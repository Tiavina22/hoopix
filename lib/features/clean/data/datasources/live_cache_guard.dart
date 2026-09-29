import 'dart:io' as io;

import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/entities/cache_owner_attribution.dart';
import 'package:hoopix/features/clean/domain/entities/user_cache_scope.dart';

/// The last check before a reverse-DNS user cache leaves — port of Mole's
/// `_mole_should_refuse_live_user_cache_path` (`lib/core/file_ops.sh`,
/// Mole #1390, #1439, #1471).
///
/// A cache in scope (see [userCacheScopeOf]) is refused when:
/// - a process plausibly owning it is running, or the process list cannot
///   be read ([CacheOwnerAttribution]);
/// - for a container cache, any process holds the path or one of its
///   descendants open (`lsof +D`), because a container id and the helper
///   writing into it need not share a name;
/// - for a `~/Library/Caches/<id>` path, any process holds one of its
///   SQLite families open — the path itself when it is one, or each family
///   directly inside it.
///
/// Every uncertain answer refuses: an `lsof` that timed out, is missing,
/// exits with anything but a silent 1, or a container path whose identity
/// changed while it was being probed.
///
/// Deliberate divergence from Mole: Mole only trusts an `lsof` that can see
/// root-owned processes (its `sudo -n lsof` fallback rides on the password
/// `mo clean` asks for up front), and otherwise keeps every cache in scope.
/// hoopix has no such session, so an unprivileged `lsof` would make that
/// rule keep most app caches forever. It reads every process of the user
/// instead: an app or helper holding its own cache is always the user's
/// process, as in #1390 and #1472. What it cannot see is a root process
/// holding a file inside the user's own Library.
class LiveCacheGuard {
  LiveCacheGuard({
    required this.home,
    ProcessRunner? processList,
    ProcessRunner? openFiles,
    ProcessRunner? metadata,
    int? selfPid,
    bool Function(String path)? isDirectory,
    List<String>? Function(String directory)? filesIn,
  }) : _processList =
           processList ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _openFiles =
           openFiles ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _metadata =
           metadata ?? const ProcessRunner(timeout: Duration(seconds: 2)),
       _selfPid = selfPid ?? io.pid,
       _isDirectory = isDirectory ?? _defaultIsDirectory,
       _filesIn = filesIn ?? _defaultFilesIn;

  final String home;
  final ProcessRunner _processList;
  final ProcessRunner _openFiles;
  final ProcessRunner _metadata;
  final int _selfPid;
  final bool Function(String path) _isDirectory;

  /// The regular files directly in a directory, or null when it cannot be
  /// listed.
  final List<String>? Function(String directory) _filesIn;

  /// How many `lsof` probes run at once. Each one walks the whole process
  /// list (about 0.2s on a real Mac), so a clean with dozens of app caches
  /// would otherwise wait on them one after another.
  static const _concurrency = 4;

  /// A refusal message for each of [paths] that must not be removed now,
  /// keyed by path. Paths outside every reverse-DNS cache tree are never
  /// in the result. Takes one fresh process snapshot for the whole batch,
  /// so call it immediately before the removal it guards.
  Future<Map<String, String>> refusals(List<String> paths) async {
    final scoped = <String, UserCacheScope>{
      for (final path in paths) path: ?userCacheScopeOf(path, home: home),
    };
    if (scoped.isEmpty) return const {};

    final table = await _snapshot();
    if (table == null) {
      return {
        for (final path in scoped.keys)
          path: 'skipped: could not read the process list',
      };
    }
    final attribution = CacheOwnerAttribution(
      table: table,
      home: home,
      bundleIdOf: _bundleIdOf,
      isDirectory: _isDirectory,
    );

    final refusals = <String, String>{};
    final queue = scoped.entries.toList();
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length) {
        final entry = queue[next++];
        final refusal = await _refusal(entry.key, entry.value, attribution);
        if (refusal != null) refusals[entry.key] = refusal;
      }
    }

    await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
    return refusals;
  }

  Future<String?> _refusal(
    String path,
    UserCacheScope scope,
    CacheOwnerAttribution attribution,
  ) async {
    if (await attribution.isOwnerRunning(scope.owner)) {
      return 'skipped: ${scope.owner} is running';
    }

    final handles = switch (scope.storage) {
      UserCacheStorage.container => await _containerHandles(path),
      UserCacheStorage.standard => await _sqliteHandles(path),
    };
    return switch (handles) {
      _Handles.idle => null,
      _Handles.open => 'skipped: a file in it is open',
      _Handles.unknown => 'skipped: could not confirm no file in it is open',
    };
  }

  Future<ProcessTable?> _snapshot() async {
    final table = await _processList.run('ps', ['-axo', 'pid,ppid,comm,args']);
    if (!table.isSuccess) return null;
    // Only extra evidence: a failed read keeps the argv heuristic, which
    // stays busy for any line it cannot place.
    final executables = await _processList.run('ps', ['-axo', 'pid=,comm=']);
    return ProcessTable.parse(
      table: table.stdout!,
      executables: executables.isSuccess ? executables.stdout! : '',
      selfPid: _selfPid,
    );
  }

  Future<String?> _bundleIdOf(String bundle) async {
    final result = await _metadata.run('plutil', [
      '-extract',
      'CFBundleIdentifier',
      'raw',
      '-o',
      '-',
      '$bundle/Contents/Info.plist',
    ]);
    return result.isSuccess ? result.stdout!.trim() : null;
  }

  /// Any open descendant of a container cache directory, or the file
  /// itself. The path's identity is bound around `lsof`, so a directory
  /// renamed and recreated mid-probe cannot pass on the old one's answer.
  Future<_Handles> _containerHandles(String path) async {
    if (io.FileSystemEntity.typeSync(path, followLinks: false) ==
        io.FileSystemEntityType.notFound) {
      return _Handles.idle;
    }
    final before = await _identity(path);
    if (before == null) return _Handles.unknown;

    final result = _isDirectory(path)
        ? await _openFiles.run('lsof', ['-F', 'pfn', '+D', path])
        : await _openFiles.run('lsof', ['-F', 'pfn', '--', path]);
    final handles = _readLsof(result, recordPrefixes: 'pfn');
    if (handles != _Handles.idle) return handles;

    return await _identity(path) == before ? _Handles.idle : _Handles.unknown;
  }

  /// The SQLite families [path] is, or directly contains, checked one
  /// family per `lsof` call over the members that exist.
  Future<_Handles> _sqliteHandles(String path) async {
    final bases = <String>{};
    if (_isDirectory(path)) {
      // An unreadable directory hides whatever databases it holds; that is
      // not "no SQLite here".
      final files = _filesIn(path);
      if (files == null) return _Handles.unknown;
      for (final file in files) {
        if (isSqliteFamilyPath(file)) bases.add(sqliteFamilyBase(file));
      }
    } else if (isSqliteFamilyPath(path)) {
      bases.add(sqliteFamilyBase(path));
    }

    for (final base in bases) {
      final members = [
        for (final member in [base, '$base-wal', '$base-shm'])
          if (io.FileSystemEntity.typeSync(member, followLinks: false) !=
              io.FileSystemEntityType.notFound)
            member,
      ];
      if (members.isEmpty) continue;
      final handles = _readLsof(
        await _openFiles.run('lsof', ['-F', 'n', '--', ...members]),
        recordPrefixes: 'n',
      );
      if (handles != _Handles.idle) return handles;
    }
    return _Handles.idle;
  }

  /// `dev:inode` of [path] and of its parent, or null when unreadable.
  Future<String?> _identity(String path) async {
    final parent = path.substring(0, path.lastIndexOf('/'));
    final result = await _metadata.run('stat', ['-f', '%d:%i', parent, path]);
    return result.isSuccess ? result.stdout!.trim() : null;
  }

  /// Exit 0 means a match. Exit 1 means none only when `lsof` said nothing
  /// at all; a field record in its output is still positive evidence of use
  /// (it exits 1 when only some requested names are open), and diagnostics
  /// mean an incomplete walk, never a reliable no-match.
  static _Handles _readLsof(
    ProcessResult result, {
    required String recordPrefixes,
  }) {
    if (result.isSuccess) return _Handles.open;
    final failure = result.failure!;
    final stdout = result.stdout ?? '';
    final hasRecord = stdout
        .split('\n')
        .any((line) => line.isNotEmpty && recordPrefixes.contains(line[0]));
    if (hasRecord) return _Handles.open;
    if (failure.kind == ProcessFailureKind.nonZeroExit &&
        failure.exitCode == 1 &&
        stdout.isEmpty &&
        (failure.stderr ?? '').isEmpty) {
      return _Handles.idle;
    }
    return _Handles.unknown;
  }

  static bool _defaultIsDirectory(String path) =>
      io.FileSystemEntity.typeSync(path, followLinks: false) ==
      io.FileSystemEntityType.directory;

  static List<String>? _defaultFilesIn(String directory) {
    try {
      return [
        for (final entity in io.Directory(
          directory,
        ).listSync(followLinks: false))
          if (entity is io.File) entity.path,
      ];
    } on io.FileSystemException {
      return null;
    }
  }
}

enum _Handles { open, idle, unknown }
