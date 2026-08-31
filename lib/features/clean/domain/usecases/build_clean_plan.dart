import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';
import 'package:hoopix/features/clean/domain/entities/normalize_targets.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';

/// One section's proposal: the paths it would like removed.
class CleanSectionTargets {
  const CleanSectionTargets(this.section, this.paths);

  final String section;
  final List<String> paths;
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

        final reason = _refuse(path);
        candidates.add(
          CleanCandidate(
            path: path,
            section: section.section,
            skipReason: reason,
          ),
        );
      }
    }

    return CleanPlan(candidates: candidates);
  }

  CleanSkipReason? _refuse(String path) {
    if (shouldProtectPath(path, home: home)) return CleanSkipReason.protected;
    if (whitelist.covers(path)) return CleanSkipReason.whitelisted;
    if (holdsModelCache(path)) return CleanSkipReason.compiledModelCache;
    return null;
  }
}
