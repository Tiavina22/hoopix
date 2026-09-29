/// The folders Purge scans — port of Mole's `load_purge_config` and
/// `mole_purge_read_paths_config` (`lib/clean/project.sh`,
/// `lib/clean/purge_shared.sh`).
///
/// A `purge_paths` file that lists at least one folder replaces discovery
/// entirely: that is how a project folder discovery skips (one deeper than
/// it looks, or one that shares a build artifact's name, Mole #1459) stays
/// reachable without widening discovery for everyone. A file with no paths
/// in it, or no file, means discovery.
library;

/// The configured folders in [lines], in order: comments and blank lines
/// skipped, `~` expanded, each folder once.
List<String> configuredPurgeRoots(List<String>? lines, {required String home}) {
  final roots = <String>[];
  for (final raw in lines ?? const <String>[]) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final root = _withoutTrailingSlash(expandPurgeRoot(line, home: home));
    if (!roots.contains(root)) roots.add(root);
  }
  return roots;
}

/// The roots a scan uses: the configured ones when there are any,
/// otherwise whatever [discover] finds.
List<String> purgeScanRoots(
  List<String>? lines, {
  required String home,
  required List<String> Function() discover,
}) {
  final configured = configuredPurgeRoots(lines, home: home);
  return configured.isNotEmpty ? configured : discover();
}

String expandPurgeRoot(String line, {required String home}) =>
    line.startsWith('~') ? '$home${line.substring(1)}' : line;

/// Why [raw] cannot be a scan root, or null when it can. Purge deletes
/// permanently under its roots, so a root must name one real place: an
/// absolute path (or one starting with `~`), with no `..`, and never the
/// whole disk.
String? purgeRootRefusal(String raw, {required String home}) {
  final line = raw.trim();
  if (line.isEmpty) return null;
  final root = expandPurgeRoot(line, home: home);
  if (!root.startsWith('/')) return 'Must be absolute path';
  if (root.split('/').contains('..')) return 'Path traversal not allowed';
  if (_withoutTrailingSlash(root) == '/') return 'Whole disk not allowed';
  return null;
}

/// The whole `purge_paths` file for [roots]; no roots means discovery.
/// Home is written as `~`, as Mole writes it, so the file stays portable.
List<String> purgePathsFileLines(List<String> roots, {required String home}) =>
    [
      '# Hoopix Purge Paths - Directories to scan for project artifacts',
      '# Add one path per line (supports ~ for home directory)',
      '# Delete all paths or this file to use automatic discovery',
      if (roots.isNotEmpty) '',
      for (final root in roots)
        root == home || root.startsWith('$home/')
            ? '~${root.substring(home.length)}'
            : root,
    ];

String _withoutTrailingSlash(String path) =>
    path.length > 1 && path.endsWith('/')
    ? path.substring(0, path.length - 1)
    : path;

/// What the folders editor shows and saves. While [isAutomatic], the list
/// is what discovery found and saving writes no folder, so discovery keeps
/// running on every scan; adding or removing a folder switches to the
/// user's own list.
class PurgeRootsSelection {
  const PurgeRootsSelection._({
    required this.home,
    required this.roots,
    required this.isAutomatic,
    required List<String> discovered,
  }) : _discovered = discovered;

  factory PurgeRootsSelection.load({
    required String home,
    required List<String>? fileLines,
    required List<String> discovered,
  }) {
    final configured = configuredPurgeRoots(fileLines, home: home);
    return PurgeRootsSelection._(
      home: home,
      roots: List.unmodifiable(configured.isEmpty ? discovered : configured),
      isAutomatic: configured.isEmpty,
      discovered: List.unmodifiable(discovered),
    );
  }

  final String home;
  final List<String> roots;
  final bool isAutomatic;
  final List<String> _discovered;

  /// Adds [raw], or says why it cannot be a root.
  ({PurgeRootsSelection selection, String? refusal}) withRoot(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return (selection: this, refusal: null);
    final refusal = purgeRootRefusal(line, home: home);
    if (refusal != null) return (selection: this, refusal: refusal);

    final root = configuredPurgeRoots([line], home: home).single;
    if (roots.contains(root)) return (selection: this, refusal: null);
    return (selection: _custom([...roots, root]), refusal: null);
  }

  PurgeRootsSelection withoutRoot(String root) => _custom([
    for (final existing in roots)
      if (existing != root) existing,
  ]);

  PurgeRootsSelection automatic() => PurgeRootsSelection._(
    home: home,
    roots: _discovered,
    isAutomatic: true,
    discovered: _discovered,
  );

  List<String> toFileLines() =>
      purgePathsFileLines(isAutomatic ? const [] : roots, home: home);

  PurgeRootsSelection _custom(List<String> roots) => PurgeRootsSelection._(
    home: home,
    roots: List.unmodifiable(roots),
    isAutomatic: false,
    discovered: _discovered,
  );
}
