import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_services_registration.dart';

const _lsregisterPath =
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/'
    'LaunchServices.framework/Support/lsregister';

class _RecordingRunner extends ProcessRunner {
  _RecordingRunner({this.timeOut = false});

  final bool timeOut;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    if (timeOut) {
      return ProcessResult.failure(
        ProcessFailure.timedOut(executable, const Duration(seconds: 5)),
      );
    }
    return ProcessResult.success('');
  }
}

void main() {
  const appPath = '/Applications/MyApp.app';

  LaunchServicesRegistration registrationWith({
    ProcessRunner? runner,
    ProcessRunner? refreshRunner,
    Set<String> existingPaths = const {appPath, _lsregisterPath},
  }) => LaunchServicesRegistration(
    runner: runner,
    refreshRunner: refreshRunner,
    typeOf: (path) => existingPaths.contains(path)
        ? FileSystemEntityType.file
        : FileSystemEntityType.notFound,
  );

  group('unregisterApp', () {
    test('runs lsregister -u on the app bundle', () async {
      final runner = _RecordingRunner();
      final registration = registrationWith(runner: runner);

      final result = await registration.unregisterApp(appPath);

      expect(result, LaunchTeardownResult.completed);
      expect(runner.calls, [
        [_lsregisterPath, '-u', appPath],
      ]);
    });

    test('does nothing for a path that is not a .app bundle', () async {
      final runner = _RecordingRunner();
      final registration = registrationWith(runner: runner);

      await registration.unregisterApp('/Applications/MyApp');

      expect(runner.calls, isEmpty);
    });

    test('does nothing once the app no longer exists on disk', () async {
      final runner = _RecordingRunner();
      final registration = registrationWith(
        runner: runner,
        existingPaths: {_lsregisterPath},
      );

      await registration.unregisterApp(appPath);

      expect(runner.calls, isEmpty);
    });

    test('does nothing when no lsregister binary can be found', () async {
      final runner = _RecordingRunner();
      final registration = registrationWith(
        runner: runner,
        existingPaths: {appPath},
      );

      await registration.unregisterApp(appPath);

      expect(runner.calls, isEmpty);
    });

    test(
      'reports a timeout as timedOut, any other failure as completed',
      () async {
        final registration = registrationWith(
          runner: _RecordingRunner(timeOut: true),
        );

        expect(
          await registration.unregisterApp(appPath),
          LaunchTeardownResult.timedOut,
        );
      },
    );
  });

  group('refresh', () {
    test('rebuilds every LaunchServices domain', () async {
      final runner = _RecordingRunner();
      final registration = registrationWith(refreshRunner: runner);

      await registration.refresh();

      expect(runner.calls, [
        [
          _lsregisterPath,
          '-r',
          '-f',
          '-domain',
          'local',
          '-domain',
          'user',
          '-domain',
          'system',
        ],
      ]);
    });

    test('does nothing when no lsregister binary can be found', () async {
      final runner = _RecordingRunner();
      final registration = registrationWith(
        refreshRunner: runner,
        existingPaths: const {},
      );

      await registration.refresh();

      expect(runner.calls, isEmpty);
    });

    test('a timeout is swallowed rather than thrown', () async {
      final registration = registrationWith(
        refreshRunner: _RecordingRunner(timeOut: true),
      );

      await expectLater(registration.refresh(), completes);
    });
  });
}
