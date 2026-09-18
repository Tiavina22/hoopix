import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/directory_scanner.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_cache.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/large_files_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/local_snapshot_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/overview_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/reveal_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/trash_local_datasource.dart';
import 'package:hoopix/features/analyze/data/repositories/analyze_repository_impl.dart';
import 'package:hoopix/features/history/data/repositories/history_repository_impl.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/data/repositories/optimize_repository_impl.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/purge/data/datasources/purge_identity.dart';
import 'package:hoopix/features/purge/data/repositories/purge_repository_impl.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';

import '../../../support/fake_process_runner.dart';

class _Task implements OptimizeTaskRunner {
  _Task(this.task, this.outcome);

  @override
  final OptimizeTask task;
  final OptimizeOutcome outcome;

  @override
  Future<OptimizeTaskResult> run() async =>
      OptimizeTaskResult(task: task, outcome: outcome);
}

/// History used to show only Clean and Uninstall, because nothing else wrote
/// to the log. This drives Purge, Analyze and Optimize for real, into one temp
/// home, and reads the result back through the same repository the screen
/// uses, so a writer and the reader cannot drift apart unnoticed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trashChannel = MethodChannel('fit.hoopix/trash');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_history_e2e_');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(trashChannel, null);
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('Purge, Analyze and Optimize all show up in History', () async {
    // Purge: a real permanent delete of a real (temp) directory.
    final artifact = await Directory(
      '${home.path}/Code/app/node_modules',
    ).create(recursive: true);
    final identity = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i ${artifact.parent.path}': ProcessResult.success('1:1\n'),
        'stat -f %d:%i ${artifact.path}': ProcessResult.success('1:2\n'),
      }),
    );
    await File('${artifact.parent.path}/package.json').create();
    final candidate = PurgeCandidate(
      path: artifact.path,
      searchRoot: '${home.path}/Code',
      activity: PurgeActivityState.old,
      isCloudSynced: false,
      identityAtScan: await identity.snapshot(artifact.path),
      sizeBytes: 4096,
    );
    await PurgeRepositoryImpl(
      home: home.path,
      identity: identity,
      sizeProbe: SizeProbe(FakeProcessRunner(const {})),
    ).approve([candidate]);

    // Analyze: a Trash move, the native side answered by a stub.
    messenger.setMockMethodCallHandler(
      trashChannel,
      (call) async => <Object?, Object?>{},
    );
    final runner = FakeProcessRunner(const {});
    await AnalyzeRepositoryImpl.withDataSources(
      overview: OverviewLocalDataSource(runner, home: home.path),
      directory: DirectoryLocalDataSource(
        DirectoryScanner(),
        DirectoryCache(cacheDirectory: null),
      ),
      largeFiles: LargeFilesLocalDataSource(runner),
      reveal: RevealLocalDataSource(runner),
      trash: const TrashLocalDataSource(),
      localSnapshot: LocalSnapshotLocalDataSource(runner),
      log: OperationLog(home: home.path),
    ).moveToTrash(['/Users/me/big.iso']);

    // Optimize: one task that changed something.
    await OptimizeRepositoryImpl(
      home: home.path,
      tasks: [
        _Task(
          const OptimizeTask(
            action: 'sqlite_vacuum',
            name: 'Database Vacuum',
            description: 'd',
          ),
          OptimizeOutcome.applied,
        ),
      ],
    ).runAll().toList();

    final entries = await HistoryRepositoryImpl(
      home: home.path,
    ).recentOperations();

    // Newest first: Optimize ran last.
    expect(entries.map((e) => (e.command, e.outcome, e.path)), [
      ('optimize', OperationOutcome.applied, 'Database Vacuum'),
      ('analyze', OperationOutcome.trashed, '/Users/me/big.iso'),
      ('purge', OperationOutcome.cleared, artifact.path),
    ]);
    expect(entries.last.sizeBytes, 4096);
  });
}
