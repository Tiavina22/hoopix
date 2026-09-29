/// Does a running process own a reverse-DNS user cache? Port of Mole's
/// `_mole_load_process_table`, `_mole_user_cache_owner_process_state` and
/// `_mole_process_line_belongs_to_other_app` (`lib/core/file_ops.sh`,
/// Mole #1390).
///
/// Unlinking an open `Cache.db` while its owner still holds it can send
/// that process into an unbounded write loop on unlinked temp files and
/// fill the volume (Autodesk Fusion's AcCoreConsole). Size and mtime are
/// never authority for these trees: only a conclusive "no matching
/// process" may let one go.
library;

import 'package:hoopix/features/clean/domain/entities/user_cache_scope.dart';

/// Measurement tools whose argv names the very path being judged — a `du`
/// over `~/Library/Caches/<id>` would otherwise make every slow-to-measure
/// cache read as owned.
const _measurementTools = {
  'du',
  'find',
  'mdfind',
  'ps',
  'grep',
  'stat',
  'ls',
  'rm',
};

/// hoopix's own bundle id: the app must not vote on itself.
const _selfBundleId = 'com.lyrify.hoopix';

/// One snapshot of the process table, filtered down to the lines allowed
/// to vote on ownership. Each line is the `comm args` text, followed by
/// `\x1f` and the full executable path when `ps` reported one.
class ProcessTable {
  const ProcessTable(this.lines);

  final List<String> lines;

  /// Builds from `ps -axo pid,ppid,comm,args` ([table]) and
  /// `ps -axo pid=,comm=` ([executables]). Drops [selfPid]'s own process
  /// tree — its ancestors and every descendant, which is where hoopix's own
  /// `du` and `lsof` children run — plus the measurement tools and any line
  /// naming hoopix's bundle id.
  ///
  /// Returns null when [table] has no process row at all: a table that
  /// could not be read is not proof that nothing owns a cache.
  static ProcessTable? parse({
    required String table,
    required String executables,
    required int selfPid,
  }) {
    final exe = <int, String>{};
    for (final row in executables.split('\n')) {
      final match = RegExp(r'^\s*(\d+)\s+(/.*)$').firstMatch(row);
      if (match == null) continue;
      final path = match.group(2)!;
      if (path.contains('\x1f')) continue;
      exe[int.parse(match.group(1)!)] = path;
    }

    final parent = <int, int>{};
    final text = <int, String>{};
    final order = <int>[];
    final rows = table.split('\n');
    for (final row in rows.skip(1)) {
      final match = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$').firstMatch(row);
      if (match == null) continue;
      final pid = int.parse(match.group(1)!);
      parent[pid] = int.parse(match.group(2)!);
      text[pid] = match.group(3)!;
      order.add(pid);
    }
    if (order.isEmpty) return null;

    final mine = <int>{};
    for (
      int? p = selfPid;
      p != null && p != 0 && p != 1 && mine.add(p);
      p = parent[p]
    ) {}
    for (final pid in order) {
      var depth = 0;
      for (
        int? p = pid;
        p != null && p != 0 && p != 1 && depth < 64;
        p = parent[p], depth++
      ) {
        if (p == selfPid) {
          mine.add(pid);
          break;
        }
      }
    }

    final lines = <String>[];
    for (final pid in order) {
      if (mine.contains(pid)) continue;
      final line = text[pid]!;
      final comm = line.trimLeft().split(RegExp(r'\s+')).first;
      if (_measurementTools.contains(comm.split('/').last)) continue;
      if (line.toLowerCase().contains(_selfBundleId)) continue;
      final path = exe[pid];
      lines.add(path == null ? line : '$line\x1f$path');
    }
    return ProcessTable(lines);
  }
}

/// Reads the `CFBundleIdentifier` of the app bundle at the given path, or
/// null when it cannot be read.
typedef BundleIdReader = Future<String?> Function(String bundlePath);

/// Answers [isOwnerRunning] against one [ProcessTable] snapshot, memoizing
/// per owner and per bundle for the life of the snapshot.
class CacheOwnerAttribution {
  CacheOwnerAttribution({
    required this.table,
    required this.home,
    required BundleIdReader bundleIdOf,
    required bool Function(String path) isDirectory,
  }) : _bundleIdOf = bundleIdOf,
       _isDirectory = isDirectory;

  final ProcessTable table;
  final String home;
  final BundleIdReader _bundleIdOf;
  final bool Function(String path) _isDirectory;

  final _owners = <String, bool>{};
  final _bundleIds = <String, Future<String?>>{};

  /// Whether a process that plausibly owns [owner]'s cache is running.
  ///
  /// Two acceptance shapes, deliberately asymmetric:
  ///   1. The full reverse-DNS id appears on a line. Self-identifying, so a
  ///      plain case-insensitive substring is enough.
  ///   2. The last label appears as a delimited token AND the same line
  ///      names another component of the id. Corroboration is what makes a
  ///      shared binary name usable: Claude and VS Code both ship a
  ///      Squirrel binary called ShipIt. A line whose executable lives in
  ///      an app bundle is then attributed by that bundle's identifier
  ///      first, so a sibling channel (Brave Origin Nightly) does not keep
  ///      another's cache (Brave Browser Nightly) busy.
  Future<bool> isOwnerRunning(String owner) async {
    final known = _owners[owner];
    if (known != null) return known;
    return _owners[owner] = await _probe(owner);
  }

  Future<bool> _probe(String owner) async {
    final lowerOwner = owner.toLowerCase();
    if (table.lines.any((line) => line.toLowerCase().contains(lowerOwner))) {
      return true;
    }

    final components = owner.split('.');
    final leaf = components.last;
    if (leaf == owner || leaf.length < 4) return false;

    // "com" is in every reverse-DNS id and corroborates nothing.
    final corroborators = [
      for (final component in components.take(components.length - 1))
        if (component.length >= 4 && component.toLowerCase() != 'com')
          RegExp.escape(component),
    ];
    if (corroborators.isEmpty) return false;

    const open = r'(^|[^A-Za-z0-9])';
    const close = r'([^A-Za-z0-9]|$)';
    final leafPattern = RegExp(
      '$open${RegExp.escape(leaf)}$close',
      caseSensitive: false,
    );
    final corroboratorPattern = RegExp(
      '$open(${corroborators.join('|')})$close',
      caseSensitive: false,
    );

    for (final line in table.lines) {
      if (!leafPattern.hasMatch(line)) continue;
      if (!corroboratorPattern.hasMatch(line)) continue;
      if (await _belongsToOtherApp(line, owner, leaf)) continue;
      return true;
    }
    return false;
  }

  /// True when [line]'s executable lives in an app bundle below
  /// `/Applications` or `~/Applications` whose identifier is not [owner]'s
  /// — so the line says nothing about [owner]. Everything uncertain (no
  /// bundle on the line, an unreadable identifier) counts as possibly the
  /// owner's, which keeps the cache.
  Future<bool> _belongsToOtherApp(
    String rawLine,
    String owner,
    String leaf,
  ) async {
    var line = rawLine;
    var executable = '';
    final separator = line.lastIndexOf('\x1f');
    if (separator >= 0) {
      executable = line.substring(separator + 1);
      line = line.substring(0, separator);
    }

    // ps prefixes argv with the 16-character comm. Remove it only when argv
    // repeats that exact path prefix; otherwise keep uncertain lines busy.
    line = line.trimLeft();
    if (line.length > 16) {
      final commPrefix = line.substring(0, 16);
      final arguments = line.substring(16).trimLeft();
      if (commPrefix.startsWith('/') && arguments.startsWith(commPrefix)) {
        line = arguments;
      }
    }

    final field = executable.startsWith('/') ? executable : line;
    final bundle = _bundleOn(field);
    if (bundle == null) return false;
    final id = await (_bundleIds[bundle] ??= _readBundleId(bundle));
    if (id == null) return false;

    final lowerId = id.toLowerCase();
    final lowerOwner = owner.toLowerCase();
    final lowerLeaf = leaf.toLowerCase();
    final executablePattern = RegExp(
      '/${RegExp.escape(leaf)}(\\s|\$)',
      caseSensitive: false,
    );
    final ownsLine =
        lowerId == lowerOwner ||
        lowerId.startsWith('$lowerOwner.') ||
        lowerOwner.startsWith('$lowerId.') ||
        executablePattern.hasMatch(line) ||
        executable.split('/').last.toLowerCase() == lowerLeaf;
    return !ownsLine;
  }

  /// The first existing `.app` directory along [field], from its start,
  /// under an application root — never searching later arguments.
  String? _bundleOn(String field) {
    final homeRoot = home.endsWith('/')
        ? home.substring(0, home.length - 1)
        : home;
    for (final root in ['/Applications', '$homeRoot/Applications']) {
      if (!field.startsWith('$root/')) continue;
      var head = '';
      var tail = field;
      while (tail.contains('.app/')) {
        final cut = tail.indexOf('.app/');
        head = '$head${tail.substring(0, cut)}.app';
        tail = tail.substring(cut + '.app/'.length);
        // Crossing into another absolute argument cannot identify argv[0].
        if (head.contains(' /')) return null;
        if (_isDirectory(head)) return head;
        head = '$head/';
      }
    }
    return null;
  }

  Future<String?> _readBundleId(String bundle) async {
    final id = await _bundleIdOf(bundle);
    return isReverseDnsBundleId(id) ? id : null;
  }
}
