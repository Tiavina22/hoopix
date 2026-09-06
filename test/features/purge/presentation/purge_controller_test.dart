import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_identity_snapshot.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_repository.dart';
import 'package:hoopix/features/purge/domain/usecases/approve_purge_plan.dart';
import 'package:hoopix/features/purge/domain/usecases/watch_purge_plan.dart';
import 'package:hoopix/features/purge/presentation/state/purge_controller.dart';

const _identity = PurgeIdentitySnapshot(
  parentIdentity: '1:1',
  targetIdentity: '1:2',
);

PurgeCandidate _candidate(
  String path, {
  PurgeActivityState activity = PurgeActivityState.old,
  bool isCloudSynced = false,
  int? sizeBytes,
}) => PurgeCandidate(
  path: path,
  searchRoot: '/repo',
  activity: activity,
  isCloudSynced: isCloudSynced,
  identityAtScan: _identity,
  sizeBytes: sizeBytes,
);

class _FakePurgeRepository implements PurgeRepository {
  _FakePurgeRepository(this.plans);

  final List<PurgePlan> plans;
  final List<List<String>> approvedCalls = [];

  @override
  Stream<PurgePlan> watchPlan() => Stream.fromIterable(plans);

  @override
  Future<Map<String, String>> approve(List<PurgeCandidate> approved) async {
    approvedCalls.add([for (final c in approved) c.path]);
    return const {};
  }
}

void main() {
  test('an old candidate starts selected by default', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(candidates: [_candidate('/repo/node_modules')]),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isSelected('/repo/node_modules'), isTrue);
    expect(controller.selected, hasLength(1));
  });

  test('a recent candidate starts unselected by default', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(
        candidates: [
          _candidate('/repo/node_modules', activity: PurgeActivityState.recent),
        ],
      ),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isSelected('/repo/node_modules'), isFalse);
    expect(controller.selected, isEmpty);
  });

  test('an uncertain candidate also starts unselected', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(
        candidates: [
          _candidate(
            '/repo/node_modules',
            activity: PurgeActivityState.uncertain,
          ),
        ],
      ),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.isSelected('/repo/node_modules'), isFalse);
  });

  test('toggling flips selection', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(candidates: [_candidate('/repo/node_modules')]),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );
    controller.start();
    await Future<void>.delayed(Duration.zero);

    controller.toggle('/repo/node_modules');
    expect(controller.isSelected('/repo/node_modules'), isFalse);

    controller.toggle('/repo/node_modules');
    expect(controller.isSelected('/repo/node_modules'), isTrue);
  });

  test('a later size-only update does not re-seed default selection', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(candidates: [_candidate('/repo/node_modules')]),
      PurgePlan(
        candidates: [_candidate('/repo/node_modules', sizeBytes: 5000)],
      ),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );
    controller.start();
    await Future<void>.delayed(Duration.zero);

    controller.toggle(
      '/repo/node_modules',
    ); // user unchecks the one old default
    await Future<void>.delayed(Duration.zero);

    expect(controller.isSelected('/repo/node_modules'), isFalse);
  });

  test('selectedReclaimableBytes only counts selected candidates', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(
        candidates: [
          _candidate('/repo/a', sizeBytes: 100),
          _candidate(
            '/repo/b',
            sizeBytes: 200,
            activity: PurgeActivityState.recent,
          ),
        ],
      ),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );
    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedReclaimableBytes, 100);
  });

  test('selectedHasCloudSynced reflects only the checked rows', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(
        candidates: [
          _candidate('/repo/a'),
          _candidate(
            '/repo/b',
            isCloudSynced: true,
            activity: PurgeActivityState.recent,
          ),
        ],
      ),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );
    controller.start();
    await Future<void>.delayed(Duration.zero);

    // /repo/b is cloud-synced but recent, so it is not selected by default.
    expect(controller.selectedHasCloudSynced, isFalse);

    controller.toggle('/repo/b');
    expect(controller.selectedHasCloudSynced, isTrue);
  });

  test('approve sends only the selected candidates and re-scans', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(candidates: [_candidate('/repo/a'), _candidate('/repo/b')]),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );
    controller.start();
    await Future<void>.delayed(Duration.zero);

    controller.toggle('/repo/b'); // uncheck one

    final failures = await controller.approve();

    expect(failures, isEmpty);
    expect(repo.approvedCalls.single, ['/repo/a']);
  });

  test(
    'setAllSelected(false) then (true) clears and restores selection',
    () async {
      final repo = _FakePurgeRepository([
        PurgePlan(candidates: [_candidate('/repo/a'), _candidate('/repo/b')]),
      ]);
      final controller = PurgeController(
        WatchPurgePlan(repo),
        ApprovePurgePlan(repo),
      );
      controller.start();
      await Future<void>.delayed(Duration.zero);

      controller.setAllSelected(false);
      expect(controller.selected, isEmpty);

      controller.setAllSelected(true);
      expect(controller.selected, hasLength(2));
    },
  );

  test('canApprove is false until something is selected', () async {
    final repo = _FakePurgeRepository([
      PurgePlan(
        candidates: [
          _candidate('/repo/a', activity: PurgeActivityState.recent),
        ],
      ),
    ]);
    final controller = PurgeController(
      WatchPurgePlan(repo),
      ApprovePurgePlan(repo),
    );
    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.canApprove, isFalse);
  });
}
