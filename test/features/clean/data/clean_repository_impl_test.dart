import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/browser_profile_caches_local_datasource.dart';
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
