import 'dart:convert';
import 'dart:io';

import 'package:hoopix/features/analyze/data/models/analyze_entry_model.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

/// Bumped whenever sizing semantics change, so entries written by an older
/// build are rejected rather than silently reused.
const _schemaVersion = 1;

/// Past this, an entry is deleted rather than reused.
const _ttl = Duration(days: 7);

/// The shorter window a cached listing may still be painted from while a
/// fresh scan runs behind it.
const _staleTtl = Duration(days: 3);

/// Directory mtime is noisy on macOS — a touch that changed nothing bumps it.
/// A modification within this of the recorded time is ignored, and beyond it
/// a recent enough entry is still reused rather than forcing a full rescan.
const _modifiedGrace = Duration(minutes: 30);
const _reuseWindow = Duration(hours: 24);

/// Memoizing a directory holding a handful of files costs more than it
/// saves: the entry takes a whole block plus an inode, and reading it back
/// is slower than the single listing it replaces. Only subtrees expensive
/// enough to rescan earn a file.
const _minFiles = 100;
const _minBytes = 10 * 1024 * 1024;

/// Backstop for trees that clear the thresholds anyway.
const _maxFiles = 5000;
const _maxBytes = 50 * 1024 * 1024;

/// Remembers directory listings between visits, so returning to a directory
/// paints immediately instead of walking it again. Mirrors the analyzer
/// cache in Mole, including its admission thresholds and its refusal to
/// store a total that depended on hardlink deduplication.
///
/// Every read and write is best effort: a broken cache means a slower
/// listing, never a failure.
class DirectoryCache {
  DirectoryCache({required String? cacheDirectory})
    : _directory = cacheDirectory == null ? null : '$cacheDirectory/analyzer';

  final String? _directory;

  /// One file per directory, named by a hash of its path.
  File? _fileFor(String path) {
    final directory = _directory;
    if (directory == null) return null;
    return File('$directory/${_stableHash(path)}.json');
  }

  /// FNV-1a, written out rather than using `String.hashCode`: Dart makes no
  /// promise that its hash stays the same across SDK versions, and a hash
  /// that shifts would orphan every entry on the next Flutter upgrade.
  static String _stableHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(value)) {
      hash = (hash ^ unit) * 0x100000001b3;
      // Dart ints are 64-bit and wrap, which is what FNV-1a expects.
      hash &= 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// The remembered listing for [path], or null when there is nothing
  /// trustworthy to show.
  ///
  /// [allowStale] is the first-paint mode: it accepts an entry the strict
  /// rules would refuse, on the understanding that a real scan is already
  /// running behind it.
  DirectoryScan? load(String path, {bool allowStale = false}) {
    final file = _fileFor(path);
    if (file == null) return null;

    final Map<String, Object?> json;
    try {
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        _discard(file);
        return null;
      }
      json = decoded;
    } on Object {
      // Truncated or foreign content will never decode; it only costs a
      // block until something prunes it.
      _discard(file);
      return null;
    }

    if (json['schemaVersion'] != _schemaVersion) {
      _discard(file);
      return null;
    }

    final scannedAt = DateTime.tryParse('${json['scannedAt']}');
    if (scannedAt == null) {
      _discard(file);
      return null;
    }

    final directory = Directory(path);
    if (!directory.existsSync()) {
      // Nothing will ever refresh or reuse this. Churn-heavy trees would
      // otherwise leave one orphan per directory behind for a full TTL.
      _discard(file);
      return null;
    }

    final age = DateTime.now().difference(scannedAt);
    if (age > _ttl) {
      _discard(file);
      return null;
    }
    if (allowStale) {
      if (age > _staleTtl) return null;
    } else if (!_survivesModification(json, directory, age)) {
      return null;
    }

    final entries = json['entries'];
    if (entries is! List) return null;

    final parsedEntries = [
      for (final entry in entries) ?_entryFrom(entry),
    ];
    return DirectoryScan(
      path: path,
      status: DirectoryScanStatus.loaded,
      entries: parsedEntries,
      totalBytes: json['totalBytes'] is int ? json['totalBytes']! as int : null,
      totalEntryCount: json['totalEntryCount'] is int
          ? json['totalEntryCount']! as int
          : parsedEntries.length,
    );
  }

  bool _survivesModification(
    Map<String, Object?> json,
    Directory directory,
    Duration age,
  ) {
    final recorded = DateTime.tryParse('${json['directoryModified']}');
    if (recorded == null) return false;

    final DateTime modified;
    try {
      modified = directory.statSync().modified;
    } on Object {
      return false;
    }

    if (!modified.isAfter(recorded)) return true;
    if (modified.difference(recorded) <= _modifiedGrace) return true;
    // Modified for real, but recently enough scanned that a full rescan on
    // every visit would cost more than the drift.
    return age <= _reuseWindow;
  }

  AnalyzeEntry? _entryFrom(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    final name = json['name'];
    if (path is! String || name is! String) return null;

    final accessed = json['accessed'];
    return AnalyzeEntryModel(
      path: path,
      name: name,
      isDirectory: json['isDirectory'] == true,
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes']! as int : null,
      accessed: accessed is String ? DateTime.tryParse(accessed) : null,
    );
  }

  /// Records [scan], if it is worth recording.
  ///
  /// A total that depended on hardlink deduplication is refused: it is
  /// scan-order dependent, so replaying it later could report a size the
  /// directory never had.
  void store(String path, DirectoryScan scan, {required bool deduped}) {
    final file = _fileFor(path);
    if (file == null) return;
    if (deduped) return;
    if (scan.status != DirectoryScanStatus.loaded) return;

    final totalBytes = scan.totalBytes ?? 0;
    if (scan.entries.length < _minFiles && totalBytes < _minBytes) return;

    try {
      file.parent.createSync(recursive: true);
      final modified = Directory(path).statSync().modified;

      final temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      temporary.writeAsStringSync(
        jsonEncode({
          'schemaVersion': _schemaVersion,
          'scannedAt': DateTime.now().toIso8601String(),
          'directoryModified': modified.toIso8601String(),
          'totalBytes': totalBytes,
          'totalEntryCount': scan.totalEntryCount,
          'entries': [
            for (final entry in scan.entries)
              {
                'path': entry.path,
                'name': entry.name,
                'isDirectory': entry.isDirectory,
                'sizeBytes': entry.sizeBytes,
                'accessed': entry.accessed?.toIso8601String(),
              },
          ],
        }),
      );
      temporary.renameSync(file.path);
      _evict();
    } on Object {
      // Losing the cache costs a slower next visit, nothing more.
    }
  }

  /// Keeps the store within its budget by dropping the oldest files once
  /// either cap is passed.
  void _evict() {
    final directory = _directory;
    if (directory == null) return;

    try {
      final files = Directory(directory)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList();

      // Stat once per file: the size is needed for the budget and the mtime
      // for the order, and re-stating inside the loop would also read files
      // that are being deleted.
      final records = [
        for (final file in files)
          if (file.statSync() case final stat)
            (file: file, size: stat.size, modified: stat.modified),
      ]..sort((a, b) => a.modified.compareTo(b.modified));

      var bytes = records.fold<int>(0, (total, record) => total + record.size);
      var count = records.length;
      if (count <= _maxFiles && bytes <= _maxBytes) return;

      // Oldest first, in one pass down to inside both caps.
      for (final record in records) {
        if (count <= _maxFiles && bytes <= _maxBytes) break;
        record.file.deleteSync();
        bytes -= record.size;
        count--;
      }
    } on Object {
      // An unprunable store is a disk-space matter, not a correctness one.
    }
  }

  void _discard(File file) {
    try {
      file.deleteSync();
    } on Object {
      // Already gone, or not ours to remove.
    }
  }
}
