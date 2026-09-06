/// Ports `filter_nested_artifacts` (`lib/clean/project.sh`): collapses a
/// list of candidate paths so a deeply nested artifact never survives
/// alongside its own ancestor — a `dist/` inside a `build/` inside a
/// `node_modules/` reports as just the outermost kept one.
///
/// Sorting first (byte-order, matching Mole's `LC_COLLATE=C sort`) puts
/// every ancestor immediately before its descendants, so a single linear
/// pass keeping a path only when it is not prefixed by the last *kept*
/// path collapses arbitrarily deep chains in one pass — the same
/// sort-then-prefix-collapse Mole's own `awk` program performs. A trailing
/// separator is added before comparing so `/foo/bar` is only ever treated
/// as nested under `/foo`, never under a sibling like `/foobar`.
List<String> filterNestedArtifacts(List<String> paths) {
  final withSeparator = [
    for (final path in paths) path.endsWith('/') ? path : '$path/',
  ]..sort();

  final kept = <String>[];
  var lastKept = '';
  for (final current in withSeparator) {
    if (lastKept.isEmpty || !current.startsWith(lastKept)) {
      kept.add(current);
      lastKept = current;
    }
  }

  return [for (final path in kept) path.substring(0, path.length - 1)];
}
