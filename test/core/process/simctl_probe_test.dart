import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/core/process/simctl_probe.dart';

import '../../support/fake_process_runner.dart';

ProcessResult _fail() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('xcrun', 1, ''));

const _bootedJson =
    '{"devices":{"iOS 18.0":[{"udid":"ABC","state":"Booted"}]}}';
const _emptyJson = '{"devices":{"iOS 18.0":[]}}';

void main() {
  late Directory applications;

  setUp(() async {
    applications = await Directory.systemTemp.createTemp('hoopix_simctl_apps_');
  });

  tearDown(() async {
    if (applications.existsSync()) await applications.delete(recursive: true);
  });

  String bootedCommand(String developerDir) =>
      'env DEVELOPER_DIR=$developerDir xcrun simctl list devices booted -j';
  String findCommand(String developerDir) =>
      'env DEVELOPER_DIR=$developerDir xcrun --find simctl';

  SimctlProbe probeWith(
    Map<String, ProcessResult> responses, {
    String? explicitDeveloperDir,
  }) => SimctlProbe(
    probe: FakeProcessRunner(responses),
    xcodeAppRoots: [applications.path],
    explicitDeveloperDir: explicitDeveloperDir,
    readEnvironment: false,
  );

  group('an explicit DEVELOPER_DIR', () {
    test('is used when it provides simctl', () async {
      final probe = probeWith({
        findCommand(applications.path): ProcessResult.success('/path/simctl'),
        bootedCommand(applications.path): ProcessResult.success(_bootedJson),
      }, explicitDeveloperDir: applications.path);

      expect(await probe.bootedDeviceState(), ProcessLiveness.running);
    });

    test('never falls through to another Xcode when it is invalid', () async {
      await Directory(
        '${applications.path}/Xcode.app/Contents/Developer',
      ).create(recursive: true);

      final probe = probeWith({
        // The explicit directory cannot find simctl...
        findCommand(applications.path): _fail(),
        // ...while an installed Xcode could, and must still not be used.
        findCommand('${applications.path}/Xcode.app/Contents/Developer'):
            ProcessResult.success('/path/simctl'),
        bootedCommand('${applications.path}/Xcode.app/Contents/Developer'):
            ProcessResult.success(_emptyJson),
      }, explicitDeveloperDir: applications.path);

      expect(await probe.bootedDeviceState(), ProcessLiveness.unknown);
    });
  });

  group('the selected developer directory', () {
    test('is used when it provides simctl', () async {
      final probe = probeWith({
        'xcode-select -p': ProcessResult.success('${applications.path}\n'),
        findCommand(applications.path): ProcessResult.success('/path/simctl'),
        bootedCommand(applications.path): ProcessResult.success(_emptyJson),
      });

      expect(await probe.bootedDeviceState(), ProcessLiveness.notRunning);
    });

    test('is unknown when xcode-select reports nothing', () async {
      final probe = probeWith({'xcode-select -p': _fail()});

      expect(await probe.bootedDeviceState(), ProcessLiveness.unknown);
    });
  });

  group('a Command Line Tools selection', () {
    Future<String> makeXcodeApp(String name) async {
      final developerDir = '${applications.path}/$name/Contents/Developer';
      await Directory(developerDir).create(recursive: true);
      return developerDir;
    }

    test('falls back to the one installed Xcode', () async {
      final developerDir = await makeXcodeApp('Xcode.app');

      final probe = probeWith({
        'xcode-select -p': ProcessResult.success(
          '/Library/Developer/CommandLineTools',
        ),
        findCommand(developerDir): ProcessResult.success('/path/simctl'),
        bootedCommand(developerDir): ProcessResult.success(_bootedJson),
      });

      expect(await probe.bootedDeviceState(), ProcessLiveness.running);
    });

    test('refuses to choose between two usable Xcodes', () async {
      final first = await makeXcodeApp('Xcode.app');
      final second = await makeXcodeApp('Xcode-beta.app');

      final probe = probeWith({
        'xcode-select -p': ProcessResult.success(
          '/Library/Developer/CommandLineTools',
        ),
        findCommand(first): ProcessResult.success('/path/simctl'),
        findCommand(second): ProcessResult.success('/path/simctl'),
        bootedCommand(first): ProcessResult.success(_emptyJson),
        bootedCommand(second): ProcessResult.success(_emptyJson),
      });

      expect(await probe.bootedDeviceState(), ProcessLiveness.unknown);
    });

    test('is unknown when no Xcode is installed at all', () async {
      final probe = probeWith({
        'xcode-select -p': ProcessResult.success(
          '/Library/Developer/CommandLineTools',
        ),
      });

      expect(await probe.bootedDeviceState(), ProcessLiveness.unknown);
    });
  });

  group('the booted-device response', () {
    Future<ProcessLiveness> stateFor(ProcessResult result) async {
      final probe = probeWith({
        'xcode-select -p': ProcessResult.success(applications.path),
        findCommand(applications.path): ProcessResult.success('/path/simctl'),
        bootedCommand(applications.path): result,
      });
      return probe.bootedDeviceState();
    }

    test('running when a device udid is listed', () async {
      expect(
        await stateFor(ProcessResult.success(_bootedJson)),
        ProcessLiveness.running,
      );
    });

    test('not running for a valid empty list', () async {
      expect(
        await stateFor(ProcessResult.success(_emptyJson)),
        ProcessLiveness.notRunning,
      );
    });

    test('unknown for a response of an unexpected shape', () async {
      expect(
        await stateFor(ProcessResult.success('not json at all')),
        ProcessLiveness.unknown,
      );
    });

    test('unknown when the probe itself fails', () async {
      expect(await stateFor(_fail()), ProcessLiveness.unknown);
    });
  });
}
