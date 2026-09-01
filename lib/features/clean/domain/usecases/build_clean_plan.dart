import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';
import 'package:hoopix/features/clean/domain/entities/normalize_targets.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';

/// One section's proposal: the paths it would like removed.
class CleanSectionTargets {
  const CleanSectionTargets(
    this.section,
    this.paths, {
    this.ownerCommands = const {},
    this.ownerCommandRechecks = const {},
    this.privilegedDeletionPaths = const {},
  });

  final String section;
  final List<String> paths;

  /// path -> the command that reclaims it, for a proposal whose cleanup
  /// mechanism is the owning tool's own cache-clean command (`npm cache
  /// clean --force`, `go clean -modcache`, ...) rather than a Trash move of
  /// the path itself. A path absent here is removed the ordinary way.
  final Map<String, List<String>> ownerCommands;

  /// path -> exact process names an owner command in [ownerCommands] must
  /// reconfirm not running immediately before it runs, closing the race
  /// between scan time and approval. A path absent here runs with no
  /// recheck — most owner commands (npm, corepack, bun) have no such race
  /// in Mole either.
  final Map<String, List<String>> ownerCommandRechecks;

  /// Paths that must be deleted through the administrator-privileges
  /// channel rather than a Trash move — the narrow, explicit set of
  /// root-owned system caches Mole itself only ever reaches through
  /// `sudo`. A path absent here is removed the ordinary way.
  final Set<String> privilegedDeletionPaths;
}

/// Turns what the sections proposed into what will actually happen.
///
/// The order is Mole's `_safe_clean_impl`, and the order matters: a missing
/// target cannot become less safe by being skipped, so existence is checked
/// before the expensive policy probes; every surviving target is then
/// re-checked at the deletion boundary, which for hoopix is the native Trash
/// channel with its own refusals.
///
/// Nothing here deletes. It produces a plan to show the user first.
class BuildCleanPlan {
  const BuildCleanPlan({
    required this.home,
    required this.whitelist,
    required this.exists,
    required this.holdsModelCache,
  });

  final String home;
  final CleanWhitelist whitelist;

  /// Injected so the filter is testable without a filesystem.
  final bool Function(String path) exists;
  final bool Function(String path) holdsModelCache;

  CleanPlan call(List<CleanSectionTargets> sections) {
    final candidates = <CleanCandidate>[];
    final seen = <String>{};

    for (final section in sections) {
      // Collapse first: a child listed beside its parent would otherwise be
      // judged, measured and counted on its own before vanishing with it.
      final targets = normalizeCleanupTargets(section.paths, home: home);

      for (final path in targets) {
        // A path proposed by two sections is one deletion, not two.
        if (!seen.add(path)) continue;

        // Missing targets are simply not the run's business.
        if (!exists(path)) continue;

        final privileged = section.privilegedDeletionPaths.contains(path);
        final reason = _refuse(path, privileged: privileged);
        candidates.add(
          CleanCandidate(
            path: path,
            section: section.section,
            skipReason: reason,
            ownerCommand: section.ownerCommands[path],
            requiresPrivilegedDeletion: privileged,
            recheckProcessGuard: section.ownerCommandRechecks[path],
          ),
        );
      }
    }

    return CleanPlan(candidates: candidates);
  }

  /// [shouldProtectPath] and the compiled-model-cache check exist for
  /// user-space, `~/Library`-relative cleanup; a privileged-deletion target
  /// is an absolute system path outside that model; its blanket
  /// `com.apple.*` filename rule would otherwise block Apple's own
  /// well-known system caches by name, exactly the ones Mole curates for
  /// this section. Its own native-side allowlist
  /// (`PrivilegedDeleteChannel.swift`) is the safety boundary here instead
  /// — an exact-match list, not a heuristic. The user's own whitelist still
  /// applies either way.
  CleanSkipReason? _refuse(String path, {required bool privileged}) {
    if (!privileged) {
      if (shouldProtectPath(path, home: home)) return CleanSkipReason.protected;
      if (holdsModelCache(path)) return CleanSkipReason.compiledModelCache;
    }
    if (whitelist.covers(path)) return CleanSkipReason.whitelisted;
    return null;
  }
}
