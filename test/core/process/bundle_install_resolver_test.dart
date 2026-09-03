import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';

import '../../support/fake_process_runner.dart';

ProcessResult _mdfindMiss() => ProcessResult.success('');
ProcessResult _mdfindFail() =>
    ProcessResult.failure(ProcessFailure.notFound('mdfind', 'not found'));

void main() {
  group('isReverseDnsBundleId', () {
    test('accepts a dotted reverse-DNS id', () {
      expect(isReverseDnsBundleId('com.example.App'), isTrue);
    });

    test('rejects a bare name, empty string, or "unknown"', () {
      expect(isReverseDnsBundleId('netbird'), isFalse);
      expect(isReverseDnsBundleId(''), isFalse);
      expect(isReverseDnsBundleId('unknown'), isFalse);
    });
  });

  late Directory applications;

  setUp(() async {
    applications = await Directory.systemTemp.createTemp(
      'hoopix_bundle_resolver_apps_',
    );
  });

  tearDown(() async {
    if (applications.existsSync()) await applications.delete(recursive: true);
  });

  Future<void> makeApp(String name, {required String bundleId}) async {
    final infoPlist = '${applications.path}/$name/Contents/Info.plist';
    await File(infoPlist).create(recursive: true);
  }

  BundleInstallResolver resolverWith(Map<String, ProcessResult> responses) =>
      BundleInstallResolver(
        probe: FakeProcessRunner(responses),
        appRoots: [applications.path],
      );

  test('finds a match via mdfind without touching the filesystem', () async {
    final resolver = BundleInstallResolver(
      probe: FakeProcessRunner({
        "mdfind kMDItemCFBundleIdentifier == 'com.example.App'":
            ProcessResult.success('/Applications/App.app\n'),
      }),
      appRoots: const [],
    );

    expect(await resolver.hasInstalledApp('com.example.App'), isTrue);
  });

  test('rejects a non-reverse-DNS id outright', () async {
    final resolver = resolverWith(const {});

    expect(await resolver.hasInstalledApp('netbird'), isFalse);
  });

  group('the filesystem fallback', () {
    test(
      'matches an app whose Info.plist carries the exact bundle id',
      () async {
        await makeApp('App.app', bundleId: 'com.example.App');
        final infoPlist = '${applications.path}/App.app/Contents/Info.plist';

        final resolver = resolverWith({
          "mdfind kMDItemCFBundleIdentifier == 'com.example.App'":
              _mdfindMiss(),
          'plutil -extract CFBundleIdentifier raw $infoPlist':
              ProcessResult.success('com.example.App'),
        });

        expect(await resolver.hasInstalledApp('com.example.App'), isTrue);
      },
    );

    test('compares bundle ids case-insensitively', () async {
      await makeApp('App.app', bundleId: 'com.example.App');
      final infoPlist = '${applications.path}/App.app/Contents/Info.plist';

      final resolver = resolverWith({
        "mdfind kMDItemCFBundleIdentifier == 'COM.EXAMPLE.APP'": _mdfindMiss(),
        'plutil -extract CFBundleIdentifier raw $infoPlist':
            ProcessResult.success('com.example.App'),
      });

      expect(await resolver.hasInstalledApp('COM.EXAMPLE.APP'), isTrue);
    });

    test('strips a .helper/.daemon/.agent/.xpc/.service suffix to find the '
        'parent app', () async {
      await makeApp('App.app', bundleId: 'com.example.App');
      final infoPlist = '${applications.path}/App.app/Contents/Info.plist';

      final resolver = resolverWith({
        "mdfind kMDItemCFBundleIdentifier == 'com.example.App.helper'":
            _mdfindMiss(),
        'plutil -extract CFBundleIdentifier raw $infoPlist':
            ProcessResult.success('com.example.App'),
      });

      expect(await resolver.hasInstalledApp('com.example.App.helper'), isTrue);
    });

    test(
      'finds an SMJobBless helper registered under Contents/Library/LaunchServices',
      () async {
        final launchServices =
            '${applications.path}/App.app/Contents/Library/LaunchServices'
            '/com.example.App.helper';
        await File(launchServices).create(recursive: true);
        await File(
          '${applications.path}/App.app/Contents/Info.plist',
        ).create(recursive: true);

        final resolver = resolverWith({
          "mdfind kMDItemCFBundleIdentifier == 'com.example.App.helper'":
              _mdfindMiss(),
          'plutil -extract CFBundleIdentifier raw '
                  '${applications.path}/App.app/Contents/Info.plist':
              ProcessResult.success('com.example.App'),
        });

        expect(
          await resolver.hasInstalledApp('com.example.App.helper'),
          isTrue,
        );
      },
    );

    test('maps Office helpers onto any installed Office app', () async {
      await makeApp('Microsoft Word.app', bundleId: 'com.microsoft.Word');
      final infoPlist =
          '${applications.path}/Microsoft Word.app/Contents/Info.plist';

      final resolver = resolverWith({
        "mdfind kMDItemCFBundleIdentifier == 'com.microsoft.autoupdate.helper'":
            _mdfindMiss(),
        'plutil -extract CFBundleIdentifier raw $infoPlist':
            ProcessResult.success('com.microsoft.Word'),
      });

      expect(
        await resolver.hasInstalledApp('com.microsoft.autoupdate.helper'),
        isTrue,
      );
    });

    test('returns false when no app root has a match', () async {
      await makeApp('Other.app', bundleId: 'com.other.App');
      final infoPlist = '${applications.path}/Other.app/Contents/Info.plist';

      final resolver = resolverWith({
        "mdfind kMDItemCFBundleIdentifier == 'com.example.App'": _mdfindMiss(),
        'plutil -extract CFBundleIdentifier raw $infoPlist':
            ProcessResult.success('com.other.App'),
      });

      expect(await resolver.hasInstalledApp('com.example.App'), isFalse);
    });

    test(
      'an unreadable Info.plist is inconclusive, so it counts as found',
      () async {
        await makeApp('App.app', bundleId: 'com.example.App');
        final infoPlist = '${applications.path}/App.app/Contents/Info.plist';

        final resolver = resolverWith({
          "mdfind kMDItemCFBundleIdentifier == 'com.example.App'":
              _mdfindMiss(),
          'plutil -extract CFBundleIdentifier raw $infoPlist':
              ProcessResult.failure(
                ProcessFailure.nonZeroExit('plutil', 1, 'error'),
              ),
        });

        expect(await resolver.hasInstalledApp('com.example.App'), isTrue);
      },
    );
  });

  test(
    'a failed mdfind probe falls through to the filesystem, not a crash',
    () async {
      await makeApp('App.app', bundleId: 'com.example.App');
      final infoPlist = '${applications.path}/App.app/Contents/Info.plist';

      final resolver = resolverWith({
        "mdfind kMDItemCFBundleIdentifier == 'com.example.App'": _mdfindFail(),
        'plutil -extract CFBundleIdentifier raw $infoPlist':
            ProcessResult.success('com.example.App'),
      });

      expect(await resolver.hasInstalledApp('com.example.App'), isTrue);
    },
  );
}
