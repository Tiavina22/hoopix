import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/cloud_storage_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _running() => ProcessResult.success('123');
ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_cloud_storage_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<List<String>> targets(Map<String, ProcessResult> responses) async {
    final source = CloudStorageLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(responses)),
    );
    return (await source.enumerate()).paths;
  }

  test('section name matches the constant Cloud & Office uses', () async {
    final source = CloudStorageLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(const {})),
    );
    final result = await source.enumerate();
    expect(result.section, CleanSectionsLocalDataSource.cloudAndOffice);
  });

  group('Dropbox', () {
    test(
      'reaches the default cache and every com.dropbox.* variant while closed',
      () async {
        await makeDir('Library/Caches/com.getdropbox.dropbox');
        await makeDir('Library/Caches/com.dropbox.Helper');

        final result = await targets({'pgrep -x Dropbox': _notRunning()});

        expect(
          result,
          contains('${home.path}/Library/Caches/com.getdropbox.dropbox'),
        );
        expect(
          result,
          contains('${home.path}/Library/Caches/com.dropbox.Helper'),
        );
      },
    );

    test('proposes nothing while Dropbox is running', () async {
      final result = await targets({'pgrep -x Dropbox': _running()});

      expect(result, isEmpty);
    });

    test(
      'proposes nothing when Dropbox\'s process state cannot be confirmed',
      () async {
        final result = await targets({'pgrep -x Dropbox': _unknown()});

        expect(result, isEmpty);
      },
    );
  });

  test('reaches Google Drive while closed', () async {
    final result = await targets({'pgrep -x Google Drive': _notRunning()});

    expect(
      result,
      contains('${home.path}/Library/Caches/com.google.GoogleDrive'),
    );
  });

  test('proposes nothing for Google Drive while it is running', () async {
    final result = await targets({'pgrep -x Google Drive': _running()});

    expect(result, isEmpty);
  });

  test('reaches OneDrive while closed', () async {
    final result = await targets({'pgrep -x OneDrive': _notRunning()});

    expect(
      result,
      contains('${home.path}/Library/Caches/com.microsoft.OneDrive'),
    );
  });

  test('proposes nothing for OneDrive while it is running', () async {
    final result = await targets({'pgrep -x OneDrive': _running()});

    expect(result, isEmpty);
  });

  test('each service is guarded independently', () async {
    final result = await targets({
      'pgrep -x Dropbox': _running(),
      'pgrep -x Google Drive': _notRunning(),
      'pgrep -x OneDrive': _notRunning(),
    });

    expect(result.any((p) => p.contains('dropbox')), isFalse);
    expect(
      result,
      contains('${home.path}/Library/Caches/com.google.GoogleDrive'),
    );
    expect(
      result,
      contains('${home.path}/Library/Caches/com.microsoft.OneDrive'),
    );
  });

  test('a missing home tree does not throw', () async {
    final result = await targets({
      'pgrep -x Dropbox': _notRunning(),
      'pgrep -x Google Drive': _notRunning(),
      'pgrep -x OneDrive': _notRunning(),
    });

    expect(
      result,
      unorderedEquals([
        '${home.path}/Library/Caches/com.getdropbox.dropbox',
        '${home.path}/Library/Caches/com.google.GoogleDrive',
        '${home.path}/Library/Caches/com.microsoft.OneDrive',
      ]),
    );
  });
}
