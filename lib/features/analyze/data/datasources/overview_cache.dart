import 'dart:convert';
import 'dart:io';

/// Bumped whenever directory-size semantics change, so entries written by an
/// older build are rejected instead of silently reused.
const _schemaVersion = 1;

const _ttl = Duration(days: 7);

/// A re-measurement usually returns the size already on record, and every
/// save rewrites the whole store. The timestamp is only refreshed once an
/// entry is within this fraction of the TTL of aging out.
const _refreshDivisor = 8;

/// Bounds the single JSON file: past [_maxEntries], drop the oldest in one
/// pass down to [_keepEntries] so eviction doesn't run on every save.
const _maxEntries = 1000;
const _keepEntries = 900;

class _Snapshot {
  const _Snapshot(this.size, this.updated);

  final int size;
  final DateTime updated;

  bool get isFresh => DateTime.now().difference(updated) < _ttl;

  Map<String, Object?> toJson() => {
    'size': size,
    'updated': updated.toIso8601String(),
    'schemaVersion': _schemaVersion,
  };

  static _Snapshot? tryParse(Object? json) {
    if (json is! Map) return null;
    if (json['schemaVersion'] != _schemaVersion) return null;
    final size = json['size'];
    final updated = DateTime.tryParse('${json['updated']}');
    if (size is! int || size <= 0 || updated == null) return null;
    return _Snapshot(size, updated);
  }
}

/// Remembers the overview's measured sizes between launches, so reopening
/// Analyze shows numbers immediately instead of an empty column while `du`
/// runs again. Mirrors Mole's `overview_sizes.json` store.
///
/// Every read and write is best effort: a corrupt or unreadable cache means
/// a slower overview, never a failure.
class OverviewCache {
  OverviewCache({required String? cacheDirectory})
    : _directory = cacheDirectory;

  /// Null when the environment has no HOME, which disables caching entirely.
  final String? _directory;

  Map<String, _Snapshot>? _entries;

  File? get _file =>
      _directory == null ? null : File('$_directory/overview_sizes.json');

  Map<String, _Snapshot> _load() {
    final loaded = _entries;
    if (loaded != null) return loaded;

    final entries = <String, _Snapshot>{};
    try {
      final file = _file;
      if (file != null && file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map) {
          decoded.forEach((path, value) {
            final snapshot = _Snapshot.tryParse(value);
            if (snapshot != null && snapshot.isFresh) {
              entries['$path'] = snapshot;
            }
          });
        }
      }
    } on Object {
      // A corrupt store is simply an empty one; it gets overwritten on the
      // next save.
    }

    return _entries = entries;
  }

  /// The remembered size for [path], or null when there is no fresh entry.
  int? sizeOf(String path) => _load()[path]?.size;

  void store(String path, int? size) {
    // No directory means no cache at all — keeping the value in memory would
    // make this instance answer from a store that was never written.
    if (_directory == null) return;
    if (path.isEmpty || size == null || size <= 0) return;

    final entries = _load();
    final existing = entries[path];
    // Nothing changed and the record is still comfortably fresh — skip
    // rewriting the whole file.
    if (existing != null &&
        existing.size == size &&
        DateTime.now().difference(existing.updated) < _ttl ~/ _refreshDivisor) {
      return;
    }

    entries[path] = _Snapshot(size, DateTime.now());
    _evict(entries);
    _persist(entries);
  }

  void _evict(Map<String, _Snapshot> entries) {
    if (entries.length <= _maxEntries) return;
    final byAge = entries.entries.toList()
      ..sort((a, b) => a.value.updated.compareTo(b.value.updated));
    for (final entry in byAge.take(entries.length - _keepEntries)) {
      entries.remove(entry.key);
    }
  }

  void _persist(Map<String, _Snapshot> entries) {
    final file = _file;
    if (file == null) return;

    try {
      file.parent.createSync(recursive: true);
      // Written to a uniquely named temp file first, then renamed, so a
      // second instance can never read a half-written store.
      final temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      temporary.writeAsStringSync(
        jsonEncode({
          for (final entry in entries.entries) entry.key: entry.value.toJson(),
        }),
      );
      temporary.renameSync(file.path);
    } on Object {
      // Losing the cache costs a slower next launch, nothing more.
    }
  }
}
