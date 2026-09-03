import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/chromium_old_versions_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

Map<String, ProcessResult> _allClosed() => {
  'pgrep -x Google Chrome': _notRunning(),
  'pgrep -x Google Chrome Helper': _notRunning(),
  'pgrep -f /Google Chrome.app/': _notRunning(),
  'pgrep -x Microsoft Edge': _notRunning(),
  'pgrep -x Brave Browser': _notRunning(),
};

void main() {
  late Directory applications;
  late Directory home;

  setUp(() async {
    applications = await Directory.systemTemp.createTemp(
      'hoopix_chromium_apps_',
    );
    home = await Directory.systemTemp.createTemp('hoopix_chromium_home_');
  });

  tearDown(() async {
    for (final dir in [applications, home]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  String versionsDirFor(String bundle, String framework) =>
      '${applications.path}/$bundle/Contents/Frameworks/$framework/Versions';

  /// Creates a Chromium-shaped Versions directory: one directory per name
  /// in [versions], and a `Current` symlink pointing at [current].
  Future<String> makeVersions({
    String bundle = 'Google Chrome.app',
    String framework = 'Google Chrome Framework.framework',
    required List<String> versions,
    required String current,
    List<String> newerThanCurrent = const [],
  }) async {
    final versionsDir = versionsDirFor(bundle, framework);
    for (final version in versions) {
      await Directory('$versionsDir/$version').create(recursive: true);
    }
    // Backdate everything, then bring the named ones forward, so "newest by
    // mtime" is deterministic rather than dependent on creation order.
    for (final version in versions) {
      await Process.run('touch', [
        '-t',
        '202001010000',
        '$versionsDir/$version',
      ]);
    }
    await Process.run('touch', ['-t', '202101010000', '$versionsDir/$current']);
    for (final version in newerThanCurrent) {
      await Process.run('touch', [
        '-t',
        '202201010000',
        '$versionsDir/$version',
      ]);
    }
    await Link('$versionsDir/Current').create('$versionsDir/$current');
    return versionsDir;
  }

  Future<CleanSectionTargets> enumerate([
    Map<String, ProcessResult>? responses,
  ]) async {
    final source = ChromiumOldVersionsLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(responses ?? _allClosed())),
      applicationRoots: [applications.path],
    );
    return source.enumerate();
  }

  test('section name matches the constant Browsers uses', () async {
    final result = await enumerate();
    expect(result.section, CleanSectionsLocalDataSource.browsers);
  });

  test('removes every version except Current while Chrome is closed', () async {
    final versionsDir = await makeVersions(
      versions: ['120.0.1', '121.0.1', '122.0.1'],
      current: '122.0.1',
    );

    final result = await enumerate();

    expect(result.paths, ['$versionsDir/120.0.1', '$versionsDir/121.0.1']);
  });

  test('keeps a staged update newer than Current', () async {
    final versionsDir = await makeVersions(
      versions: ['120.0.1', '121.0.1', '123.0.1'],
      current: '121.0.1',
      newerThanCurrent: ['123.0.1'],
    );

    final result = await enumerate();

    expect(result.paths, ['$versionsDir/120.0.1']);
  });

  test('proposes nothing when there is no Current symlink', () async {
    final versionsDir = versionsDirFor(
      'Google Chrome.app',
      'Google Chrome Framework.framework',
    );
    await Directory('$versionsDir/120.0.1').create(recursive: true);
    await Directory('$versionsDir/121.0.1').create(recursive: true);

    expect((await enumerate()).paths, isEmpty);
  });

  test('proposes nothing when Current points at a missing version', () async {
    final versionsDir = await makeVersions(
      versions: ['120.0.1', '121.0.1'],
      current: '121.0.1',
    );
    await Directory('$versionsDir/121.0.1').delete(recursive: true);

    expect((await enumerate()).paths, isEmpty);
  });

  test('proposes nothing while the browser is running', () async {
    await makeVersions(versions: ['120.0.1', '121.0.1'], current: '121.0.1');

    final responses = _allClosed();
    responses['pgrep -x Google Chrome'] = _running();

    expect((await enumerate(responses)).paths, isEmpty);
  });

  test('proposes nothing when the process state cannot be confirmed', () async {
    await makeVersions(versions: ['120.0.1', '121.0.1'], current: '121.0.1');

    final responses = _allClosed();
    responses['pgrep -f /Google Chrome.app/'] = _unknown();

    expect((await enumerate(responses)).paths, isEmpty);
  });

  test('each browser is guarded independently', () async {
    final chromeVersions = await makeVersions(
      versions: ['120.0.1', '121.0.1'],
      current: '121.0.1',
    );
    final braveVersions = await makeVersions(
      bundle: 'Brave Browser.app',
      framework: 'Brave Browser Framework.framework',
      versions: ['1.60.0', '1.61.0'],
      current: '1.61.0',
    );

    final responses = _allClosed();
    responses['pgrep -x Google Chrome'] = _running();

    final result = await enumerate(responses);

    expect(result.paths, ['$braveVersions/1.60.0']);
    expect(result.paths.any((p) => p.startsWith(chromeVersions)), isFalse);
  });

  test('every candidate carries its own browser process recheck', () async {
    final versionsDir = await makeVersions(
      bundle: 'Microsoft Edge.app',
      framework: 'Microsoft Edge Framework.framework',
      versions: ['130.0.1', '131.0.1'],
      current: '131.0.1',
    );

    final result = await enumerate();

    expect(result.recheckProcessGuards['$versionsDir/130.0.1']?.exactNames, [
      'Microsoft Edge',
    ]);
  });

  test('a missing application does not throw', () async {
    expect((await enumerate()).paths, isEmpty);
  });
}
