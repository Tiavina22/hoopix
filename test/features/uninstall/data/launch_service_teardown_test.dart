import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';

class _RecordingRunner extends ProcessRunner {
  _RecordingRunner({this.timeOutOn = const {}});

  final Set<String> timeOutOn;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    if (timeOutOn.contains(arguments.last)) {
      return ProcessResult.failure(
        ProcessFailure.timedOut(executable, const Duration(seconds: 5)),
      );
    }
    // A job that was never loaded: launchctl exits non-zero.
    return ProcessResult.failure(
      ProcessFailure.nonZeroExit(executable, 1, 'Could not find'),
    );
  }
}

void main() {
  const home = '/Users/tester';
  const agentsDir = '$home/Library/LaunchAgents';
  const appPath = '/Applications/MyApp.app';

  LaunchServiceTeardown teardownWith(
    _RecordingRunner runner,
    Map<String, String> plists,
  ) => LaunchServiceTeardown(
    home: home,
    runner: runner,
    listNames: (dir) => dir == agentsDir ? plists.keys.toList() : const [],
    readBytes: (path) async =>
        utf8.encode(plists[path.substring(agentsDir.length + 1)] ?? ''),
  );

  List<String> unloaded(_RecordingRunner runner) => [
    for (final call in runner.calls)
      if (call[0] == 'launchctl' && call[1] == 'unload') call[2],
  ];

  test('unloads bundle-id plists, then plists referencing the app', () async {
    final runner = _RecordingRunner();
    final teardown = teardownWith(runner, {
      'com.example.MyApp.plist': '',
      'com.example.MyApp.helper.plist': '',
      'net.other.updater.plist': '<string>$appPath/Contents/MacOS/up</string>',
      'net.unrelated.plist': '<string>/usr/local/bin/tool</string>',
      'README.txt': appPath,
    });

    final result = await teardown.stop(
      bundleId: 'com.example.MyApp',
      appPath: appPath,
    );

    expect(result, LaunchTeardownResult.completed);
    expect(unloaded(runner), [
      '$agentsDir/com.example.MyApp.plist',
      '$agentsDir/com.example.MyApp.helper.plist',
      '$agentsDir/net.other.updater.plist',
    ]);
  });

  test(
    'a demoted bundle id still unloads agents referencing the app path',
    () async {
      final runner = _RecordingRunner();
      final teardown = teardownWith(runner, {
        'com.example.MyApp.plist': '',
        'net.other.updater.plist': appPath,
      });

      await teardown.stop(bundleId: 'unknown', appPath: appPath);

      expect(unloaded(runner), ['$agentsDir/net.other.updater.plist']);
    },
  );

  test('never unloads the same plist twice', () async {
    final runner = _RecordingRunner();
    final teardown = teardownWith(runner, {'com.example.MyApp.plist': appPath});

    await teardown.stop(bundleId: 'com.example.MyApp', appPath: appPath);

    expect(unloaded(runner), ['$agentsDir/com.example.MyApp.plist']);
  });

  test('stops at the first unload that times out', () async {
    final runner = _RecordingRunner(
      timeOutOn: {'$agentsDir/com.example.MyApp.plist'},
    );
    final teardown = teardownWith(runner, {
      'com.example.MyApp.plist': '',
      'com.example.MyApp.helper.plist': '',
    });

    final result = await teardown.stop(
      bundleId: 'com.example.MyApp',
      appPath: appPath,
    );

    expect(result, LaunchTeardownResult.timedOut);
    expect(unloaded(runner), ['$agentsDir/com.example.MyApp.plist']);
  });

  test('does nothing without a LaunchAgents directory', () async {
    final runner = _RecordingRunner();
    final teardown = teardownWith(runner, const {});

    final result = await teardown.stop(
      bundleId: 'com.example.MyApp',
      appPath: appPath,
    );

    expect(result, LaunchTeardownResult.completed);
    expect(runner.calls, isEmpty);
  });
}
