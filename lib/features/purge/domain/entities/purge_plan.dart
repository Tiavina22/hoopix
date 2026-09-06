import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_identity_snapshot.dart';

/// One rebuildable project artifact purge found, with what it knows about
/// it so far.
class PurgeCandidate {
  const PurgeCandidate({
    required this.path,
    required this.searchRoot,
    required this.activity,
    required this.isCloudSynced,
    required this.identityAtScan,
    this.sizeBytes,
  });

  final String path;

  /// The scan root this candidate was found under — needed to re-run
  /// [isSafeProjectArtifact] against the same root immediately before
  /// deletion, the same revalidation Mole's own `is_safe_configured_purge_artifact`
  /// performs.
  final String searchRoot;

  final PurgeActivityState activity;

  /// Whether [path] lives under iCloud Drive or a similar synced root —
  /// removing it can propagate to every other device on the same account,
  /// not just this Mac.
  final bool isCloudSynced;

  /// This candidate's `dev:inode` identity, for both itself and its parent
  /// directory, captured when it was found — compared again immediately
  /// before deletion so a path that was renamed, replaced, or swapped out
  /// from under the scan is never removed on stale evidence.
  final PurgeIdentitySnapshot identityAtScan;

  /// Null while unmeasured, or when the size could not be read.
  final int? sizeBytes;

  /// Purge deliberately does not default-select a candidate that looks
  /// active — [PurgeActivityState.recent] — the same way Mole's own
  /// interactive picker leaves those unchecked. An [PurgeActivityState.uncertain]
  /// candidate is treated the same as recent: an inconclusive probe is
  /// never grounds for a default-on checkbox.
  bool get isDefaultSelected => activity == PurgeActivityState.old;

  PurgeCandidate withSize(int? sizeBytes) => PurgeCandidate(
    path: path,
    searchRoot: searchRoot,
    activity: activity,
    isCloudSynced: isCloudSynced,
    identityAtScan: identityAtScan,
    sizeBytes: sizeBytes,
  );
}

/// What a purge run would remove, before it removes anything — the
/// preview is the product, the same reason Clean's own plan exists.
class PurgePlan {
  const PurgePlan({required this.candidates});

  final List<PurgeCandidate> candidates;

  int get reclaimableBytes =>
      candidates.fold(0, (total, c) => total + (c.sizeBytes ?? 0));
}
