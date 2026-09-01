import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports the one verified-safe slice of Mole's `clean_deep_system`
/// (`lib/clean/system.sh`) hoopix can reach today: a single, exact,
/// well-known root-owned system cache Apple regenerates on its own.
///
/// The path here doubles as `PrivilegedDeleteChannel.swift`'s own
/// allowlist — the two lists are grown together, one verified entry at a
/// time, the same way Mole reviews each `safe_sudo_remove` /
/// `safe_sudo_find_delete` call under its own scrutiny. This mirrors
/// [CleanCandidate.requiresPrivilegedDeletion]'s bypass of the ordinary
/// `~/Library`-relative protection funnel: the native side's exact-match
/// list is the safety boundary for this section, not a heuristic.
///
/// Not ported: the rest of `clean_deep_system` — age-based
/// `/Library/Caches` and `/Library/Logs` sweeps, crash reports, macOS
/// installer apps, browser code-signature clone caches, GPU shader caches
/// under `/private/var/folders`, and more — is a large, individually
/// reasoned body of work of its own. This is the first proof that
/// hoopix's privileged-deletion channel works end to end, not the whole
/// section. `clean_local_snapshots` and the orphaned-system-services piece
/// of App leftovers are deferred alongside it, for the same reason: both
/// need this same privilege escalation.
class SystemLocalDataSource {
  const SystemLocalDataSource();

  static const system = 'System';

  static const _iconServicesStore =
      '/Library/Caches/com.apple.iconservices.store';

  CleanSectionTargets enumerate() => const CleanSectionTargets(
    system,
    [_iconServicesStore],
    privilegedDeletionPaths: {_iconServicesStore},
  );
}
