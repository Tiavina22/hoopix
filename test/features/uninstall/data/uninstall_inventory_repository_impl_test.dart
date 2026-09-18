import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/brew_cask.dart';
import 'package:hoopix/features/uninstall/data/datasources/dock_cleanup.dart';
import 'package:hoopix/features/uninstall/data/datasources/finder_trash.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_services_registration.dart';
import 'package:hoopix/features/uninstall/data/datasources/live_sibling_scanner.dart';
import 'package:hoopix/features/uninstall/data/datasources/pkg_receipt_apps.dart';
import 'package:hoopix/features/uninstall/data/datasources/login_item_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/removal_warnings.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_app_discovery.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/data/repositories/uninstall_inventory_repository_impl.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';

import '../../../support/fake_process_runner.dart';

// Every fixed absolute root LiveSiblingScanner and UninstallAppDiscovery
// walk that does not live under `home` — redirected in tests so a scan
// never touches this machine's real /System/Applications, etc. See
// live_sibling_scanner_test.dart's own copy of this list and rationale.
/// [UninstallInventoryRepositoryImpl.approve]'s failures alone, for the
/// many cases that only care what did not go.
Future<Map<String, String>> failuresOf(
  UninstallInventoryRepositoryImpl repository,
  List<InstalledApp> approved,
) async => (await repository.approve(approved)).failures;

/// A [BrewCask] that finds no `brew` binary at all, so no test ever runs
/// this machine's real Homebrew.
BrewCask _noBrew() => BrewCask(typeOf: (_) => FileSystemEntityType.notFound);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  const trashChannel = MethodChannel('fit.hoopix/trash');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(trashChannel, null);
  });

  late Directory home;
  late Directory stubsRoot;
  late Directory applicationsStub;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_uninstall_repo_home_');
    stubsRoot = await Directory.systemTemp.createTemp(
      'hoopix_uninstall_repo_stubs_',
    );
    applicationsStub = Directory('${stubsRoot.path}/Applications')
      ..createSync(recursive: true);
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

  List<Map<String, Object?>> readLog() {
    final file = File('${home.path}/Library/Logs/hoopix/operations.log');
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
    ];
  }

  Future<Directory> makeApp(String name) async {
    final dir = await Directory(
      '${applicationsStub.path}/$name.app',
    ).create(recursive: true);
    await File('${dir.path}/Contents/Info.plist').create(recursive: true);
    return dir;
  }

  UninstallInventoryRepositoryImpl repositoryWith({
    required Map<String, ProcessResult> responses,
    ProcessRunner? launchctl,
    LaunchServicesRegistration? launchServicesRegistration,
    LoginItemTeardown? loginItemTeardown,
    BrewCask? brewCask,
    DockCleanup? dockCleanup,
    RemovalWarnings? removalWarnings,
    FinderTrash? finderTrash,
  }) {
    final probe = FakeProcessRunner(responses);
    return UninstallInventoryRepositoryImpl(
      home: home.path,
      appDiscovery: UninstallAppDiscovery(
        home: home.path,
        probe: probe,
        directory: redirect,
      ),
      leftoverDiscovery: UninstallLeftoverDiscovery(),
      sizeProbe: SizeProbe(probe),
      liveSiblingScanner: LiveSiblingScanner(
        probe: probe,
        directory: redirect,
        pkgReceipts: _noReceipts(),
      ),
      // Never the real launchctl: an unconfigured fake answers "not found",
      // which teardown treats like an ordinary unload failure.
      launchServiceTeardown: LaunchServiceTeardown(
        home: home.path,
        runner: launchctl ?? probe,
      ),
      // Never the real lsregister: a test that does not care about it gets
      // a `typeOf` that finds no binary at all, so unregisterApp/refresh
      // are no-ops rather than real calls into this machine's own
      // LaunchServices database.
      launchServicesRegistration:
          launchServicesRegistration ??
          LaunchServicesRegistration(
            typeOf: (_) => FileSystemEntityType.notFound,
          ),
      // Never the real osascript or launchctl bootout: the fake answers
      // "not found" to both, and no helper folder is ever listed, so a test
      // can never delete one of this machine's own login items.
      loginItemTeardown:
          loginItemTeardown ??
          LoginItemTeardown(
            runner: probe,
            scriptRunner: probe,
            listNames: (_) => const [],
          ),
      brewCask: brewCask ?? _noBrew(),
      // Never this machine's own Dock: no plist is ever found, so no tile is
      // edited and the Dock is never restarted.
      dockCleanup:
          dockCleanup ??
          DockCleanup(
            home: home.path,
            runner: probe,
            typeOf: (_) => FileSystemEntityType.notFound,
          ),
      // Never this machine's own launchd or /Library/SystemExtensions: the
      // fake cannot read a uid and no extension folder is ever listed.
      removalWarnings:
          removalWarnings ??
          RemovalWarnings(runner: probe, listNames: (_) => const []),
      // Never the real Finder: the fake cannot run osascript, and every
      // fixture app lives outside /Applications anyway.
      finderTrash: finderTrash ?? FinderTrash(runner: probe),
    );
  }

  Map<String, ProcessResult> myAppResponses(String appPath) {
    final plist = '$appPath/Contents/Info.plist';
    return {
      'plutil -extract CFBundleIdentifier raw $plist': ProcessResult.success(
        'com.example.MyApp\n',
      ),
      'plutil -extract LSBackgroundOnly raw $plist': ProcessResult.success(
        '0\n',
      ),
      'plutil -extract CFBundleDisplayName raw $plist': ProcessResult.success(
        'MyApp\n',
      ),
      'plutil -extract CFBundleName raw $plist': ProcessResult.success(
        'MyApp\n',
      ),
    };
  }

  Future<String> makeAgent(String name, {String contents = ''}) async {
    final file = await File(
      '${home.path}/Library/LaunchAgents/$name',
    ).create(recursive: true);
    await file.writeAsString(contents);
    return file.path;
  }

  test('lists an app with its leftovers and eventual size', () async {
    final app = await Directory(
      '${applicationsStub.path}/MyApp.app',
    ).create(recursive: true);
    await File('${app.path}/Contents/Info.plist').create(recursive: true);
    await Directory(
      '${home.path}/Library/Application Support/MyApp',
    ).create(recursive: true);

    final plist = '${app.path}/Contents/Info.plist';
    final probe = FakeProcessRunner({
      'plutil -extract CFBundleIdentifier raw $plist': ProcessResult.success(
        'com.example.MyApp\n',
      ),
      'plutil -extract LSBackgroundOnly raw $plist': ProcessResult.success(
        '0\n',
      ),
      'plutil -extract CFBundleDisplayName raw $plist': ProcessResult.success(
        'MyApp\n',
      ),
      'plutil -extract CFBundleName raw $plist': ProcessResult.success(
        'MyApp\n',
      ),
      'du -skPx ${app.path}': ProcessResult.success('4096\t${app.path}'),
    });

    final repository = UninstallInventoryRepositoryImpl(
      home: home.path,
      appDiscovery: UninstallAppDiscovery(
        home: home.path,
        probe: probe,
        directory: redirect,
      ),
      leftoverDiscovery: UninstallLeftoverDiscovery(),
      sizeProbe: SizeProbe(probe),
      brewCask: _noBrew(),
    );

    final snapshots = await repository.watchInventory().toList();

    final first = snapshots.first.single;
    expect(first.path, app.path);
    expect(first.bundleId, 'com.example.MyApp');
    expect(
      first.leftoverPaths,
      contains('${home.path}/Library/Application Support/MyApp'),
    );
    expect(first.sizeBytes, isNull);

    final last = snapshots.last.single;
    expect(last.sizeBytes, 4096 * 1024);
    // Sizing never disturbs what was already found.
    expect(last.leftoverPaths, first.leftoverPaths);
  });

  test('emits an empty list and stops when nothing is installed', () async {
    final repository = UninstallInventoryRepositoryImpl(
      home: home.path,
      appDiscovery: UninstallAppDiscovery(
        home: home.path,
        probe: FakeProcessRunner(const {}),
        directory: redirect,
      ),
      brewCask: _noBrew(),
    );

    final snapshots = await repository.watchInventory().toList();

    expect(snapshots, [isEmpty]);
  });

  group('approve', () {
    test('moves the app bundle and its known leftovers to the Trash when no '
        'sibling shares its bundle id', () async {
      final app = await makeApp('MyApp');
      final leftover = await Directory(
        '${home.path}/Library/Application Support/MyApp',
      ).create(recursive: true);

      final plist = '${app.path}/Contents/Info.plist';
      final repository = repositoryWith(
        responses: {
          'plutil -extract CFBundleIdentifier raw $plist':
              ProcessResult.success('com.example.MyApp\n'),
          'plutil -extract LSBackgroundOnly raw $plist': ProcessResult.success(
            '0\n',
          ),
          'plutil -extract CFBundleDisplayName raw $plist':
              ProcessResult.success('MyApp\n'),
          'plutil -extract CFBundleName raw $plist': ProcessResult.success(
            'MyApp\n',
          ),
        },
      );

      final trashCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        trashCalls.add(call);
        return <Object?, Object?>{};
      });

      final installedApp = InstalledApp(
        path: app.path,
        bundleId: 'com.example.MyApp',
        displayName: 'MyApp',
        sizeBytes: 2048,
      );

      final failures = await failuresOf(repository, [installedApp]);

      expect(failures, isEmpty);
      // The app first, and its leftovers only once it is gone.
      expect(
        [for (final call in trashCalls) call.arguments],
        [
          {
            'paths': [app.path],
          },
          {
            'paths': [leftover.path],
          },
        ],
      );
      final outcomes = {for (final e in readLog()) e['path']: e['outcome']};
      expect(outcomes[app.path], 'trashed');
      expect(outcomes[leftover.path], 'trashed');
    });

    test('narrows to the app bundle alone when a live install shares the '
        'bundle id, leaving its own leftovers untouched', () async {
      final app = await makeApp('MyApp');
      final sibling = await makeApp('MyApp-beta');
      await Directory(
        '${home.path}/Library/Application Support/MyApp',
      ).create(recursive: true);

      final plist = '${app.path}/Contents/Info.plist';
      final siblingPlist = '${sibling.path}/Contents/Info.plist';
      final repository = repositoryWith(
        responses: {
          'plutil -extract CFBundleIdentifier raw $plist':
              ProcessResult.success('com.example.MyApp\n'),
          'plutil -extract LSBackgroundOnly raw $plist': ProcessResult.success(
            '0\n',
          ),
          'plutil -extract CFBundleDisplayName raw $plist':
              ProcessResult.success('MyApp\n'),
          'plutil -extract CFBundleName raw $plist': ProcessResult.success(
            'MyApp\n',
          ),
          'plutil -extract CFBundleIdentifier raw $siblingPlist':
              ProcessResult.success('com.example.MyApp\n'),
          'plutil -extract LSBackgroundOnly raw $siblingPlist':
              ProcessResult.success('0\n'),
          'plutil -extract CFBundleDisplayName raw $siblingPlist':
              ProcessResult.success('MyApp Beta\n'),
          'plutil -extract CFBundleName raw $siblingPlist':
              ProcessResult.success('MyApp Beta\n'),
        },
      );

      final trashCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        trashCalls.add(call);
        return <Object?, Object?>{};
      });

      final installedApp = InstalledApp(
        path: app.path,
        bundleId: 'com.example.MyApp',
        displayName: 'MyApp',
      );

      final failures = await failuresOf(repository, [installedApp]);

      expect(failures, isEmpty);
      expect(trashCalls.single.arguments, {
        'paths': [app.path],
      });
    });

    test('records a refusal the Trash channel reports', () async {
      final app = await makeApp('MyApp');
      final plist = '${app.path}/Contents/Info.plist';
      final repository = repositoryWith(
        responses: {
          'plutil -extract CFBundleIdentifier raw $plist':
              ProcessResult.success('com.example.MyApp\n'),
          'plutil -extract LSBackgroundOnly raw $plist': ProcessResult.success(
            '0\n',
          ),
          'plutil -extract CFBundleDisplayName raw $plist':
              ProcessResult.success('MyApp\n'),
          'plutil -extract CFBundleName raw $plist': ProcessResult.success(
            'MyApp\n',
          ),
        },
      );

      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        final paths = (call.arguments as Map)['paths'] as List;
        return {for (final p in paths) p: 'a Finder window has it open'};
      });

      final installedApp = InstalledApp(
        path: app.path,
        bundleId: 'com.example.MyApp',
        displayName: 'MyApp',
      );

      final failures = await failuresOf(repository, [installedApp]);

      expect(failures, contains(app.path));
      final entries = readLog();
      expect(entries.single['outcome'], 'refused');
    });

    test("a refused app keeps every leftover: nothing of it moves while it "
        "stays installed", () async {
      final app = await makeApp('MyApp');
      final leftover = await Directory(
        '${home.path}/Library/Application Scripts/com.example.MyApp',
      ).create(recursive: true);
      final repository = repositoryWith(responses: myAppResponses(app.path));
      final trashCalls = <List<Object?>>[];
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        final paths = (call.arguments as Map)['paths'] as List;
        trashCalls.add(paths);
        return {
          for (final p in paths)
            if (p == app.path) p: 'you don’t have permission to access it',
        };
      });

      final failures = await failuresOf(repository, [
        InstalledApp(
          path: app.path,
          bundleId: 'com.example.MyApp',
          displayName: 'MyApp',
        ),
      ]);

      expect(trashCalls, [
        [app.path],
      ]);
      expect(failures.keys, [app.path]);
      expect(leftover.existsSync(), isTrue);
      final outcomes = {for (final e in readLog()) e['path']: e['outcome']};
      expect(outcomes[leftover.path], 'skipped');
    });

    test(
      'retries a refused app through Finder, then moves its leftovers',
      () async {
        final app = await makeApp('MyApp');
        final leftover = await Directory(
          '${home.path}/Library/Application Scripts/com.example.MyApp',
        ).create(recursive: true);
        final finder = _RecordingFinder(removes: true);
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          finderTrash: finder,
        );
        final trashCalls = <List<Object?>>[];
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          final paths = (call.arguments as Map)['paths'] as List;
          trashCalls.add(paths);
          return {
            for (final p in paths)
              if (p == app.path) p: 'you don’t have permission to access it',
          };
        });

        final failures = await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);

        expect(failures, isEmpty);
        expect(finder.moved, [app.path]);
        expect(trashCalls, [
          [app.path],
          [leftover.path],
        ]);
        final entries = {for (final e in readLog()) e['path']: e};
        expect(entries[app.path]?['outcome'], 'trashed');
        expect(entries[app.path]?['detail'], contains('through Finder'));
      },
    );

    test('an app Finder could not move keeps its leftovers too', () async {
      final app = await makeApp('MyApp');
      final leftover = await Directory(
        '${home.path}/Library/Application Scripts/com.example.MyApp',
      ).create(recursive: true);
      final finder = _RecordingFinder(removes: false);
      final repository = repositoryWith(
        responses: myAppResponses(app.path),
        finderTrash: finder,
      );
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        final paths = (call.arguments as Map)['paths'] as List;
        return {for (final p in paths) p: 'you don’t have permission'};
      });

      final failures = await failuresOf(repository, [
        InstalledApp(
          path: app.path,
          bundleId: 'com.example.MyApp',
          displayName: 'MyApp',
        ),
      ]);

      expect(finder.moved, [app.path]);
      expect(failures.keys, [app.path]);
      expect(leftover.existsSync(), isTrue);
    });

    test('an empty approval is a no-op', () async {
      final repository = repositoryWith(responses: const {});

      final failures = await failuresOf(repository, const []);

      expect(failures, isEmpty);
    });

    group('launch services', () {
      test('unloads the app agents before anything moves, then trashes their '
          'plists with the app', () async {
        final app = await makeApp('MyApp');
        final agent = await makeAgent('com.example.MyApp.helper.plist');
        final events = <String>[];
        final launchctl = _EventRunner(events);
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          launchctl: launchctl,
        );
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          events.add('trash ${(call.arguments as Map)['paths']}');
          return <Object?, Object?>{};
        });

        final failures = await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);

        expect(failures, isEmpty);
        expect(events, [
          'launchctl unload $agent',
          'trash ${[app.path]}',
          'trash ${[agent]}',
        ]);
      });

      test(
        'refuses the app, and every app after it, when launchctl times out',
        () async {
          final app = await makeApp('MyApp');
          await makeAgent('com.example.MyApp.plist');
          const later = '/Applications/Later.app';
          final events = <String>[];
          final repository = repositoryWith(
            responses: myAppResponses(app.path),
            launchctl: _EventRunner(events, timeOut: true),
          );
          var trashCalled = false;
          messenger.setMockMethodCallHandler(trashChannel, (call) async {
            trashCalled = true;
            return <Object?, Object?>{};
          });

          final failures = await failuresOf(repository, [
            InstalledApp(
              path: app.path,
              bundleId: 'com.example.MyApp',
              displayName: 'MyApp',
            ),
            const InstalledApp(
              path: later,
              bundleId: 'com.example.Later',
              displayName: 'Later',
            ),
          ]);

          expect(trashCalled, isFalse);
          expect(failures.keys, unorderedEquals([app.path, later]));
          expect(Directory(app.path).existsSync(), isTrue);
          final outcomes = {for (final e in readLog()) e['path']: e['outcome']};
          expect(outcomes, {app.path: 'refused', later: 'refused'});
        },
      );

      test(
        "a live sibling keeps its bundle-id agent loaded and on disk, while "
        "an agent pointing at the removed app's own path is unloaded",
        () async {
          final app = await makeApp('MyApp');
          final sibling = await makeApp('MyApp-beta');
          final shared = await makeAgent('com.example.MyApp.plist');
          final ownPath = await makeAgent(
            'net.other.launcher.plist',
            contents: '<string>${app.path}/Contents/MacOS/MyApp</string>',
          );
          final siblingPlist = '${sibling.path}/Contents/Info.plist';
          final events = <String>[];
          final repository = repositoryWith(
            responses: {
              ...myAppResponses(app.path),
              'plutil -extract CFBundleIdentifier raw $siblingPlist':
                  ProcessResult.success('com.example.MyApp\n'),
              'plutil -extract LSBackgroundOnly raw $siblingPlist':
                  ProcessResult.success('0\n'),
              'plutil -extract CFBundleDisplayName raw $siblingPlist':
                  ProcessResult.success('MyApp Beta\n'),
              'plutil -extract CFBundleName raw $siblingPlist':
                  ProcessResult.success('MyApp Beta\n'),
            },
            launchctl: _EventRunner(events),
          );
          final trashed = <Object?>[];
          messenger.setMockMethodCallHandler(trashChannel, (call) async {
            trashed.addAll((call.arguments as Map)['paths'] as List);
            return <Object?, Object?>{};
          });

          await failuresOf(repository, [
            InstalledApp(
              path: app.path,
              bundleId: 'com.example.MyApp',
              displayName: 'MyApp',
            ),
          ]);

          expect(events, ['launchctl unload $ownPath']);
          expect(trashed, [app.path]);
          expect(File(shared).existsSync(), isTrue);
        },
      );
    });

    group('launch services registration', () {
      LaunchServicesRegistration registrationWith(ProcessRunner runner) =>
          LaunchServicesRegistration(
            runner: runner,
            refreshRunner: runner,
            // The stubbed lsregister path always "exists"; every other path
            // (the app bundle itself) is checked against the real
            // filesystem, same as the app's own stub directory tree.
            typeOf: (path) => path == _lsregisterPath
                ? FileSystemEntityType.file
                : FileSystemEntity.typeSync(path, followLinks: false),
          );

      test('unregisters the app before trashing it, then refreshes once the '
          'batch is done', () async {
        final app = await makeApp('MyApp');
        final events = <String>[];
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          launchServicesRegistration: registrationWith(_EventRunner(events)),
        );
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          events.add('trash ${(call.arguments as Map)['paths']}');
          return <Object?, Object?>{};
        });

        final failures = await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);
        // The refresh is fired without being awaited; give it a turn to
        // actually run before asserting on it.
        await Future<void>.delayed(Duration.zero);

        expect(failures, isEmpty);
        expect(events, [
          '$_lsregisterPath -u ${app.path}',
          'trash ${[app.path]}',
          '$_lsregisterPath -r -f -domain local -domain user -domain system',
        ]);
      });

      test(
        'refuses the app, and every app after it, when lsregister times out',
        () async {
          final app = await makeApp('MyApp');
          const later = '/Applications/Later.app';
          var trashCalled = false;
          final repository = repositoryWith(
            responses: myAppResponses(app.path),
            launchServicesRegistration: registrationWith(
              _EventRunner([], timeOutExecutables: {_lsregisterPath}),
            ),
          );
          messenger.setMockMethodCallHandler(trashChannel, (call) async {
            trashCalled = true;
            return <Object?, Object?>{};
          });

          final failures = await failuresOf(repository, [
            InstalledApp(
              path: app.path,
              bundleId: 'com.example.MyApp',
              displayName: 'MyApp',
            ),
            const InstalledApp(
              path: later,
              bundleId: 'com.example.Later',
              displayName: 'Later',
            ),
          ]);

          expect(trashCalled, isFalse);
          expect(failures.keys, unorderedEquals([app.path, later]));
          expect(Directory(app.path).existsSync(), isTrue);
        },
      );

      test('does not refresh when nothing reached the Trash step', () async {
        final events = <String>[];
        final repository = repositoryWith(
          responses: const {},
          launchServicesRegistration: registrationWith(_EventRunner(events)),
        );

        await failuresOf(repository, const []);
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
      });
    });

    group('login items', () {
      Future<String> makeHelper(Directory app) async {
        final info = await File(
          '${app.path}/Contents/Library/LoginItems/Helper.app/Contents/Info.plist',
        ).create(recursive: true);
        return info.path;
      }

      LoginItemTeardown loginWith(
        List<String> events, {
        Map<String, ProcessResult> responses = const {},
        Set<String> timeOutExecutables = const {},
      }) {
        final runner = _EventRunner(
          events,
          responses: {'id -u': ProcessResult.success('501\n'), ...responses},
          timeOutExecutables: timeOutExecutables,
        );
        return LoginItemTeardown(runner: runner, scriptRunner: runner);
      }

      test('removes the login item before anything moves, and boots its helper '
          'out only once the app is gone', () async {
        final app = await makeApp('MyApp');
        final helperInfo = await makeHelper(app);
        final events = <String>[];
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          loginItemTeardown: loginWith(
            events,
            responses: {
              'plutil -extract CFBundleIdentifier raw $helperInfo':
                  ProcessResult.success('com.example.MyApp.Helper\n'),
            },
          ),
        );
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          events.add('trash');
          return <Object?, Object?>{};
        });

        final failures = await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);

        expect(failures, isEmpty);
        final osascript = events.indexWhere((e) => e.startsWith('osascript'));
        final trash = events.indexOf('trash');
        final bootout = events.indexOf(
          'launchctl bootout gui/501/com.example.MyApp.Helper',
        );
        expect(events[osascript], endsWith(' MyApp'));
        expect(osascript, lessThan(trash));
        expect(trash, lessThan(bootout));
      });

      test(
        'a live sibling keeps its login item and running helper untouched',
        () async {
          final app = await makeApp('MyApp');
          await makeHelper(app);
          final sibling = await makeApp('MyApp-beta');
          final siblingPlist = '${sibling.path}/Contents/Info.plist';
          final events = <String>[];
          final repository = repositoryWith(
            responses: {
              ...myAppResponses(app.path),
              'plutil -extract CFBundleIdentifier raw $siblingPlist':
                  ProcessResult.success('com.example.MyApp\n'),
              'plutil -extract LSBackgroundOnly raw $siblingPlist':
                  ProcessResult.success('0\n'),
              'plutil -extract CFBundleDisplayName raw $siblingPlist':
                  ProcessResult.success('MyApp\n'),
              'plutil -extract CFBundleName raw $siblingPlist':
                  ProcessResult.success('MyApp\n'),
            },
            loginItemTeardown: loginWith(events),
          );
          messenger.setMockMethodCallHandler(
            trashChannel,
            (call) async => <Object?, Object?>{},
          );

          await failuresOf(repository, [
            InstalledApp(
              path: app.path,
              bundleId: 'com.example.MyApp',
              displayName: 'MyApp',
            ),
          ]);

          expect(events, isEmpty);
        },
      );

      test('a refused move leaves the helper running', () async {
        final app = await makeApp('MyApp');
        final helperInfo = await makeHelper(app);
        final events = <String>[];
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          loginItemTeardown: loginWith(
            events,
            responses: {
              'plutil -extract CFBundleIdentifier raw $helperInfo':
                  ProcessResult.success('com.example.MyApp.Helper\n'),
            },
          ),
        );
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          final paths = (call.arguments as Map)['paths'] as List;
          return {for (final p in paths) p: 'in use'};
        });

        final failures = await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);

        expect(failures, contains(app.path));
        expect(events.where((e) => e.startsWith('launchctl')), isEmpty);
      });

      test(
        'a System Events timeout leaves the login item but still removes the '
        'app, and says so in the log',
        () async {
          final app = await makeApp('MyApp');
          final events = <String>[];
          final repository = repositoryWith(
            responses: myAppResponses(app.path),
            loginItemTeardown: loginWith(
              events,
              timeOutExecutables: {'osascript'},
            ),
          );
          final trashed = <Object?>[];
          messenger.setMockMethodCallHandler(trashChannel, (call) async {
            trashed.addAll((call.arguments as Map)['paths'] as List);
            return <Object?, Object?>{};
          });

          final failures = await failuresOf(repository, [
            InstalledApp(
              path: app.path,
              bundleId: 'com.example.MyApp',
              displayName: 'MyApp',
            ),
          ]);

          expect(failures, isEmpty);
          expect(trashed, [app.path]);
          final outcomes = [
            for (final e in readLog())
              if (e['path'] == app.path) e['outcome'],
          ];
          expect(outcomes, ['skipped', 'trashed']);
        },
      );
    });

    group('homebrew', () {
      /// A BrewCask over [fake]: brew "exists", every other path is checked
      /// on the real (temp) filesystem, and the real Caskrooms are never
      /// listed, so detection only ever sees what [fake] answers.
      BrewCask brewWith(_RepoBrew fake) => BrewCask(
        probe: fake,
        uninstallRunner: (_) => fake,
        typeOf: (path) => path == '/opt/homebrew/bin/brew'
            ? FileSystemEntityType.file
            : FileSystemEntity.typeSync(path, followLinks: false),
        resolvePath: (path) => path,
        readLink: (_) => null,
        listNames: (_) => const [],
      );

      Future<({Directory app, String kept, String zapped})> brewedApp() async {
        final app = await makeApp('MyApp');
        final kept = await Directory(
          '${home.path}/Library/Application Support/MyApp',
        ).create(recursive: true);
        final zapped = await Directory(
          '${home.path}/Library/Caches/MyApp',
        ).create(recursive: true);
        return (app: app, kept: kept.path, zapped: zapped.path);
      }

      InstalledApp installed(Directory app) => InstalledApp(
        path: app.path,
        bundleId: 'com.example.MyApp',
        displayName: 'MyApp',
      );

      test('the inventory tags a Homebrew-managed app for review', () async {
        final fixture = await brewedApp();
        final fake = _RepoBrew(appPath: fixture.app.path);
        final repository = repositoryWith(
          responses: myAppResponses(fixture.app.path),
          brewCask: brewWith(fake),
        );

        final snapshots = await repository.watchInventory().toList();

        expect(snapshots.first.single.caskName, isNull);
        expect(snapshots.last.single.caskName, 'myapp');
        // Review only: the preview never runs a single uninstall.
        expect(fake.calls.where((c) => c.startsWith('uninstall')), isEmpty);
      });

      test('uninstalls a cask through Homebrew with --zap, then moves only the '
          'leftovers the zap did not already remove', () async {
        final fixture = await brewedApp();
        final fake = _RepoBrew(
          appPath: fixture.app.path,
          zapRemoves: [fixture.zapped],
        );
        final repository = repositoryWith(
          responses: myAppResponses(fixture.app.path),
          brewCask: brewWith(fake),
        );
        final trashed = <Object?>[];
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          trashed.addAll((call.arguments as Map)['paths'] as List);
          return <Object?, Object?>{};
        });

        final failures = await failuresOf(repository, [installed(fixture.app)]);

        expect(failures, isEmpty);
        expect(fake.calls, contains('uninstall --cask --zap myapp'));
        expect(trashed, [fixture.kept]);
        expect(fixture.app.existsSync(), isFalse);
        final outcomes = {for (final e in readLog()) e['path']: e};
        expect(outcomes[fixture.app.path]?['outcome'], 'cleared');
        expect(
          outcomes[fixture.app.path]?['detail'],
          'brew uninstall --cask --zap myapp',
        );
      });

      test('a live sibling gets a plain uninstall, never --zap', () async {
        final fixture = await brewedApp();
        final sibling = await makeApp('MyApp-beta');
        final siblingPlist = '${sibling.path}/Contents/Info.plist';
        final fake = _RepoBrew(appPath: fixture.app.path);
        final repository = repositoryWith(
          responses: {
            ...myAppResponses(fixture.app.path),
            'plutil -extract CFBundleIdentifier raw $siblingPlist':
                ProcessResult.success('com.example.MyApp\n'),
            'plutil -extract LSBackgroundOnly raw $siblingPlist':
                ProcessResult.success('0\n'),
            'plutil -extract CFBundleDisplayName raw $siblingPlist':
                ProcessResult.success('MyApp Beta\n'),
            'plutil -extract CFBundleName raw $siblingPlist':
                ProcessResult.success('MyApp Beta\n'),
          },
          brewCask: brewWith(fake),
        );
        final trashed = <Object?>[];
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          trashed.addAll((call.arguments as Map)['paths'] as List);
          return <Object?, Object?>{};
        });

        await failuresOf(repository, [installed(fixture.app)]);

        expect(fake.calls, contains('uninstall --cask myapp'));
        expect(fake.calls, isNot(contains('uninstall --cask --zap myapp')));
        // Narrowed to the bundle alone: no leftover belongs to this app.
        expect(trashed, isEmpty);
      });

      test(
        'refuses, and moves nothing, while Homebrew still lists the cask',
        () async {
          final fixture = await brewedApp();
          final fake = _RepoBrew(appPath: fixture.app.path, fails: true);
          final repository = repositoryWith(
            responses: myAppResponses(fixture.app.path),
            brewCask: brewWith(fake),
          );
          var trashCalled = false;
          messenger.setMockMethodCallHandler(trashChannel, (call) async {
            trashCalled = true;
            return <Object?, Object?>{};
          });

          final failures = await failuresOf(repository, [
            installed(fixture.app),
          ]);

          expect(trashCalled, isFalse);
          expect(fixture.app.existsSync(), isTrue);
          expect(
            failures[fixture.app.path],
            contains('brew uninstall --cask --zap myapp'),
          );
        },
      );

      test(
        'falls back to the Trash once Homebrew no longer tracks the cask',
        () async {
          final fixture = await brewedApp();
          final fake = _RepoBrew(
            appPath: fixture.app.path,
            fails: true,
            forgetsCaskOnFailure: true,
          );
          final repository = repositoryWith(
            responses: myAppResponses(fixture.app.path),
            brewCask: brewWith(fake),
          );
          final trashed = <Object?>[];
          messenger.setMockMethodCallHandler(trashChannel, (call) async {
            trashed.addAll((call.arguments as Map)['paths'] as List);
            return <Object?, Object?>{};
          });

          final failures = await failuresOf(repository, [
            installed(fixture.app),
          ]);

          expect(failures, isEmpty);
          expect(trashed.first, fixture.app.path);
          expect(trashed, containsAll([fixture.kept, fixture.zapped]));
        },
      );

      test('refuses an app whose Homebrew state cannot be read, before any '
          'teardown', () async {
        final fixture = await brewedApp();
        final fake = _RepoBrew(appPath: fixture.app.path, listFails: true);
        final events = <String>[];
        final repository = repositoryWith(
          responses: myAppResponses(fixture.app.path),
          brewCask: brewWith(fake),
          loginItemTeardown: LoginItemTeardown(
            runner: _EventRunner(events),
            scriptRunner: _EventRunner(events),
          ),
        );
        var trashCalled = false;
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          trashCalled = true;
          return <Object?, Object?>{};
        });

        final failures = await failuresOf(repository, [installed(fixture.app)]);

        expect(trashCalled, isFalse);
        expect(events, isEmpty);
        expect(failures, contains(fixture.app.path));
        expect(fake.calls.where((c) => c.startsWith('uninstall')), isEmpty);
      });

      test(
        'a brew uninstall that times out refuses it and every app after it',
        () async {
          final fixture = await brewedApp();
          const later = '/Applications/Later.app';
          final fake = _RepoBrew(appPath: fixture.app.path, timesOut: true);
          final repository = repositoryWith(
            responses: myAppResponses(fixture.app.path),
            brewCask: brewWith(fake),
          );
          var trashCalled = false;
          messenger.setMockMethodCallHandler(trashChannel, (call) async {
            trashCalled = true;
            return <Object?, Object?>{};
          });

          final failures = await failuresOf(repository, [
            installed(fixture.app),
            const InstalledApp(
              path: later,
              bundleId: 'com.example.Later',
              displayName: 'Later',
            ),
          ]);

          expect(trashCalled, isFalse);
          expect(failures.keys, unorderedEquals([fixture.app.path, later]));
        },
      );
    });

    group('dock', () {
      test('hands a removed app to the Dock cleanup with its bundle id, before '
          'the LaunchServices rebuild', () async {
        final app = await makeApp('MyApp');
        final events = <String>[];
        final dock = _RecordingDock(events);
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          dockCleanup: dock,
          launchServicesRegistration: LaunchServicesRegistration(
            refreshRunner: _EventRunner(events),
            typeOf: (path) => path == _lsregisterPath
                ? FileSystemEntityType.file
                : FileSystemEntityType.notFound,
          ),
        );
        messenger.setMockMethodCallHandler(
          trashChannel,
          (call) async => <Object?, Object?>{},
        );

        await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);
        await pumpEventQueue();

        expect(dock.targets.single.appPath, app.path);
        expect(dock.targets.single.bundleId, 'com.example.MyApp');
        expect(events.first, 'dock');
        expect(events.last, startsWith('$_lsregisterPath -r'));
      });

      test('a live sibling keeps its tile: only the path can match', () async {
        final app = await makeApp('MyApp');
        final sibling = await makeApp('MyApp-beta');
        final siblingPlist = '${sibling.path}/Contents/Info.plist';
        final dock = _RecordingDock([]);
        final repository = repositoryWith(
          responses: {
            ...myAppResponses(app.path),
            'plutil -extract CFBundleIdentifier raw $siblingPlist':
                ProcessResult.success('com.example.MyApp\n'),
            'plutil -extract LSBackgroundOnly raw $siblingPlist':
                ProcessResult.success('0\n'),
            'plutil -extract CFBundleDisplayName raw $siblingPlist':
                ProcessResult.success('MyApp Beta\n'),
            'plutil -extract CFBundleName raw $siblingPlist':
                ProcessResult.success('MyApp Beta\n'),
          },
          dockCleanup: dock,
        );
        messenger.setMockMethodCallHandler(
          trashChannel,
          (call) async => <Object?, Object?>{},
        );

        await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);
        await pumpEventQueue();

        expect(dock.targets.single.bundleId, 'unknown');
      });

      test('an app the Trash refused keeps its tile', () async {
        final app = await makeApp('MyApp');
        final dock = _RecordingDock([]);
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          dockCleanup: dock,
        );
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          final paths = (call.arguments as Map)['paths'] as List;
          return {for (final p in paths) p: 'in use'};
        });

        await failuresOf(repository, [
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);
        await pumpEventQueue();

        expect(dock.calls, 0);
      });
    });

    group('left-behind warnings', () {
      RemovalWarnings warningsWith({
        Set<String> loaded = const {},
        Map<String, List<String>> extensions = const {},
      }) => RemovalWarnings(
        runner: _EventRunner(
          [],
          responses: {
            'id -u': ProcessResult.success('501\n'),
            for (final label in loaded)
              'launchctl print gui/501/$label': ProcessResult.success(''),
          },
          // Anything not listed as loaded answers like launchd's 113.
          failUnlisted: true,
        ),
        listNames: (dir) => extensions[dir] ?? const [],
      );

      test('names a removed app whose background job is still loaded, or that '
          'still has a system extension', () async {
        final app = await makeApp('MyApp');
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          removalWarnings: warningsWith(
            loaded: {'com.example.MyApp'},
            extensions: {
              '/Library/SystemExtensions': ['UUID'],
              '/Library/SystemExtensions/UUID': [
                'com.example.MyApp.network-extension.systemextension',
              ],
            },
          ),
        );
        messenger.setMockMethodCallHandler(
          trashChannel,
          (call) async => <Object?, Object?>{},
        );

        final result = await repository.approve([
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);

        expect(result.failures, isEmpty);
        expect(result.backgroundItemApps, ['MyApp']);
        expect(result.systemExtensionApps, ['MyApp']);
      });

      test('an app the Trash refused is never warned about', () async {
        final app = await makeApp('MyApp');
        final repository = repositoryWith(
          responses: myAppResponses(app.path),
          removalWarnings: warningsWith(loaded: {'com.example.MyApp'}),
        );
        messenger.setMockMethodCallHandler(trashChannel, (call) async {
          final paths = (call.arguments as Map)['paths'] as List;
          return {for (final p in paths) p: 'in use'};
        });

        final result = await repository.approve([
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);

        expect(result.hasWarnings, isFalse);
      });

      test(
        "a live sibling's own job is never blamed on the removed app",
        () async {
          final app = await makeApp('MyApp');
          final sibling = await makeApp('MyApp-beta');
          final siblingPlist = '${sibling.path}/Contents/Info.plist';
          final repository = repositoryWith(
            responses: {
              ...myAppResponses(app.path),
              'plutil -extract CFBundleIdentifier raw $siblingPlist':
                  ProcessResult.success('com.example.MyApp\n'),
              'plutil -extract LSBackgroundOnly raw $siblingPlist':
                  ProcessResult.success('0\n'),
              'plutil -extract CFBundleDisplayName raw $siblingPlist':
                  ProcessResult.success('MyApp Beta\n'),
              'plutil -extract CFBundleName raw $siblingPlist':
                  ProcessResult.success('MyApp Beta\n'),
            },
            removalWarnings: warningsWith(
              loaded: {'com.example.MyApp'},
              extensions: {
                '/Library/SystemExtensions': [
                  'com.example.MyApp.extension.systemextension',
                ],
              },
            ),
          );
          messenger.setMockMethodCallHandler(
            trashChannel,
            (call) async => <Object?, Object?>{},
          );

          final result = await repository.approve([
            InstalledApp(
              path: app.path,
              bundleId: 'com.example.MyApp',
              displayName: 'MyApp',
            ),
          ]);

          expect(result.failures, isEmpty);
          expect(result.hasWarnings, isFalse);
        },
      );
    });
  });
}

/// Records every call as `executable args...` into a list shared with the
/// Trash handler, so a test can assert unload-before-trash ordering.
/// [timeOutExecutables] lets a test make only one of launchctl/lsregister
/// hang, so the two timeout paths can be told apart.
class _EventRunner extends ProcessRunner {
  _EventRunner(
    this.events, {
    bool timeOut = false,
    Set<String> timeOutExecutables = const {},
    this.responses = const {},
    this.failUnlisted = false,
  }) : _timeOutExecutables = timeOutExecutables,
       _timeOutAll = timeOut;

  /// When set, a command missing from [responses] exits non-zero instead of
  /// succeeding.
  final bool failUnlisted;

  final List<String> events;
  final Set<String> _timeOutExecutables;
  final bool _timeOutAll;

  /// Canned answers keyed by `executable arg1 ...`; anything unlisted
  /// succeeds with empty output.
  final Map<String, ProcessResult> responses;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final key = [executable, ...arguments].join(' ');
    events.add(key);
    if (_timeOutAll || _timeOutExecutables.contains(executable)) {
      return ProcessResult.failure(
        ProcessFailure.timedOut(executable, const Duration(seconds: 5)),
      );
    }
    return responses[key] ??
        (failUnlisted
            ? ProcessResult.failure(
                ProcessFailure.nonZeroExit(executable, 113, 'not found'),
              )
            : ProcessResult.success(''));
  }
}

const _lsregisterPath =
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/'
    'LaunchServices.framework/Support/lsregister';

/// A stateful stand-in for Homebrew managing one app as the cask `myapp`:
/// `brew info` owns [appPath], and a successful uninstall really deletes the
/// app bundle (plus whatever [zapRemoves] names, as a zap would) and drops
/// the cask from `brew list`.
class _RepoBrew extends ProcessRunner {
  _RepoBrew({
    required this.appPath,
    this.zapRemoves = const [],
    this.fails = false,
    this.forgetsCaskOnFailure = false,
    this.listFails = false,
    this.timesOut = false,
  });

  final String appPath;
  final List<String> zapRemoves;
  final bool fails;
  final bool forgetsCaskOnFailure;
  final bool listFails;
  final bool timesOut;
  final calls = <String>[];
  var _listed = true;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final brewAt = arguments.indexOf('/opt/homebrew/bin/brew');
    final key = arguments.sublist(brewAt + 1).join(' ');
    calls.add(key);
    if (key == 'list --cask') {
      if (listFails) {
        return ProcessResult.failure(
          ProcessFailure.nonZeroExit(executable, 1, 'Error'),
        );
      }
      return ProcessResult.success(_listed ? 'myapp\n' : '');
    }
    if (key == 'info --cask myapp') {
      return ProcessResult.success('==> Artifacts\n$appPath (App)\n');
    }
    if (key.startsWith('uninstall --cask')) {
      if (timesOut) {
        return ProcessResult.failure(
          ProcessFailure.timedOut(executable, const Duration(minutes: 5)),
        );
      }
      if (fails) {
        if (forgetsCaskOnFailure) _listed = false;
        return ProcessResult.failure(
          ProcessFailure.nonZeroExit(
            executable,
            1,
            'sudo: a terminal is required',
          ),
        );
      }
      for (final path in [appPath, if (key.contains('--zap')) ...zapRemoves]) {
        // Test fixtures only: every path here lives under a temp directory.
        final dir = Directory(path);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
      _listed = false;
      return ProcessResult.success('');
    }
    return ProcessResult.failure(
      ProcessFailure.nonZeroExit(executable, 1, 'Unknown command: $key'),
    );
  }
}

/// Records what the repository hands the Dock cleanup instead of touching
/// any Dock.
class _RecordingDock extends DockCleanup {
  _RecordingDock(this.events) : super(home: '/nonexistent');

  final List<String> events;
  final targets = <DockTarget>[];
  var calls = 0;

  @override
  Future<bool> remove(List<DockTarget> targets) async {
    calls++;
    events.add('dock');
    this.targets.addAll(targets);
    return false;
  }
}

/// Stands in for Finder's elevated Trash move: records the attempt and,
/// when [removes], reports the bundle gone as a password-authorized Finder
/// move would. Never touches the real Finder.
class _RecordingFinder extends FinderTrash {
  _RecordingFinder({required this.removes});

  final bool removes;
  final moved = <String>[];

  @override
  Future<bool> moveApplication(String appPath) async {
    moved.add(appPath);
    return removes;
  }
}
