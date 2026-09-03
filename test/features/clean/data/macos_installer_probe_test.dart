import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/macos_installer_probe.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  group('identity', () {
    test('returns the trimmed stat output', () async {
      final probe = MacosInstallerProbe(
        probe: FakeProcessRunner({
          'stat -f%d:%i:%m /a/b.app': ProcessResult.success(
            '16777232:123456:1700000000\n',
          ),
        }),
      );

      expect(await probe.identity('/a/b.app'), '16777232:123456:1700000000');
    });

    test('returns null when stat fails', () async {
      final probe = MacosInstallerProbe(
        probe: FakeProcessRunner({
          'stat -f%d:%i:%m /a/b.app': ProcessResult.failure(
            ProcessFailure.notFound('stat', 'no such file'),
          ),
        }),
      );

      expect(await probe.identity('/a/b.app'), isNull);
    });
  });

  test('mtimeOf reads the trailing mtime component', () {
    const probe = MacosInstallerProbe();
    expect(probe.mtimeOf('16777232:123456:1700000000'), 1700000000);
    expect(probe.mtimeOf('not-a-valid-identity'), isNull);
  });

  group('currentMajorVersion', () {
    test('parses the major version from sw_vers', () async {
      final probe = MacosInstallerProbe(
        probe: FakeProcessRunner({
          'sw_vers -productVersion': ProcessResult.success('15.6.1\n'),
        }),
      );

      expect(await probe.currentMajorVersion(), 15);
    });

    test('returns null when sw_vers cannot be read', () async {
      final probe = MacosInstallerProbe(
        probe: FakeProcessRunner({
          'sw_vers -productVersion': ProcessResult.failure(
            ProcessFailure.notFound('sw_vers', 'not found'),
          ),
        }),
      );

      expect(await probe.currentMajorVersion(), isNull);
    });
  });

  group('installerMajorVersion', () {
    test('parses the major version from the installer Info.plist', () async {
      final probe = MacosInstallerProbe(
        probe: FakeProcessRunner({
          '/usr/libexec/PlistBuddy -c Print :DTPlatformVersion '
                  '/Applications/Install macOS Sequoia.app/Contents/Info.plist':
              ProcessResult.success('15.0\n'),
        }),
      );

      expect(
        await probe.installerMajorVersion(
          '/Applications/Install macOS Sequoia.app',
        ),
        15,
      );
    });

    test('returns null when the plist or key is missing', () async {
      final probe = MacosInstallerProbe(
        probe: FakeProcessRunner({
          '/usr/libexec/PlistBuddy -c Print :DTPlatformVersion '
                  '/Applications/Install macOS Sequoia.app/Contents/Info.plist':
              ProcessResult.failure(
                ProcessFailure.nonZeroExit(
                  'PlistBuddy',
                  1,
                  'Entry, Does Not Exist',
                ),
              ),
        }),
      );

      expect(
        await probe.installerMajorVersion(
          '/Applications/Install macOS Sequoia.app',
        ),
        isNull,
      );
    });
  });

  group('softwareUpdatePending', () {
    Future<bool> pendingFor(ProcessResult result) async {
      final probe = MacosInstallerProbe(
        probe: FakeProcessRunner({
          'plutil -extract RecommendedUpdates json -o - '
                  '/Library/Preferences/com.apple.SoftwareUpdate.plist':
              result,
        }),
      );
      return probe.softwareUpdatePending();
    }

    test('false only for an explicitly empty list', () async {
      expect(await pendingFor(ProcessResult.success('[]')), isFalse);
      expect(
        await pendingFor(ProcessResult.success('[\n]\n')),
        isFalse,
        reason: 'whitespace around the empty array must still count as clear',
      );
    });

    test('true for a non-empty list', () async {
      expect(
        await pendingFor(ProcessResult.success('[{"foo":"bar"}]')),
        isTrue,
      );
    });

    test('true (fail closed) when the plist cannot be read', () async {
      expect(
        await pendingFor(
          ProcessResult.failure(
            ProcessFailure.notFound('plutil', 'no such file'),
          ),
        ),
        isTrue,
      );
    });
  });
}
