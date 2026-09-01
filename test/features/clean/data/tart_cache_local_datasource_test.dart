import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/tart_cache_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _success() => ProcessResult.success('ok');
ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));
ProcessResult _notFound() =>
    ProcessResult.failure(ProcessFailure.notFound('tart', 'not found'));

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_tart_cache_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<CleanSectionTargets> enumerate({
    required ProcessResult versionProbe,
    required ProcessResult pgrepResponse,
  }) {
    final source = TartCacheLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner({'pgrep -x tart': pgrepResponse})),
      probe: FakeProcessRunner({'tart --version': versionProbe}),
    );
    return source.enumerate();
  }

  test('section name matches the constant Virtualization uses', () async {
    final result = await enumerate(
      versionProbe: _notFound(),
      pgrepResponse: _notRunning(),
    );
    expect(result.section, CleanSectionsLocalDataSource.virtualization);
  });

  test(
    'proposes the cache root with its prune command and a recheck guard '
    'when tart is installed, its cache exists, and it is not running',
    () async {
      await Directory('${home.path}/.tart/cache').create(recursive: true);

      final result = await enumerate(
        versionProbe: _success(),
        pgrepResponse: _notRunning(),
      );

      final cacheRoot = '${home.path}/.tart/cache';
      expect(result.paths, [cacheRoot]);
      expect(result.ownerCommands[cacheRoot], [
        'tart',
        'prune',
        '--entries',
        'caches',
        '--older-than',
        '30',
      ]);
      expect(result.ownerCommandRechecks[cacheRoot], ['tart']);
    },
  );

  test('proposes nothing when the cache directory does not exist', () async {
    final result = await enumerate(
      versionProbe: _success(),
      pgrepResponse: _notRunning(),
    );

    expect(result.paths, isEmpty);
  });

  test('proposes nothing when tart is not installed', () async {
    await Directory('${home.path}/.tart/cache').create(recursive: true);

    final result = await enumerate(
      versionProbe: _notFound(),
      pgrepResponse: _notRunning(),
    );

    expect(result.paths, isEmpty);
  });

  test('proposes nothing while tart is running', () async {
    await Directory('${home.path}/.tart/cache').create(recursive: true);

    final result = await enumerate(
      versionProbe: _success(),
      pgrepResponse: _running(),
    );

    expect(result.paths, isEmpty);
  });

  test('proposes nothing when the process state cannot be confirmed', () async {
    await Directory('${home.path}/.tart/cache').create(recursive: true);

    final result = await enumerate(
      versionProbe: _success(),
      pgrepResponse: _unknown(),
    );

    expect(result.paths, isEmpty);
  });
}
