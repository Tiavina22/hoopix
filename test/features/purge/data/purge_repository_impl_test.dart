import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/features/purge/data/datasources/purge_identity.dart';
import 'package:hoopix/features/purge/data/repositories/purge_repository_impl.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_identity_snapshot.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_purge_repo_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<Directory> backdatedNodeModules() async {
    final project = await Directory('${home.path}/Code/myproject').create(
      recursive: true,
    );
    await File('${project.path}/package.json').create();
    final artifact = await Directory(
      '${project.path}/node_modules',
    ).create(recursive: true);

    final target = DateTime.now().subtract(const Duration(days: 30));
    final stamp =
        '${target.year.toString().padLeft(4, '0')}'
        '${target.month.toString().padLeft(2, '0')}'
        '${target.day.toString().padLeft(2, '0')}'
        '${target.hour.toString().padLeft(2, '0')}'
        '${target.minute.toString().padLeft(2, '0')}';
    await Process.run('touch', ['-t', stamp, artifact.path]);
    return artifact;
  }

  PurgeRepositoryImpl repository({
    Map<String, ProcessResult> statResponses = const {},
    Map<String, ProcessResult> duResponses = const {},
  }) => PurgeRepositoryImpl(
    home: home.path,
    identity: PurgeIdentity(probe: FakeProcessRunner(statResponses)),
    sizeProbe: SizeProbe(FakeProcessRunner(duResponses)),
  );

  test('finds an old artifact under a discovered project, sized', () async {
    final artifact = await backdatedNodeModules();

    final plans = await repository(
      statResponses: {
        'stat -f %d:%i ${artifact.parent.path}': ProcessResult.success(
          '1:100\n',
        ),
        'stat -f %d:%i ${artifact.path}': ProcessResult.success('1:200\n'),
      },
      duResponses: {
        'du -skPx ${artifact.path}': ProcessResult.success('2048\t${artifact.path}'),
      },
    ).watchPlan().toList();

    final last = plans.last;
    expect(last.candidates, hasLength(1));
    final candidate = last.candidates.single;
    expect(candidate.path, artifact.path);
    expect(candidate.activity, PurgeActivityState.old);
    expect(candidate.sizeBytes, 2048 * 1024);
    expect(candidate.isDefaultSelected, isTrue);
  });

  test('never proposes a path whose identity cannot be pinned', () async {
    final artifact = await backdatedNodeModules();

    final plan = await repository(
      statResponses: {
        'stat -f %d:%i ${artifact.parent.path}': ProcessResult.success(
          '1:100\n',
        ),
        'stat -f %d:%i ${artifact.path}': ProcessResult.failure(
          ProcessFailure.nonZeroExit('stat', 1, ''),
        ),
      },
    ).watchPlan().first;

    expect(plan.candidates, isEmpty);
  });

  test('never proposes a protected artifact (unrecognized vendor/)', () async {
    final project = await Directory('${home.path}/Code/myproject').create(
      recursive: true,
    );
    await File('${project.path}/package.json').create();
    await Directory('${project.path}/vendor').create();

    final plan = await repository().watchPlan().first;

    expect(plan.candidates, isEmpty);
  });

  group('approve', () {
    Future<PurgeCandidate> candidateFor(Directory artifact) async {
      final identity = PurgeIdentity(
        probe: FakeProcessRunner({
          'stat -f %d:%i ${artifact.parent.path}': ProcessResult.success(
            '1:100\n',
          ),
          'stat -f %d:%i ${artifact.path}': ProcessResult.success('1:200\n'),
        }),
      );
      final snapshot = await identity.snapshot(artifact.path);
      return PurgeCandidate(
        path: artifact.path,
        searchRoot: '${home.path}/Code',
        activity: PurgeActivityState.old,
        isCloudSynced: false,
        identityAtScan: snapshot,
        sizeBytes: 100,
      );
    }

    test('deletes a candidate whose identity is unchanged', () async {
      final artifact = await backdatedNodeModules();
      final candidate = await candidateFor(artifact);

      final failures = await repository(
        statResponses: {
          'stat -f %d:%i ${artifact.parent.path}': ProcessResult.success(
            '1:100\n',
          ),
          'stat -f %d:%i ${artifact.path}': ProcessResult.success('1:200\n'),
        },
      ).approve([candidate]);

      expect(failures, isEmpty);
      expect(artifact.existsSync(), isFalse);
    });

    test('refuses when the target identity has changed since scan', () async {
      final artifact = await backdatedNodeModules();
      final candidate = await candidateFor(artifact);

      final failures = await repository(
        statResponses: {
          'stat -f %d:%i ${artifact.parent.path}': ProcessResult.success(
            '1:100\n',
          ),
          // A different inode now: replaced since the scan.
          'stat -f %d:%i ${artifact.path}': ProcessResult.success('1:999\n'),
        },
      ).approve([candidate]);

      expect(failures[artifact.path], 'changed since scan');
      expect(artifact.existsSync(), isTrue);
    });

    test('refuses a candidate that no longer exists', () async {
      final artifact = await backdatedNodeModules();
      final candidate = await candidateFor(artifact);
      await artifact.delete(recursive: true);

      final failures = await repository().approve([candidate]);

      expect(failures[candidate.path], 'no longer exists');
    });

    test('refuses a candidate that is now protected', () async {
      final project = await Directory('${home.path}/Code/myproject').create(
        recursive: true,
      );
      final vendor = await Directory('${project.path}/vendor').create();
      // No composer.json / go.mod / Rails markers: unrecognized owner,
      // protected by default even though it passed at scan time under a
      // different rule set (simulates the owner marker having disappeared).
      final candidate = PurgeCandidate(
        path: vendor.path,
        searchRoot: '${home.path}/Code',
        activity: PurgeActivityState.old,
        isCloudSynced: false,
        identityAtScan: const PurgeIdentitySnapshot(
          parentIdentity: '1:1',
          targetIdentity: '1:2',
        ),
      );

      final failures = await repository(
        statResponses: {
          'stat -f %d:%i ${project.path}': ProcessResult.success('1:1\n'),
          'stat -f %d:%i ${vendor.path}': ProcessResult.success('1:2\n'),
        },
      ).approve([candidate]);

      expect(failures[vendor.path], 'now protected');
      expect(vendor.existsSync(), isTrue);
    });

    test('refuses a candidate that is now a symlink', () async {
      final artifact = await backdatedNodeModules();
      final candidate = await candidateFor(artifact);
      await artifact.delete(recursive: true);
      final real = await Directory('${home.path}/elsewhere').create();
      await Link(artifact.path).create(real.path);

      final failures = await repository().approve([candidate]);

      expect(failures[candidate.path], 'is now a symlink');
    });
  });
}
