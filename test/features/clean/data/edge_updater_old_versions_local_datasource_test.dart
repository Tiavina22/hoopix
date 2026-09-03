import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/edge_updater_old_versions_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');

void main() {
  group('compareVersionStrings', () {
    test('orders dotted numeric versions numerically, not lexically', () {
      expect(compareVersionStrings('131.0.2903.86', '131.0.2903.9'), 1);
      expect(compareVersionStrings('9.0.0', '10.0.0'), -1);
      expect(compareVersionStrings('131.0.1', '131.0.1'), 0);
    });

    test('a shorter version sorts before a longer one sharing its prefix', () {
      expect(compareVersionStrings('1.2', '1.2.3'), -1);
      expect(compareVersionStrings('1.2.3', '1.2'), 1);
    });
  });

  late Directory home;
  late Directory applications;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_edge_updater_home_');
    applications = await Directory.systemTemp.createTemp(
      'hoopix_edge_updater_apps_',
    );
  });

  tearDown(() async {
    for (final dir in [home, applications]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  String updaterDir() =>
      '${home.path}/Library/Application Support/Microsoft/EdgeUpdater'
      '/apps/msedge-stable';

  Future<void> makeVersions(List<String> versions) async {
    for (final version in versions) {
      await Directory('${updaterDir()}/$version').create(recursive: true);
    }
  }

  /// Creates an Edge bundle whose Info.plist the probe can read.
  Future<String> makeEdgeApp() async {
    final plist = '${applications.path}/Microsoft Edge.app/Contents/Info.plist';
    await File(plist).create(recursive: true);
    return plist;
  }

  Future<CleanSectionTargets> enumerate({
    Map<String, ProcessResult> responses = const {},
    bool edgeRunning = false,
  }) async {
    final source = EdgeUpdaterOldVersionsLocalDataSource(
      home: home.path,
      guard: ProcessGuard(
        FakeProcessRunner({
          'pgrep -x Microsoft Edge': edgeRunning ? _running() : _notRunning(),
        }),
      ),
      probe: FakeProcessRunner(responses),
      applicationRoots: [applications.path],
    );
    return source.enumerate();
  }

  test('section name matches the constant Browsers uses', () async {
    final result = await enumerate();
    expect(result.section, CleanSectionsLocalDataSource.browsers);
  });

  test(
    'removes only payloads strictly older than the installed Edge',
    () async {
      await makeVersions(['130.0.1', '131.0.1', '132.0.1']);
      final plist = await makeEdgeApp();

      final result = await enumerate(
        responses: {
          'plutil -extract CFBundleShortVersionString raw $plist':
              ProcessResult.success('131.0.1\n'),
        },
      );

      // 131 is installed, 132 is a pending update: only 130 is a leftover.
      expect(result.paths, ['${updaterDir()}/130.0.1']);
    },
  );

  test(
    'without an installed version, keeps the highest of several payloads',
    () async {
      await makeVersions(['130.0.1', '131.0.1', '9.0.1']);

      final result = await enumerate();

      expect(
        result.paths,
        unorderedEquals(['${updaterDir()}/130.0.1', '${updaterDir()}/9.0.1']),
      );
    },
  );

  test(
    'without an installed version, a lone payload is never removed',
    () async {
      await makeVersions(['131.0.1']);

      expect((await enumerate()).paths, isEmpty);
    },
  );

  test('proposes nothing while Edge is running', () async {
    await makeVersions(['130.0.1', '131.0.1']);

    expect((await enumerate(edgeRunning: true)).paths, isEmpty);
  });

  test('every candidate carries an Edge process recheck', () async {
    await makeVersions(['130.0.1', '131.0.1']);

    final result = await enumerate();

    expect(result.recheckProcessGuards['${updaterDir()}/130.0.1']?.exactNames, [
      'Microsoft Edge',
    ]);
  });

  test('a missing updater directory does not throw', () async {
    expect((await enumerate()).paths, isEmpty);
  });
}
