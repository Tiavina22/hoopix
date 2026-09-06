import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/purge/domain/entities/purge_identity_snapshot.dart';

/// Ports the shape of `_mole_snapshot_path_identity` /
/// `_mole_path_matches_identity` (`lib/core/file_ops.sh`): purge's
/// concurrency-safety model is optimistic identity pinning, not mutual
/// exclusion — capture a path's own `dev:inode`, and its parent
/// directory's, at scan time, then re-stat and compare immediately before
/// deletion. A parent-directory identity change catches the directory
/// itself being renamed or replaced; a target identity change catches the
/// leaf being deleted and recreated in between — the same TOCTOU window a
/// project's own build tooling can reopen between when purge found an
/// artifact and when the user approves removing it.
class PurgeIdentity {
  PurgeIdentity({ProcessRunner? probe})
    : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5));

  final ProcessRunner _probe;

  /// `dev:inode` for [path], or null when it cannot be stat'd at all.
  Future<String?> identityOf(String path) async {
    final result = await _probe.run('stat', ['-f', '%d:%i', path]);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Both halves of a snapshot for [path]: its parent directory's identity
  /// and its own. Either can be null if that half is currently unreadable
  /// — a snapshot that cannot fully resolve is never treated as a match
  /// later, so a candidate found now but gone before its own snapshot
  /// completes is not proposed at all.
  Future<PurgeIdentitySnapshot> snapshot(String path) async {
    final parent = _parentOf(path);
    final parentId = await identityOf(parent);
    final targetId = await identityOf(path);
    return PurgeIdentitySnapshot(
      parentIdentity: parentId,
      targetIdentity: targetId,
    );
  }

  /// Whether [path] still matches [expected] — re-stats both halves right
  /// now and compares. Fails closed: an incomplete [expected] snapshot, or
  /// a path that no longer resolves either half, never matches.
  Future<bool> matches(String path, PurgeIdentitySnapshot expected) async {
    if (!expected.isComplete) return false;
    final current = await snapshot(path);
    return current.parentIdentity == expected.parentIdentity &&
        current.targetIdentity == expected.targetIdentity;
  }

  String _parentOf(String path) {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final lastSlash = trimmed.lastIndexOf('/');
    if (lastSlash <= 0) return '/';
    return trimmed.substring(0, lastSlash);
  }
}
