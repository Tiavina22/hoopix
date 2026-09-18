import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/login_item_teardown.dart';

/// Records every call and answers from [responses] keyed by
/// `executable arg1 ...`; anything unlisted succeeds with empty output.
/// Executables in [timeOutOn] time out instead; those in [failOn] exit
/// non-zero.
class _Runner extends ProcessRunner {
  _Runner({
    this.responses = const {},
    this.timeOutOn = const {},
    this.failOn = const {},
  });

  final Map<String, ProcessResult> responses;
  final Set<String> timeOutOn;
  final Set<String> failOn;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    if (timeOutOn.contains(executable)) {
      return ProcessResult.failure(
        ProcessFailure.timedOut(executable, const Duration(seconds: 5)),
      );
    }
    if (failOn.contains(executable)) {
      // What a denied Automation permission looks like: error -1743.
      return ProcessResult.failure(
        ProcessFailure.nonZeroExit(executable, 1, 'execution error (-1743)'),
      );
    }
    return responses[[executable, ...arguments].join(' ')] ??
        ProcessResult.success('');
  }
}

void main() {
  const appPath = '/Applications/MyApp.app';
  const loginItems = '$appPath/Contents/Library/LoginItems';

  group('removeLoginItem', () {
    test('passes the name as an argument, never inside the script', () async {
      final runner = _Runner();
      final teardown = LoginItemTeardown(scriptRunner: runner);

      final result = await teardown.removeLoginItem('My "Quoted" App');

      expect(result, LaunchTeardownResult.completed);
      final call = runner.calls.single;
      expect(call.first, 'osascript');
      expect(call.last, 'My "Quoted" App');
      // osascript -e <line> -e <line> ... <name>
      final args = call.sublist(1, call.length - 1);
      expect([
        for (var i = 0; i < args.length; i += 2) args[i],
      ], everyElement('-e'));
      final script = [for (var i = 1; i < args.length; i += 2) args[i]];
      expect(script.join('\n'), isNot(contains('Quoted')));
      expect(script.first, 'on run argv');
      expect(script.last, 'end run');
    });

    test('strips a trailing .app, as login items never carry it', () async {
      final runner = _Runner();
      await LoginItemTeardown(
        scriptRunner: runner,
      ).removeLoginItem('MyApp.app');

      expect(runner.calls.single.last, 'MyApp');
    });

    test('does nothing for an empty name', () async {
      final runner = _Runner();
      await LoginItemTeardown(scriptRunner: runner).removeLoginItem('');

      expect(runner.calls, isEmpty);
    });

    test('reports a timeout, and any other failure as completed', () async {
      expect(
        await LoginItemTeardown(
          scriptRunner: _Runner(timeOutOn: {'osascript'}),
        ).removeLoginItem('MyApp'),
        LaunchTeardownResult.timedOut,
      );
      expect(
        await LoginItemTeardown(
          scriptRunner: _Runner(failOn: {'osascript'}),
        ).removeLoginItem('MyApp'),
        LaunchTeardownResult.completed,
      );
    });
  });

  group('discoverHelperIds', () {
    LoginItemTeardown teardownWith(_Runner runner, List<String> names) =>
        LoginItemTeardown(
          runner: runner,
          listNames: (dir) => dir == loginItems ? names : const [],
          typeOf: (path) => path.endsWith('/Contents/Info.plist')
              ? FileSystemEntityType.file
              : FileSystemEntityType.notFound,
        );

    String plist(String helper) => '$loginItems/$helper/Contents/Info.plist';

    test('reads each helper app bundle id, reverse-DNS ones only', () async {
      final runner = _Runner(
        responses: {
          'plutil -extract CFBundleIdentifier raw ${plist('Helper.app')}':
              ProcessResult.success('com.example.MyApp.Helper\n'),
          'plutil -extract CFBundleIdentifier raw ${plist('Odd.app')}':
              ProcessResult.success('not a bundle id\n'),
        },
      );
      final teardown = teardownWith(runner, [
        'Helper.app',
        'Odd.app',
        'README.txt',
      ]);

      expect(await teardown.discoverHelperIds(appPath), [
        'com.example.MyApp.Helper',
      ]);
      expect(runner.calls, hasLength(2));
    });

    test('a timeout yields no helpers at all', () async {
      final teardown = teardownWith(_Runner(timeOutOn: {'plutil'}), [
        'Helper.app',
      ]);

      expect(await teardown.discoverHelperIds(appPath), isEmpty);
    });

    test('an app without a LoginItems folder has no helpers', () async {
      final runner = _Runner();
      final teardown = teardownWith(runner, const []);

      expect(await teardown.discoverHelperIds(appPath), isEmpty);
      expect(runner.calls, isEmpty);
    });
  });

  group('bootoutHelpers', () {
    final uid = {'id -u': ProcessResult.success('501\n')};

    test('boots each helper out of the gui domain', () async {
      final runner = _Runner(responses: uid);

      final result = await LoginItemTeardown(
        runner: runner,
      ).bootoutHelpers(['com.example.MyApp.Helper']);

      expect(result, LaunchTeardownResult.completed);
      expect(runner.calls, [
        ['id', '-u'],
        ['launchctl', 'bootout', 'gui/501/com.example.MyApp.Helper'],
      ]);
    });

    test("never boots out Apple's namespace or a malformed id", () async {
      final runner = _Runner(responses: uid);

      await LoginItemTeardown(
        runner: runner,
      ).bootoutHelpers(['com.apple.Finder', 'not-an-id', '']);

      expect(runner.calls, isEmpty);
    });

    test('does nothing when the uid cannot be read', () async {
      final runner = _Runner();

      await LoginItemTeardown(
        runner: runner,
      ).bootoutHelpers(['com.example.MyApp.Helper']);

      expect(runner.calls, [
        ['id', '-u'],
      ]);
    });

    test('stops at the first bootout that times out', () async {
      final runner = _Runner(responses: uid, timeOutOn: {'launchctl'});

      final result = await LoginItemTeardown(
        runner: runner,
      ).bootoutHelpers(['com.example.MyApp.One', 'com.example.MyApp.Two']);

      expect(result, LaunchTeardownResult.timedOut);
      expect(runner.calls.where((c) => c.first == 'launchctl'), hasLength(1));
    });
  });
}
