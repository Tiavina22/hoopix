import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/live_sibling_scanner.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _bundleId(String id) => ProcessResult.success('$id\n');
ProcessResult _unreadable() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('plutil', 1, ''));

// Every fixed absolute root LiveSiblingScanner walks that does not live
// under `home` — these must all be redirected in tests, or the scan hits
// this machine's real /System/Applications, /Library/Input Methods, etc.
// and either times out on real apps or reports a false inconclusive.
const _fixedAbsoluteRoots = [
  '/Applications',
  '/System/Applications',
  '/Library/Input Methods',
  '/opt/homebrew/Caskroom',
  '/usr/local/Caskroom',
];

void main() {
  late Directory home;
  late Directory stubsRoot;
  late Directory applicationsStub;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_live_sibling_home_');
    stubsRoot = await Directory.systemTemp.createTemp(
      'hoopix_live_sibling_stubs_',
    );
    applicationsStub = Directory('${stubsRoot.path}/Applications')
      ..createSync(recursive: true);
    // The other fixed roots stay unmapped on disk (never created) so a
    // listSync() on them throws notFound, which the scanner treats as an
    // ordinary "not installed here" rather than inconclusive.
  });

  tearDown(() async {
    for (final dir in [home, stubsRoot]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  Directory redirect(String path) {
    for (final root in _fixedAbsoluteRoots) {
      if (path == root || path.startsWith('$root/')) {
        return Directory(path.replaceFirst(root, '${stubsRoot.path}$root'));
      }
    }
    return Directory(path);
  }

  Future<Directory> makeApp(String relative) async {
    final dir = await Directory(
      '${applicationsStub.path}/$relative',
    ).create(recursive: true);
    await File('${dir.path}/Contents/Info.plist').create(recursive: true);
    return dir;
  }

  LiveSiblingScanner scanner({
    Map<String, ProcessResult> responses = const {},
  }) => LiveSiblingScanner(
    probe: FakeProcessRunner(responses),
    directory: redirect,
  );

  test('absent for a malformed bundle id', () async {
    final result = await scanner().scan(
      home: home.path,
      bundleId: 'unknown',
      excludePath: '/Applications/Removed.app',
    );

    expect(result, LiveSiblingScanResult.absent);
  });

  test('absent when no other app shares the bundle id', () async {
    final other = await makeApp('Other.app');

    final result =
        await scanner(
          responses: {
            _infoPlistProbeKey(other): _bundleId('com.example.Other'),
          },
        ).scan(
          home: home.path,
          bundleId: 'com.example.Removed',
          excludePath: '/Applications/Removed.app',
        );

    expect(result, LiveSiblingScanResult.absent);
  });

  test('found when another app shares the exact bundle id', () async {
    final other = await makeApp('Sibling.app');

    final result =
        await scanner(
          responses: {
            _infoPlistProbeKey(other): _bundleId('com.example.Shared'),
          },
        ).scan(
          home: home.path,
          bundleId: 'com.example.Shared',
          excludePath: '${applicationsStub.path}/Removed.app',
        );

    expect(result, LiveSiblingScanResult.found);
  });

  test('matches case-insensitively', () async {
    final other = await makeApp('Sibling.app');

    final result =
        await scanner(
          responses: {
            _infoPlistProbeKey(other): _bundleId('COM.EXAMPLE.SHARED'),
          },
        ).scan(
          home: home.path,
          bundleId: 'com.example.shared',
          excludePath: '${applicationsStub.path}/Removed.app',
        );

    expect(result, LiveSiblingScanResult.found);
  });

  test('never counts the excluded path itself as a sibling', () async {
    final selfApp = await makeApp('Removed.app');

    final result =
        await scanner(
          responses: {
            _infoPlistProbeKey(selfApp): _bundleId('com.example.Shared'),
          },
        ).scan(
          home: home.path,
          bundleId: 'com.example.Shared',
          excludePath: selfApp.path,
        );

    expect(result, LiveSiblingScanResult.absent);
  });

  test('inconclusive when a candidate bundle id cannot be read', () async {
    final other = await makeApp('Broken.app');

    final result =
        await scanner(
          responses: {_infoPlistProbeKey(other): _unreadable()},
        ).scan(
          home: home.path,
          bundleId: 'com.example.Shared',
          excludePath: '${applicationsStub.path}/Removed.app',
        );

    expect(result, LiveSiblingScanResult.inconclusive);
  });

  test('never descends into a helper nested inside another .app', () async {
    final outer = await Directory(
      '${applicationsStub.path}/Outer.app',
    ).create(recursive: true);
    await File('${outer.path}/Contents/Info.plist').create(recursive: true);
    final nested = await Directory(
      '${outer.path}/Contents/Helpers/Inner.app',
    ).create(recursive: true);
    await File('${nested.path}/Contents/Info.plist').create(recursive: true);

    final result =
        await scanner(
          responses: {
            _infoPlistProbeKey(outer): _bundleId('com.example.Outer'),
            _infoPlistProbeKey(nested): _bundleId('com.example.Shared'),
          },
        ).scan(
          home: home.path,
          bundleId: 'com.example.Shared',
          excludePath: '${applicationsStub.path}/Removed.app',
        );

    // The nested app is never even reached, so its (would-be) matching
    // bundle id never surfaces — proving the walk actually prunes there
    // rather than merely not finding a fake response.
    expect(result, LiveSiblingScanResult.absent);
  });

  test('resolves an iOS/iPadOS app whose plist lives under Wrapper/', () async {
    final app = await Directory(
      '${applicationsStub.path}/IOSApp.app',
    ).create(recursive: true);
    final wrapped = await Directory(
      '${app.path}/Wrapper/IOSApp.app',
    ).create(recursive: true);
    await File('${wrapped.path}/Info.plist').create(recursive: true);

    final result =
        await scanner(
          responses: {
            'plutil -extract CFBundleIdentifier raw ${wrapped.path}/Info.plist':
                _bundleId('com.example.Shared'),
          },
        ).scan(
          home: home.path,
          bundleId: 'com.example.Shared',
          excludePath: '${applicationsStub.path}/Removed.app',
        );

    expect(result, LiveSiblingScanResult.found);
  });
}

String _infoPlistProbeKey(Directory app) =>
    'plutil -extract CFBundleIdentifier raw ${app.path}/Contents/Info.plist';
