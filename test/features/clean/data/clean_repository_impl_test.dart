import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/browser_profile_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/cloud_storage_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/final_cut_pro_generated_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/jianying_pro_generated_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/macos_installer_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/macos_installer_probe.dart';
import 'package:hoopix/features/clean/data/datasources/orphaned_system_services_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/pnpm_store_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/tart_cache_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/utm_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/xcode_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/repositories/clean_repository_impl.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trashChannel = MethodChannel('fit.hoopix/trash');
  const privilegedDeleteChannel = MethodChannel('fit.hoopix/privileged_delete');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(trashChannel, null);
    messenger.setMockMethodCallHandler(privilegedDeleteChannel, null);
  });

  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_clean_repo_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  List<Map<String, Object?>> readLog() {
    final file = File('${home.path}/Library/Logs/hoopix/operations.log');
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
    ];
  }

  test('runs the owner command instead of moving its path to Trash', () async {
    messenger.setMockMethodCallHandler(trashChannel, (call) async {
      fail('Trash must not be called for an owner-command candidate');
    });

    final repository = CleanRepositoryImpl(home: home.path);
    final candidate = CleanCandidate(
      path: '${home.path}/.npm',
      section: 'Developer tools',
      sizeBytes: 10,
      ownerCommand: const ['echo', 'cleaned'],
    );

    final failures = await repository.approve([candidate]);

    expect(failures, isEmpty);
    final entries = readLog();
    expect(entries.single['outcome'], 'cleared');
    expect(entries.single['path'], candidate.path);
  });

  test('records a refusal when the owner command exits non-zero', () async {
    final repository = CleanRepositoryImpl(home: home.path);
    final candidate = CleanCandidate(
      path: '${home.path}/.cache/tool',
      section: 'Developer tools',
      ownerCommand: const ['false'],
    );

    final failures = await repository.approve([candidate]);

    expect(failures, contains(candidate.path));
    final entries = readLog();
    expect(entries.single['outcome'], 'refused');
  });

  test(
    'a batch mixing Trash and owner-command candidates runs both mechanisms',
    () async {
      final trashCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        trashCalls.add(call);
        return <Object?, Object?>{};
      });

      final repository = CleanRepositoryImpl(home: home.path);
      final trashCandidate = CleanCandidate(
        path: '${home.path}/Library/Caches/plain',
        section: 'User essentials',
        sizeBytes: 5,
      );
      final commandCandidate = CleanCandidate(
        path: '${home.path}/.npm',
        section: 'Developer tools',
        sizeBytes: 10,
        ownerCommand: const ['echo', 'cleaned'],
      );

      final failures = await repository.approve([
        trashCandidate,
        commandCandidate,
      ]);

      expect(failures, isEmpty);
      expect(trashCalls.single.arguments, {
        'paths': [trashCandidate.path],
      });
      final outcomes = {for (final e in readLog()) e['path']: e['outcome']};
      expect(outcomes[trashCandidate.path], 'trashed');
      expect(outcomes[commandCandidate.path], 'cleared');
    },
  );

  test('refuses a Trash candidate whose recheck guard finds the process now '
      'running, without moving it to Trash', () async {
    messenger.setMockMethodCallHandler(trashChannel, (call) async {
      fail('Trash must not be called once the recheck finds it running');
    });

    final repository = CleanRepositoryImpl(
      home: home.path,
      recheckGuard: ProcessGuard(
        FakeProcessRunner({
          'pgrep -x Google Chrome': ProcessResult.success('123'),
        }),
      ),
    );
    final candidate = CleanCandidate(
      path: '${home.path}/Library/Application Support/Google/Chrome/blob',
      section: 'Browsers',
      sizeBytes: 5,
      recheckProcessGuard: const ProcessRecheck(exactNames: ['Google Chrome']),
    );

    final failures = await repository.approve([candidate]);

    expect(failures, contains(candidate.path));
    final entries = readLog();
    expect(entries.single['outcome'], 'refused');
  });

  test('refuses a Trash candidate whose recheck guard cannot confirm the '
      'process state', () async {
    final repository = CleanRepositoryImpl(
      home: home.path,
      recheckGuard: ProcessGuard(
        FakeProcessRunner({
          'pgrep -x Google Chrome': ProcessResult.failure(
            ProcessFailure.nonZeroExit('pgrep', 2, 'usage'),
          ),
        }),
      ),
    );
    final candidate = CleanCandidate(
      path: '${home.path}/Library/Application Support/Google/Chrome/blob',
      section: 'Browsers',
      recheckProcessGuard: const ProcessRecheck(exactNames: ['Google Chrome']),
    );

    final failures = await repository.approve([candidate]);

    expect(failures, contains(candidate.path));
  });

  test(
    'moves a Trash candidate once its recheck guard reconfirms the process '
    'is not running, leaving an unguarded sibling untouched by the check',
    () async {
      final trashCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        trashCalls.add(call);
        return <Object?, Object?>{};
      });

      final repository = CleanRepositoryImpl(
        home: home.path,
        recheckGuard: ProcessGuard(
          FakeProcessRunner({
            'pgrep -x Google Chrome': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
          }),
        ),
      );
      final guardedCandidate = CleanCandidate(
        path: '${home.path}/Library/Application Support/Google/Chrome/blob',
        section: 'Browsers',
        sizeBytes: 5,
        recheckProcessGuard: const ProcessRecheck(
          exactNames: ['Google Chrome'],
        ),
      );
      final plainCandidate = CleanCandidate(
        path: '${home.path}/Library/Caches/plain',
        section: 'User essentials',
        sizeBytes: 5,
      );

      final failures = await repository.approve([
        guardedCandidate,
        plainCandidate,
      ]);

      expect(failures, isEmpty);
      expect(trashCalls.single.arguments, {
        'paths': [guardedCandidate.path, plainCandidate.path],
      });
      final outcomes = {for (final e in readLog()) e['path']: e['outcome']};
      expect(outcomes[guardedCandidate.path], 'trashed');
      expect(outcomes[plainCandidate.path], 'trashed');
    },
  );

  test('the User essentials section is merged with a .DS_Store from '
      'FinderMetadataLocalDataSource', () async {
    await File('${home.path}/Documents/.DS_Store').create(recursive: true);

    final repository = CleanRepositoryImpl(home: home.path);
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains('${home.path}/Documents/.DS_Store'),
    );
  });

  test('the Developer tools section is merged into the plan', () async {
    await Directory(
      '${home.path}/.yarn/cache/some-package',
    ).create(recursive: true);

    final repository = CleanRepositoryImpl(home: home.path);
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains('${home.path}/.yarn/cache/some-package'),
    );
  });

  test('the Apps & utilities section is merged into the plan', () async {
    await Directory('${home.path}/.cacher/logs').create(recursive: true);
    await File('${home.path}/.cacher/logs/run.log').create(recursive: true);

    final repository = CleanRepositoryImpl(home: home.path);
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains('${home.path}/.cacher/logs/run.log'),
    );
  });

  test('the Browser profile caches section is merged into the plan', () async {
    await Directory(
      '${home.path}/Library/Application Support/Vivaldi/Default/GPUCache',
    ).create(recursive: true);
    await File(
      '${home.path}/Library/Application Support/Vivaldi/Default/GPUCache/blob',
    ).create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      browserProfileCaches: BrowserProfileCachesLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            'pgrep -x Vivaldi': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
          }),
        ),
      ),
    );
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains(
        '${home.path}/Library/Application Support/Vivaldi/Default/GPUCache/blob',
      ),
    );
  });

  test('the Xcode caches section is merged into the plan', () async {
    await Directory(
      '${home.path}/Library/Developer/Xcode/DerivedData/MyApp-abc123',
    ).create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      xcodeCaches: XcodeCachesLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            for (final process in [
              'Xcode',
              'xcodebuild',
              'xctest',
              'XCTRunner',
              'XCBBuildService',
              'swift-frontend',
            ])
              'pgrep -x $process': ProcessResult.failure(
                ProcessFailure.nonZeroExit('pgrep', 1, ''),
              ),
          }),
        ),
      ),
    );
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains('${home.path}/Library/Developer/Xcode/DerivedData/MyApp-abc123'),
    );
  });

  test('the Cloud storage section is merged into the plan', () async {
    await Directory(
      '${home.path}/Library/Caches/com.microsoft.OneDrive',
    ).create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      cloudStorage: CloudStorageLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            for (final process in ['Dropbox', 'Google Drive', 'OneDrive'])
              'pgrep -x $process': ProcessResult.failure(
                ProcessFailure.nonZeroExit('pgrep', 1, ''),
              ),
          }),
        ),
      ),
    );
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains('${home.path}/Library/Caches/com.microsoft.OneDrive'),
    );
  });

  test('the Virtualization section is merged into the plan', () async {
    await Directory(
      '${home.path}/Library/Containers/com.utmapp.UTM/Data/tmp',
    ).create(recursive: true);
    await File(
      '${home.path}/Library/Containers/com.utmapp.UTM/Data/tmp/download.iso',
    ).create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      utmCaches: UtmCachesLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            'pgrep -x UTM': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
          }),
        ),
      ),
    );
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains(
        '${home.path}/Library/Containers/com.utmapp.UTM/Data/tmp/download.iso',
      ),
    );
  });

  test('the Virtualization section is merged into the plan with its owner '
      'command intact', () async {
    await Directory('${home.path}/.tart/cache/entry').create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      tartCache: TartCacheLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            'pgrep -x tart': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
          }),
        ),
        probe: FakeProcessRunner({
          'tart --version': ProcessResult.success('1.0'),
        }),
      ),
    );
    final plan = await repository.watchPlan().first;

    final cacheRoot = '${home.path}/.tart/cache';
    final candidate = plan.candidates.singleWhere((c) => c.path == cacheRoot);
    expect(candidate.ownerCommand, isNotNull);
    expect(candidate.recheckProcessGuard?.exactNames, ['tart']);
  });

  test('refuses an owner command whose recheck guard finds the process now '
      'running, without running the command', () async {
    final commandRunner = FakeProcessRunner({
      'tart prune --entries caches --older-than 30': ProcessResult.success(''),
    });
    final repository = CleanRepositoryImpl(
      home: home.path,
      ownerCommandRunner: commandRunner,
      recheckGuard: ProcessGuard(
        FakeProcessRunner({'pgrep -x tart': ProcessResult.success('123')}),
      ),
    );
    final candidate = CleanCandidate(
      path: '${home.path}/.tart/cache',
      section: 'Virtualization',
      ownerCommand: const [
        'tart',
        'prune',
        '--entries',
        'caches',
        '--older-than',
        '30',
      ],
      recheckProcessGuard: const ProcessRecheck(exactNames: ['tart']),
    );

    final failures = await repository.approve([candidate]);

    expect(failures, contains(candidate.path));
    final entries = readLog();
    expect(entries.single['outcome'], 'refused');
  });

  test('refuses an owner command whose recheck guard cannot confirm the '
      'process state', () async {
    final repository = CleanRepositoryImpl(
      home: home.path,
      recheckGuard: ProcessGuard(
        FakeProcessRunner({
          'pgrep -x tart': ProcessResult.failure(
            ProcessFailure.nonZeroExit('pgrep', 2, 'usage'),
          ),
        }),
      ),
    );
    final candidate = CleanCandidate(
      path: '${home.path}/.tart/cache',
      section: 'Virtualization',
      ownerCommand: const ['tart', 'prune'],
      recheckProcessGuard: const ProcessRecheck(exactNames: ['tart']),
    );

    final failures = await repository.approve([candidate]);

    expect(failures, contains(candidate.path));
  });

  test('runs an owner command once its recheck guard reconfirms the process '
      'is not running', () async {
    final commandRunner = FakeProcessRunner({
      'tart prune --entries caches --older-than 30': ProcessResult.success(''),
    });
    final repository = CleanRepositoryImpl(
      home: home.path,
      ownerCommandRunner: commandRunner,
      recheckGuard: ProcessGuard(
        FakeProcessRunner({
          'pgrep -x tart': ProcessResult.failure(
            ProcessFailure.nonZeroExit('pgrep', 1, ''),
          ),
        }),
      ),
    );
    final candidate = CleanCandidate(
      path: '${home.path}/.tart/cache',
      section: 'Virtualization',
      ownerCommand: const [
        'tart',
        'prune',
        '--entries',
        'caches',
        '--older-than',
        '30',
      ],
      recheckProcessGuard: const ProcessRecheck(exactNames: ['tart']),
    );

    final failures = await repository.approve([candidate]);

    expect(failures, isEmpty);
    final entries = readLog();
    expect(entries.single['outcome'], 'cleared');
  });

  test('the Apps & utilities section is merged with Final Cut Pro generated '
      'caches intact', () async {
    await Directory(
      '${home.path}/Movies/MyLibrary.fcpbundle/Event 1/Render Files'
      '/High Quality Media',
    ).create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      finalCutProGeneratedCaches: FinalCutProGeneratedCachesLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            'pgrep -x Final Cut Pro': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
            'pgrep -f /Final Cut Pro.app/': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
          }),
        ),
      ),
    );
    final plan = await repository.watchPlan().first;

    final target =
        '${home.path}/Movies/MyLibrary.fcpbundle/Event 1/Render Files'
        '/High Quality Media';
    final candidate = plan.candidates.singleWhere((c) => c.path == target);
    expect(candidate.recheckProcessGuard?.exactNames, ['Final Cut Pro']);
  });

  test('the Apps & utilities section is merged with JianyingPro generated '
      'caches', () async {
    await Directory(
      '${home.path}/Movies/JianyingPro/User Data/Cache/recognize',
    ).create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      jianyingProGeneratedCaches: JianyingProGeneratedCachesLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            'pgrep -x VideoFusion-macOS': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
            'pgrep -f /VideoFusion-macOS.app/Contents/MacOS/VideoFusion-macOS':
                ProcessResult.failure(
                  ProcessFailure.nonZeroExit('pgrep', 1, ''),
                ),
          }),
        ),
      ),
    );
    final plan = await repository.watchPlan().first;

    expect(
      plan.candidates.map((c) => c.path),
      contains('${home.path}/Movies/JianyingPro/User Data/Cache/recognize'),
    );
  });

  test('the Developer tools section is merged with the pnpm store owner '
      'command intact', () async {
    final storePath = '${home.path}/pnpm-store';
    await Directory(storePath).create(recursive: true);

    final repository = CleanRepositoryImpl(
      home: home.path,
      pnpmStore: PnpmStoreLocalDataSource(
        home: home.path,
        guard: ProcessGuard(
          FakeProcessRunner({
            r'pgrep -f (^|/)pnpm(\.cjs)?([[:space:]]|$)': ProcessResult.failure(
              ProcessFailure.nonZeroExit('pgrep', 1, ''),
            ),
          }),
        ),
        probe: FakeProcessRunner({
          'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version':
              ProcessResult.success('9.1.0'),
          'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm store path':
              ProcessResult.success(storePath),
        }),
      ),
    );
    final plan = await repository.watchPlan().first;

    final candidate = plan.candidates.singleWhere((c) => c.path == storePath);
    expect(candidate.ownerCommand, [
      'env',
      'COREPACK_ENABLE_DOWNLOAD_PROMPT=0',
      'pnpm',
      'store',
      'prune',
    ]);
  });

  test('the System section is merged with a stale macOS installer app '
      'discovered through MacosInstallerLocalDataSource', () async {
    final applications = await Directory.systemTemp.createTemp(
      'hoopix_installer_apps_',
    );
    addTearDown(() async {
      if (applications.existsSync()) {
        await applications.delete(recursive: true);
      }
    });
    final installerPath = '${applications.path}/Install macOS Sequoia.app';
    await Directory(installerPath).create(recursive: true);

    final oldMtime =
        DateTime.now()
            .subtract(const Duration(days: 20))
            .millisecondsSinceEpoch ~/
        1000;
    final responses = {
      'sw_vers -productVersion': ProcessResult.success('15.6.1'),
      'stat -f%d:%i:%m $installerPath': ProcessResult.success(
        '16777232:123456:$oldMtime',
      ),
      'plutil -extract RecommendedUpdates json -o - '
              '/Library/Preferences/com.apple.SoftwareUpdate.plist':
          ProcessResult.success('[]'),
      'pgrep -f $installerPath': ProcessResult.failure(
        ProcessFailure.nonZeroExit('pgrep', 1, ''),
      ),
      '/usr/libexec/PlistBuddy -c Print :DTPlatformVersion '
          '$installerPath/Contents/Info.plist': ProcessResult.success(
        '14.0',
      ),
    };

    final repository = CleanRepositoryImpl(
      home: home.path,
      macosInstaller: MacosInstallerLocalDataSource(
        probe: MacosInstallerProbe(probe: FakeProcessRunner(responses)),
        guard: ProcessGuard(FakeProcessRunner(responses)),
        directory: (path) =>
            path == '/Applications' ? applications : Directory(path),
      ),
    );
    final plan = await repository.watchPlan().first;

    final candidate = plan.candidates.singleWhere(
      (c) => c.path == installerPath,
    );
    expect(candidate.requiresPrivilegedDeletion, isTrue);
    expect(
      candidate.revalidatorKey,
      MacosInstallerLocalDataSource.revalidatorKey,
    );
  });

  test(
    'the App leftovers section is merged with an orphaned system service',
    () async {
      final servicesRoot = await Directory.systemTemp.createTemp(
        'hoopix_repo_orphan_services_',
      );
      addTearDown(() async {
        if (servicesRoot.existsSync()) {
          await servicesRoot.delete(recursive: true);
        }
      });
      final daemons = Directory('${servicesRoot.path}/LaunchDaemons')
        ..createSync();
      final agents = Directory('${servicesRoot.path}/LaunchAgents')
        ..createSync();
      final helpers = Directory('${servicesRoot.path}/PrivilegedHelperTools')
        ..createSync();
      final plistPath = '${daemons.path}/com.example.orphan.plist';
      await File(plistPath).create(recursive: true);

      final responses = {
        '/usr/libexec/PlistBuddy -c Print :ProgramArguments:0 $plistPath':
            ProcessResult.success('/usr/local/opt/example/bin/example'),
        "mdfind kMDItemCFBundleIdentifier == 'com.example.orphan'":
            ProcessResult.success(''),
      };

      final repository = CleanRepositoryImpl(
        home: home.path,
        orphanedSystemServices: OrphanedSystemServicesLocalDataSource(
          home: home.path,
          probe: FakeProcessRunner(responses),
          directory: (path) => switch (path) {
            '/Library/LaunchDaemons' => daemons,
            '/Library/LaunchAgents' => agents,
            '/Library/PrivilegedHelperTools' => helpers,
            _ => Directory(path),
          },
        ),
      );
      final plan = await repository.watchPlan().first;

      final candidate = plan.candidates.singleWhere((c) => c.path == plistPath);
      expect(candidate.requiresPrivilegedDeletion, isTrue);
      expect(
        candidate.revalidatorKey,
        OrphanedSystemServicesLocalDataSource.revalidatorKey,
      );
    },
  );

  test(
    'runs privileged deletion instead of moving its path to Trash',
    () async {
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        fail('Trash must not be called for a privileged-deletion candidate');
      });
      messenger.setMockMethodCallHandler(privilegedDeleteChannel, (call) async {
        return <Object?, Object?>{};
      });

      final repository = CleanRepositoryImpl(home: home.path);
      final candidate = CleanCandidate(
        path: '/Library/Caches/com.apple.iconservices.store',
        section: 'System',
        sizeBytes: 10,
        requiresPrivilegedDeletion: true,
      );

      final failures = await repository.approve([candidate]);

      expect(failures, isEmpty);
      final entries = readLog();
      expect(entries.single['outcome'], 'cleared');
      expect(entries.single['path'], candidate.path);
    },
  );

  test('records a refusal the privileged-delete channel reports', () async {
    messenger.setMockMethodCallHandler(privilegedDeleteChannel, (call) async {
      final paths = (call.arguments as Map)['paths'] as List;
      return {
        for (final p in paths) p: 'administrator privileges were not granted',
      };
    });

    final repository = CleanRepositoryImpl(home: home.path);
    final candidate = CleanCandidate(
      path: '/Library/Caches/com.apple.iconservices.store',
      section: 'System',
      requiresPrivilegedDeletion: true,
    );

    final failures = await repository.approve([candidate]);

    expect(failures, contains(candidate.path));
    final entries = readLog();
    expect(entries.single['outcome'], 'refused');
  });

  test(
    'a batch mixing Trash and privileged-deletion candidates runs both, one prompt for the batch',
    () async {
      final trashCalls = <MethodCall>[];
      final privilegedCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(trashChannel, (call) async {
        trashCalls.add(call);
        return <Object?, Object?>{};
      });
      messenger.setMockMethodCallHandler(privilegedDeleteChannel, (call) async {
        privilegedCalls.add(call);
        return <Object?, Object?>{};
      });

      final repository = CleanRepositoryImpl(home: home.path);
      final trashCandidate = CleanCandidate(
        path: '${home.path}/Library/Caches/plain',
        section: 'User essentials',
        sizeBytes: 5,
      );
      final systemCandidate = CleanCandidate(
        path: '/Library/Caches/com.apple.iconservices.store',
        section: 'System',
        sizeBytes: 10,
        requiresPrivilegedDeletion: true,
      );

      final failures = await repository.approve([
        trashCandidate,
        systemCandidate,
      ]);

      expect(failures, isEmpty);
      expect(trashCalls.single.arguments, {
        'paths': [trashCandidate.path],
      });
      expect(privilegedCalls, hasLength(1));
      expect(privilegedCalls.single.arguments, {
        'paths': [systemCandidate.path],
      });
      final outcomes = {for (final e in readLog()) e['path']: e['outcome']};
      expect(outcomes[trashCandidate.path], 'trashed');
      expect(outcomes[systemCandidate.path], 'cleared');
    },
  );

  group('privileged-deletion rechecks', () {
    late Directory applications;

    setUp(() async {
      applications = await Directory.systemTemp.createTemp(
        'hoopix_repo_installer_apps_',
      );
      await Directory(
        '${applications.path}/Install macOS Sequoia.app',
      ).create(recursive: true);
    });

    tearDown(() async {
      if (applications.existsSync()) await applications.delete(recursive: true);
    });

    String installerPath() => '${applications.path}/Install macOS Sequoia.app';

    /// Responses that make the installer eligible. Mutated in place by the
    /// tests below to simulate state changing between scan and approval.
    Map<String, ProcessResult> eligibleResponses() {
      final oldMtime =
          DateTime.now()
              .subtract(const Duration(days: 20))
              .millisecondsSinceEpoch ~/
          1000;
      return {
        'sw_vers -productVersion': ProcessResult.success('15.6.1'),
        'stat -f%d:%i:%m ${installerPath()}': ProcessResult.success(
          '16777232:123456:$oldMtime',
        ),
        'plutil -extract RecommendedUpdates json -o - '
                '/Library/Preferences/com.apple.SoftwareUpdate.plist':
            ProcessResult.success('[]'),
        'pgrep -f ${installerPath()}': ProcessResult.failure(
          ProcessFailure.nonZeroExit('pgrep', 1, ''),
        ),
        '/usr/libexec/PlistBuddy -c Print :DTPlatformVersion '
            '${installerPath()}/Contents/Info.plist': ProcessResult.success(
          '14.0',
        ),
      };
    }

    /// Scans with [responses], returning the repository and the installer
    /// candidate it found, so a test can mutate [responses] before
    /// approving it.
    Future<(CleanRepositoryImpl, CleanCandidate)> scan(
      Map<String, ProcessResult> responses, {
      ProcessGuard? recheckGuard,
    }) async {
      final repository = CleanRepositoryImpl(
        home: home.path,
        recheckGuard: recheckGuard,
        macosInstaller: MacosInstallerLocalDataSource(
          probe: MacosInstallerProbe(probe: FakeProcessRunner(responses)),
          guard: ProcessGuard(FakeProcessRunner(responses)),
          directory: (path) =>
              path == '/Applications' ? applications : Directory(path),
        ),
      );
      final plan = await repository.watchPlan().first;
      final candidate = plan.candidates.singleWhere(
        (c) => c.path == installerPath(),
      );
      return (repository, candidate);
    }

    test('refuses when the recheck guard finds the installer now running, '
        'without deleting it', () async {
      messenger.setMockMethodCallHandler(privilegedDeleteChannel, (call) async {
        fail('privileged delete must not run once the recheck finds it busy');
      });

      final responses = eligibleResponses();
      final (repository, candidate) = await scan(
        responses,
        recheckGuard: ProcessGuard(
          FakeProcessRunner({
            'pgrep -f ${installerPath()}': ProcessResult.success('123'),
          }),
        ),
      );

      final failures = await repository.approve([candidate]);

      expect(failures, contains(candidate.path));
      final entries = readLog();
      expect(entries.single['outcome'], 'refused');
    });

    test(
      'refuses when the installer identity changed since the scan',
      () async {
        messenger.setMockMethodCallHandler(privilegedDeleteChannel, (
          call,
        ) async {
          fail('privileged delete must not run for a replaced bundle');
        });

        final responses = eligibleResponses();
        final (repository, candidate) = await scan(responses);

        // The updater replaced the bundle between scan and approval.
        responses['stat -f%d:%i:%m ${installerPath()}'] = ProcessResult.success(
          '16777232:999999:1700000001',
        );

        final failures = await repository.approve([candidate]);

        expect(failures, contains(candidate.path));
      },
    );

    test('refuses when a software update became pending', () async {
      messenger.setMockMethodCallHandler(privilegedDeleteChannel, (call) async {
        fail('privileged delete must not run with an update pending');
      });

      final responses = eligibleResponses();
      final (repository, candidate) = await scan(responses);

      responses['plutil -extract RecommendedUpdates json -o - '
              '/Library/Preferences/com.apple.SoftwareUpdate.plist'] =
          ProcessResult.success('[{"foo":"bar"}]');

      final failures = await repository.approve([candidate]);

      expect(failures, contains(candidate.path));
    });

    test(
      'deletes once the revalidation and process recheck both hold',
      () async {
        final privilegedCalls = <MethodCall>[];
        messenger.setMockMethodCallHandler(privilegedDeleteChannel, (
          call,
        ) async {
          privilegedCalls.add(call);
          return <Object?, Object?>{};
        });

        final responses = eligibleResponses();
        final (repository, candidate) = await scan(responses);

        final failures = await repository.approve([candidate]);

        expect(failures, isEmpty);
        expect(privilegedCalls.single.arguments, {
          'paths': [installerPath()],
        });
        final entries = readLog();
        expect(entries.single['outcome'], 'cleared');
      },
    );

    test(
      'refuses a candidate naming a revalidator that does not exist',
      () async {
        messenger.setMockMethodCallHandler(privilegedDeleteChannel, (
          call,
        ) async {
          fail('privileged delete must not run for an unknown revalidator');
        });

        final repository = CleanRepositoryImpl(home: home.path);
        final candidate = CleanCandidate(
          path: '/Applications/Install macOS Sequoia.app',
          section: 'System',
          requiresPrivilegedDeletion: true,
          revalidatorKey: 'not-a-real-revalidator',
        );

        final failures = await repository.approve([candidate]);

        expect(failures, contains(candidate.path));
      },
    );
  });

  test('an empty owner command is a refusal, not a silent no-op', () async {
    final repository = CleanRepositoryImpl(home: home.path);
    final candidate = CleanCandidate(
      path: '${home.path}/.cache/tool',
      section: 'Developer tools',
      ownerCommand: const [],
    );

    final failures = await repository.approve([candidate]);

    expect(failures, contains(candidate.path));
  });
}
