import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_services_registration.dart';
import 'package:hoopix/features/uninstall/data/datasources/live_sibling_scanner.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_app_discovery.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/data/repositories/uninstall_inventory_repository_impl.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';

import '../../../support/fake_process_runner.dart';

// Every fixed absolute root LiveSiblingScanner and UninstallAppDiscovery
// walk that does not live under `home` — redirected in tests so a scan
// never touches this machine's real /System/Applications, etc. See
// live_sibling_scanner_test.dart's own copy of this list and rationale.
const _fixedAbsoluteRoots = [
  '/Applications',
  '/System/Applications',
  '/Library/Input Methods',
  '/opt/homebrew/Caskroom',
  '/usr/local/Caskroom',
];

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
      liveSiblingScanner: LiveSiblingScanner(probe: probe, directory: redirect),
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

      final failures = await repository.approve([installedApp]);

      expect(failures, isEmpty);
      expect(trashCalls.single.arguments, {
        'paths': [app.path, leftover.path],
      });
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

      final failures = await repository.approve([installedApp]);

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

      final failures = await repository.approve([installedApp]);

      expect(failures, contains(app.path));
      final entries = readLog();
      expect(entries.single['outcome'], 'refused');
    });

    test('an empty approval is a no-op', () async {
      final repository = repositoryWith(responses: const {});

      final failures = await repository.approve(const []);

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

        final failures = await repository.approve([
          InstalledApp(
            path: app.path,
            bundleId: 'com.example.MyApp',
            displayName: 'MyApp',
          ),
        ]);

        expect(failures, isEmpty);
        expect(events, [
          'launchctl unload $agent',
          'trash ${[app.path, agent]}',
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

          final failures = await repository.approve([
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

          await repository.approve([
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

        final failures = await repository.approve([
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

          final failures = await repository.approve([
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

        await repository.approve(const []);
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
      });
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
  }) : _timeOutExecutables = timeOut ? null : timeOutExecutables,
       _timeOutAll = timeOut;

  final List<String> events;
  final Set<String>? _timeOutExecutables;
  final bool _timeOutAll;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    events.add([executable, ...arguments].join(' '));
    if (_timeOutAll || (_timeOutExecutables?.contains(executable) ?? false)) {
      return ProcessResult.failure(
        ProcessFailure.timedOut(executable, const Duration(seconds: 5)),
      );
    }
    return ProcessResult.success('');
  }
}

const _lsregisterPath =
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/'
    'LaunchServices.framework/Support/lsregister';
