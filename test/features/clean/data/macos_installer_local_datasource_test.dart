import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/macos_installer_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/macos_installer_probe.dart';
import 'package:hoopix/features/clean/data/datasources/system_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

const _installerPath = '/Applications/Install macOS Sequoia.app';

/// Twenty days ago, in epoch seconds — comfortably past the 14-day floor.
int get _oldMtime =>
    DateTime.now().subtract(const Duration(days: 20)).millisecondsSinceEpoch ~/
    1000;

/// Five days ago — under the 14-day floor.
int get _recentMtime =>
    DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch ~/
    1000;

Map<String, ProcessResult> _eligibleResponses({int? mtime}) => {
  'sw_vers -productVersion': ProcessResult.success('15.6.1'),
  'stat -f%d:%i:%m $_installerPath': ProcessResult.success(
    '16777232:123456:${mtime ?? _oldMtime}',
  ),
  'plutil -extract RecommendedUpdates json -o - '
          '/Library/Preferences/com.apple.SoftwareUpdate.plist':
      ProcessResult.success('[]'),
  'pgrep -f $_installerPath': ProcessResult.failure(
    ProcessFailure.nonZeroExit('pgrep', 1, ''),
  ),
  '/usr/libexec/PlistBuddy -c Print :DTPlatformVersion '
      '$_installerPath/Contents/Info.plist': ProcessResult.success(
    '14.0',
  ),
};

void main() {
  late Directory applications;

  setUp(() async {
    applications = await Directory.systemTemp.createTemp(
      'hoopix_macos_installer_apps_',
    );
    await Directory(
      '${applications.path}/Install macOS Sequoia.app',
    ).create(recursive: true);
  });

  tearDown(() async {
    if (applications.existsSync()) await applications.delete(recursive: true);
  });

  Future<CleanSectionTargets> enumerate(
    Map<String, ProcessResult> responses,
  ) async {
    final rewritten = {
      for (final entry in responses.entries)
        entry.key.replaceAll(_installerPath, _appPath(applications)):
            entry.value,
    };
    final source = MacosInstallerLocalDataSource(
      probe: MacosInstallerProbe(probe: FakeProcessRunner(rewritten)),
      guard: ProcessGuard(FakeProcessRunner(rewritten)),
      directory: (path) =>
          path == '/Applications' ? applications : Directory(path),
    );
    return source.enumerate();
  }

  test('section name matches the constant System uses', () async {
    final result = await enumerate(const {});
    expect(result.section, SystemLocalDataSource.system);
  });

  test('proposes an installer older than 14 days, idle, with no pending '
      'update, whose major version differs from the running one', () async {
    final result = await enumerate(_eligibleResponses());

    final path = _appPath(applications);
    expect(result.paths, [path]);
    expect(result.privilegedDeletionPaths, {path});
    expect(result.recheckProcessGuards[path]?.patterns, [path]);
    expect(
      result.privilegedTargetRechecks[path]?.expectedIdentity,
      '16777232:123456:$_oldMtime',
    );
    expect(
      result.privilegedTargetRechecks[path]?.requireSoftwareUpdateNotPending,
      isTrue,
    );
  });

  test(
    'proposes nothing when the current macOS version cannot be read',
    () async {
      final responses = {..._eligibleResponses()};
      responses['sw_vers -productVersion'] = ProcessResult.failure(
        ProcessFailure.notFound('sw_vers', 'not found'),
      );

      expect((await enumerate(responses)).paths, isEmpty);
    },
  );

  test('proposes nothing when the installer is younger than 14 days', () async {
    final responses = _eligibleResponses(mtime: _recentMtime);

    expect((await enumerate(responses)).paths, isEmpty);
  });

  test(
    'proposes nothing when a software update is pending or unknown',
    () async {
      final responses = {..._eligibleResponses()};
      responses['plutil -extract RecommendedUpdates json -o - '
              '/Library/Preferences/com.apple.SoftwareUpdate.plist'] =
          ProcessResult.success('[{"foo":"bar"}]');

      expect((await enumerate(responses)).paths, isEmpty);
    },
  );

  test('proposes nothing while the installer process is running', () async {
    final responses = {..._eligibleResponses()};
    responses['pgrep -f ${_appPath(applications)}'] = ProcessResult.success(
      '123',
    );

    expect((await enumerate(responses)).paths, isEmpty);
  });

  test(
    'proposes nothing when the installer matches the running major version',
    () async {
      final responses = {..._eligibleResponses()};
      responses['/usr/libexec/PlistBuddy -c Print :DTPlatformVersion '
              '${_appPath(applications)}/Contents/Info.plist'] =
          ProcessResult.success('15.0');

      expect((await enumerate(responses)).paths, isEmpty);
    },
  );

  test('proposes nothing when the installer version cannot be read', () async {
    final responses = {..._eligibleResponses()};
    responses['/usr/libexec/PlistBuddy -c Print :DTPlatformVersion '
            '${_appPath(applications)}/Contents/Info.plist'] =
        ProcessResult.failure(
          ProcessFailure.nonZeroExit('PlistBuddy', 1, 'Entry, Does Not Exist'),
        );

    expect((await enumerate(responses)).paths, isEmpty);
  });

  test('ignores an /Applications entry that is not an installer app', () async {
    await Directory(
      '${applications.path}/Google Chrome.app',
    ).create(recursive: true);

    final result = await enumerate(_eligibleResponses());

    expect(result.paths.any((p) => p.contains('Google Chrome')), isFalse);
  });
}

String _appPath(Directory applications) =>
    '${applications.path}/Install macOS Sequoia.app';
