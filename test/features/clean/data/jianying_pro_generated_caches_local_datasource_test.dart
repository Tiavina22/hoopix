import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/jianying_pro_generated_caches_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

final _closed = {
  'pgrep -x VideoFusion-macOS': _notRunning(),
  'pgrep -f /VideoFusion-macOS.app/Contents/MacOS/VideoFusion-macOS':
      _notRunning(),
};

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp(
      'hoopix_jianyingpro_caches_home_',
    );
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<List<String>> targets(Map<String, ProcessResult> responses) async {
    final source = JianyingProGeneratedCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(responses)),
    );
    return (await source.enumerate()).paths;
  }

  test('section name matches the constant Apps & utilities uses', () async {
    final source = JianyingProGeneratedCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(const {})),
    );
    final result = await source.enumerate();
    expect(result.section, AppsAndUtilitiesLocalDataSource.appsAndUtilities);
  });

  test(
    'reaches every regenerable subdirectory that exists while closed',
    () async {
      await makeDir('Movies/JianyingPro/User Data/Cache/recognize');
      await makeDir('Movies/JianyingPro/User Data/Cache/tmp');
      // Not on the allowlist: must never be proposed.
      await makeDir('Movies/JianyingPro/User Data/Cache/image');
      await makeDir('Movies/JianyingPro/User Data/Cache/importcache3');

      final result = await targets(_closed);

      expect(
        result,
        contains('${home.path}/Movies/JianyingPro/User Data/Cache/recognize'),
      );
      expect(
        result,
        contains('${home.path}/Movies/JianyingPro/User Data/Cache/tmp'),
      );
      expect(
        result,
        isNot(
          contains('${home.path}/Movies/JianyingPro/User Data/Cache/image'),
        ),
      );
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Movies/JianyingPro/User Data/Cache/importcache3',
          ),
        ),
      );
    },
  );

  test('does not propose a subdirectory that does not exist', () async {
    await makeDir('Movies/JianyingPro/User Data/Cache/recognize');

    final result = await targets(_closed);

    expect(result, [
      '${home.path}/Movies/JianyingPro/User Data/Cache/recognize',
    ]);
  });

  test('proposes nothing when the cache root does not exist', () async {
    final result = await targets(_closed);

    expect(result, isEmpty);
  });

  test('proposes nothing while the main editor process is running', () async {
    await makeDir('Movies/JianyingPro/User Data/Cache/recognize');

    final result = await targets({
      'pgrep -x VideoFusion-macOS': _running(),
      'pgrep -f /VideoFusion-macOS.app/Contents/MacOS/VideoFusion-macOS':
          _notRunning(),
    });

    expect(result, isEmpty);
  });

  test('proposes nothing when the process state cannot be confirmed', () async {
    await makeDir('Movies/JianyingPro/User Data/Cache/recognize');

    final result = await targets({
      'pgrep -x VideoFusion-macOS': _unknown(),
      'pgrep -f /VideoFusion-macOS.app/Contents/MacOS/VideoFusion-macOS':
          _notRunning(),
    });

    expect(result, isEmpty);
  });
}
