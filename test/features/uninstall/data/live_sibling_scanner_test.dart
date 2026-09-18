import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/live_sibling_scanner.dart';
import 'package:hoopix/features/uninstall/data/datasources/pkg_receipt_apps.dart';

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
  '/Volumes',
];

/// Receipts that read completely and name no app, so no test ever walks
/// this machine's real pkgutil database.
PkgReceiptApps _noReceipts() => PkgReceiptApps(
  runner: FakeProcessRunner({'pkgutil --pkgs': ProcessResult.success('')}),
);

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
    PkgReceiptApps? receipts,
  }) => LiveSiblingScanner(
    probe: FakeProcessRunner(responses),
    directory: redirect,
    pkgReceipts: receipts ?? _noReceipts(),
  );

  /// An app under the redirected `/Volumes/<volume>/...`.
  Future<Directory> makeVolumeApp(String relative) async {
    final dir = await Directory(
      '${stubsRoot.path}/Volumes/$relative',
    ).create(recursive: true);
    await File('${dir.path}/Contents/Info.plist').create(recursive: true);
    return dir;
  }

  String plistOf(Directory app) => '${app.path}/Contents/Info.plist';

  Map<String, ProcessResult> ids(Map<Directory, String> apps) => {
    for (final entry in apps.entries)
      'plutil -extract CFBundleIdentifier raw ${plistOf(entry.key)}': _bundleId(
        entry.value,
      ),
  };

  group('mounted volumes', () {
    test("finds a sibling in a volume's Applications folder", () async {
      final removed = await makeApp('MyApp.app');
      final other = await makeVolumeApp('External/Applications/MyApp.app');

      final result =
          await scanner(
            responses: ids({
              removed: 'com.example.MyApp',
              other: 'com.example.MyApp',
            }),
          ).scan(
            home: home.path,
            bundleId: 'com.example.MyApp',
            excludePath: removed.path,
          );

      expect(result, LiveSiblingScanResult.found);
    });

    test('finds a sibling sitting directly on a volume', () async {
      final removed = await makeApp('MyApp.app');
      final other = await makeVolumeApp('External/MyApp.app');

      final result =
          await scanner(
            responses: ids({
              removed: 'com.example.MyApp',
              other: 'com.example.MyApp',
            }),
          ).scan(
            home: home.path,
            bundleId: 'com.example.MyApp',
            excludePath: removed.path,
          );

      expect(result, LiveSiblingScanResult.found);
    });

    test(
      'never follows a volume that is a symlink, like Macintosh HD',
      () async {
        final removed = await makeApp('MyApp.app');
        final elsewhere = await Directory(
          '${stubsRoot.path}/elsewhere/Applications/MyApp.app',
        ).create(recursive: true);
        await File(
          '${elsewhere.path}/Contents/Info.plist',
        ).create(recursive: true);
        await Directory('${stubsRoot.path}/Volumes').create();
        await Link(
          '${stubsRoot.path}/Volumes/Macintosh HD',
        ).create('${stubsRoot.path}/elsewhere');

        final result =
            await scanner(
              responses: ids({
                removed: 'com.example.MyApp',
                elsewhere: 'com.example.MyApp',
              }),
            ).scan(
              home: home.path,
              bundleId: 'com.example.MyApp',
              excludePath: removed.path,
            );

        expect(result, LiveSiblingScanResult.absent);
      },
    );

    test('a volume it cannot read makes absence unprovable', () async {
      final removed = await makeApp('MyApp.app');
      final locked = await Directory(
        '${stubsRoot.path}/Volumes/Locked',
      ).create(recursive: true);
      await Process.run('chmod', ['000', locked.path]);
      addTearDown(() => Process.run('chmod', ['755', locked.path]));

      final result =
          await scanner(responses: ids({removed: 'com.example.MyApp'})).scan(
            home: home.path,
            bundleId: 'com.example.MyApp',
            excludePath: removed.path,
          );

      expect(result, LiveSiblingScanResult.inconclusive);
    });
  });

  group('package receipts', () {
    test(
      'finds a sibling a package installed outside every app root',
      () async {
        final removed = await makeApp('MyApp.app');
        final installed = await Directory(
          '${stubsRoot.path}/opt/vendor/MyApp.app',
        ).create(recursive: true);
        await File(plistOf(installed)).create(recursive: true);

        final result =
            await scanner(
              responses: ids({
                removed: 'com.example.MyApp',
                installed: 'com.example.MyApp',
              }),
              receipts: _FixedReceipts([installed.path]),
            ).scan(
              home: home.path,
              bundleId: 'com.example.MyApp',
              excludePath: removed.path,
            );

        expect(result, LiveSiblingScanResult.found);
      },
    );

    test(
      'a receipt-named app whose bundle id cannot be read is a doubt',
      () async {
        final removed = await makeApp('MyApp.app');

        final result =
            await scanner(
              responses: ids({removed: 'com.example.MyApp'}),
              receipts: _FixedReceipts([
                '${stubsRoot.path}/opt/vendor/Gone.app',
              ]),
            ).scan(
              home: home.path,
              bundleId: 'com.example.MyApp',
              excludePath: removed.path,
            );

        expect(result, LiveSiblingScanResult.inconclusive);
      },
    );

    test(
      'receipts it could not read in full make absence unprovable',
      () async {
        final removed = await makeApp('MyApp.app');

        final result =
            await scanner(
              responses: ids({removed: 'com.example.MyApp'}),
              receipts: _FixedReceipts(const [], complete: false),
            ).scan(
              home: home.path,
              bundleId: 'com.example.MyApp',
              excludePath: removed.path,
            );

        expect(result, LiveSiblingScanResult.inconclusive);
      },
    );
  });

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

class _FixedReceipts extends PkgReceiptApps {
  _FixedReceipts(this.apps, {this.complete = true});

  final List<String> apps;
  final bool complete;

  @override
  Future<PkgReceiptScan> nonstandardAppPaths({
    required DateTime deadline,
  }) async => PkgReceiptScan(appPaths: apps, complete: complete);
}
