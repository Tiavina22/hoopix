import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/final_cut_pro_generated_caches_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

final _closed = {
  'pgrep -x Final Cut Pro': _notRunning(),
  'pgrep -f /Final Cut Pro.app/': _notRunning(),
};

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_fcp_caches_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<CleanSectionTargets> enumerate(
    Map<String, ProcessResult> responses,
  ) async {
    final source = FinalCutProGeneratedCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(responses)),
    );
    return source.enumerate();
  }

  Future<List<String>> targets(Map<String, ProcessResult> responses) async =>
      (await enumerate(responses)).paths;

  test('section name matches the constant Apps & utilities uses', () async {
    final result = await enumerate(const {});
    expect(result.section, AppsAndUtilitiesLocalDataSource.appsAndUtilities);
  });

  test(
    'reaches render and proxy media inside a library while FCP is closed',
    () async {
      await makeDir(
        'Movies/MyLibrary.fcpbundle/Event 1/Render Files/High Quality Media',
      );
      await makeDir(
        'Movies/MyLibrary.fcpbundle/Project 1/Transcoded Media/Proxy Media',
      );

      final result = await targets(_closed);

      expect(
        result,
        contains(
          '${home.path}/Movies/MyLibrary.fcpbundle/Event 1/Render Files'
          '/High Quality Media',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Movies/MyLibrary.fcpbundle/Project 1/Transcoded Media'
          '/Proxy Media',
        ),
      );
    },
  );

  test('never descends into Original Media, Analysis Files, Motion Templates '
      'or Final Cut Pro Backups', () async {
    for (final protectedName in [
      'Original Media',
      'Analysis Files',
      'Motion Templates',
      'Final Cut Pro Backups',
    ]) {
      await makeDir(
        'Movies/MyLibrary.fcpbundle/$protectedName/Render Files'
        '/High Quality Media',
      );
    }

    final result = await targets(_closed);

    expect(result, isEmpty);
  });

  test('finds a library nested up to 4 directories under Movies', () async {
    await makeDir(
      'Movies/a/b/c/Deep.fcpbundle/Event/Render Files/High Quality Media',
    );

    final result = await targets(_closed);

    expect(
      result,
      contains(
        '${home.path}/Movies/a/b/c/Deep.fcpbundle/Event/Render Files'
        '/High Quality Media',
      ),
    );
  });

  test(
    'does not find a library nested past 4 directories under Movies',
    () async {
      await makeDir(
        'Movies/a/b/c/d/TooDeep.fcpbundle/Event/Render Files/High Quality Media',
      );

      final result = await targets(_closed);

      expect(result, isEmpty);
    },
  );

  test('does not treat a High Quality Media directory outside Render Files as '
      'a target', () async {
    await makeDir(
      'Movies/MyLibrary.fcpbundle/Event 1/Not Render Files/High Quality Media',
    );

    final result = await targets(_closed);

    expect(result, isEmpty);
  });

  test('proposes nothing while Final Cut Pro is running', () async {
    await makeDir(
      'Movies/MyLibrary.fcpbundle/Event 1/Render Files/High Quality Media',
    );

    final result = await targets({
      'pgrep -x Final Cut Pro': _running(),
      'pgrep -f /Final Cut Pro.app/': _notRunning(),
    });

    expect(result, isEmpty);
  });

  test('proposes nothing when the process state cannot be confirmed', () async {
    await makeDir(
      'Movies/MyLibrary.fcpbundle/Event 1/Render Files/High Quality Media',
    );

    final result = await targets({
      'pgrep -x Final Cut Pro': _unknown(),
      'pgrep -f /Final Cut Pro.app/': _notRunning(),
    });

    expect(result, isEmpty);
  });

  test(
    'every proposed path carries a recheck of the Final Cut Pro process',
    () async {
      await makeDir(
        'Movies/MyLibrary.fcpbundle/Event 1/Render Files/High Quality Media',
      );

      final result = await enumerate(_closed);

      final target =
          '${home.path}/Movies/MyLibrary.fcpbundle/Event 1/Render Files'
          '/High Quality Media';
      expect(result.recheckProcessGuards[target]?.exactNames, [
        'Final Cut Pro',
      ]);
      expect(result.recheckProcessGuards[target]?.patterns, [
        '/Final Cut Pro.app/',
      ]);
    },
  );

  test(
    'a missing Movies directory proposes nothing and does not throw',
    () async {
      expect(await targets(_closed), isEmpty);
    },
  );
}
