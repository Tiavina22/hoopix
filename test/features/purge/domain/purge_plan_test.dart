import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_identity_snapshot.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';

const _identity = PurgeIdentitySnapshot(
  parentIdentity: '1:1',
  targetIdentity: '1:2',
);

PurgeCandidate _candidate({
  required PurgeActivityState activity,
  int? sizeBytes,
}) => PurgeCandidate(
  path: '/repo/node_modules',
  searchRoot: '/repo',
  activity: activity,
  isCloudSynced: false,
  identityAtScan: _identity,
  sizeBytes: sizeBytes,
);

void main() {
  test('an old candidate is default-selected', () {
    expect(
      _candidate(activity: PurgeActivityState.old).isDefaultSelected,
      isTrue,
    );
  });

  test('a recent candidate is not default-selected', () {
    expect(
      _candidate(activity: PurgeActivityState.recent).isDefaultSelected,
      isFalse,
    );
  });

  test('an uncertain candidate is not default-selected either', () {
    expect(
      _candidate(activity: PurgeActivityState.uncertain).isDefaultSelected,
      isFalse,
    );
  });

  test('withSize preserves every other field', () {
    final original = _candidate(activity: PurgeActivityState.old);
    final sized = original.withSize(2048);

    expect(sized.sizeBytes, 2048);
    expect(sized.path, original.path);
    expect(sized.searchRoot, original.searchRoot);
    expect(sized.activity, original.activity);
    expect(sized.identityAtScan, original.identityAtScan);
  });

  test('reclaimableBytes sums measured candidates, treating null as zero', () {
    final plan = PurgePlan(
      candidates: [
        _candidate(activity: PurgeActivityState.old, sizeBytes: 100),
        _candidate(activity: PurgeActivityState.old, sizeBytes: null),
        _candidate(activity: PurgeActivityState.old, sizeBytes: 50),
      ],
    );

    expect(plan.reclaimableBytes, 150);
  });
}
