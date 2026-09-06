/// A path's `dev:inode` identity, for both itself and its parent
/// directory, at one point in time — a plain domain value, free of any
/// process/platform dependency, the same shape [ProcessRecheck] takes in
/// Clean. `PurgeIdentity` (`data/datasources/purge_identity.dart`) is what
/// actually reads these from disk and compares them again later.
class PurgeIdentitySnapshot {
  const PurgeIdentitySnapshot({
    required this.parentIdentity,
    required this.targetIdentity,
  });

  final String? parentIdentity;
  final String? targetIdentity;

  bool get isComplete => parentIdentity != null && targetIdentity != null;
}
