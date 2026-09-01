import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/xcode_caches_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _running() => ProcessResult.success('123');
ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_xcode_caches_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<CleanSectionTargets> enumerate(
    Map<String, ProcessResult> responses,
  ) async {
    final source = XcodeCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(responses)),
    );
    return source.enumerate();
  }

  Future<List<String>> targets(Map<String, ProcessResult> responses) async =>
      (await enumerate(responses)).paths;

  const allClosed = {
    'pgrep -x Xcode': null,
    'pgrep -x xcodebuild': null,
    'pgrep -x xctest': null,
    'pgrep -x XCTRunner': null,
    'pgrep -x XCBBuildService': null,
    'pgrep -x swift-frontend': null,
  };

  Map<String, ProcessResult> closed() => {
    for (final key in allClosed.keys) key: _notRunning(),
  };

  test('section name matches the constant Developer tools uses', () async {
    final source = XcodeCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(const {})),
    );
    final result = await source.enumerate();
    expect(result.section, DeveloperToolsLocalDataSource.developerTools);
  });

  test(
    'reaches the Xcode cache, build products and DerivedData while closed',
    () async {
      await makeDir('Library/Caches/com.apple.dt.Xcode/blob');
      await makeDir('Library/Developer/Xcode/Products/blob');
      await makeDir('Library/Developer/Xcode/DerivedData/MyApp-abc123');

      final result = await targets(closed());

      expect(
        result,
        contains('${home.path}/Library/Caches/com.apple.dt.Xcode/blob'),
      );
      expect(
        result,
        contains('${home.path}/Library/Developer/Xcode/Products/blob'),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Developer/Xcode/DerivedData/MyApp-abc123',
        ),
      );
    },
  );

  test('proposes nothing while any Xcode tooling process is running', () async {
    await makeDir('Library/Developer/Xcode/DerivedData/MyApp-abc123');

    final responses = closed();
    responses['pgrep -x xcodebuild'] = _running();

    expect(await targets(responses), isEmpty);
  });

  test('proposes nothing when the process state cannot be confirmed', () async {
    await makeDir('Library/Developer/Xcode/DerivedData/MyApp-abc123');

    final responses = closed();
    responses['pgrep -x swift-frontend'] = _unknown();

    expect(await targets(responses), isEmpty);
  });

  test('a missing home tree does not throw', () async {
    expect(await targets(closed()), isEmpty);
  });

  test(
    'every proposed path carries a recheck of the same tooling processes',
    () async {
      await makeDir('Library/Caches/com.apple.dt.Xcode/blob');
      await makeDir('Library/Developer/Xcode/Products/blob');
      await makeDir('Library/Developer/Xcode/DerivedData/MyApp-abc123');

      final result = await enumerate(closed());

      for (final path in result.paths) {
        expect(
          result.recheckProcessGuards[path]?.exactNames,
          allClosed.keys.map((key) => key.substring('pgrep -x '.length)),
        );
      }
    },
  );
}
