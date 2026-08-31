/// Collapses a cleanup batch to the set that will actually be acted on.
///
/// Port of `normalize_paths_for_cleanup` in Mole's `bin/clean.sh`. Two jobs:
///
/// A child listed alongside its own parent is dropped. Deleting the parent
/// takes the child with it, so keeping both would delete something that is
/// already gone and count its bytes twice in the reclaimed total.
///
/// Gradle's script caches nest a hash directory under a DSL directory under
/// a version; the whole hash directory is the unit worth removing, so deeper
/// paths inside one collapse to it.
List<String> normalizeCleanupTargets(List<String> paths, {required String home}) {
  if (paths.isEmpty) return const [];

  final collapsed = <String>[];
  for (final path in paths) {
    final normalized = _collapse(path, home);
    if (!collapsed.contains(normalized)) collapsed.add(normalized);
  }

  // Lexicographic order puts every parent immediately before its children,
  // so one pass that remembers the last kept path is enough.
  collapsed.sort();

  final kept = <String>[];
  String? lastKept;
  for (final path in collapsed) {
    if (lastKept != null && path.startsWith('$lastKept/')) continue;
    kept.add(path);
    lastKept = path;
  }
  return kept;
}

/// A Gradle script-cache path deeper than its hash directory, reduced to
/// that directory; anything else unchanged apart from a trailing slash.
String _collapse(String path, String home) {
  final trimmed =
      path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  final root = '$home/.gradle/caches/';
  if (!trimmed.startsWith(root)) return trimmed;

  final parts = trimmed.substring(root.length).split('/');
  // version / (groovy-dsl|kotlin-dsl) / hash / something-deeper
  if (parts.length <= 3) return trimmed;
  if (parts[1] != 'groovy-dsl' && parts[1] != 'kotlin-dsl') return trimmed;
  if (parts[0].isEmpty || parts[2].isEmpty) return trimmed;

  return '$root${parts[0]}/${parts[1]}/${parts[2]}';
}
