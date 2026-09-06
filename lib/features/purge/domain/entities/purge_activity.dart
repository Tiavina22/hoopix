import 'dart:io';

import 'package:hoopix/features/purge/domain/entities/purge_constants.dart';

/// Ports the three-state result of `classify_purge_activity`
/// (`lib/clean/project.sh`): only a complete, bounded scan may ever answer
/// [old] — a timeout or a read failure always fails closed to [uncertain],
/// never silently to [old].
enum PurgeActivityState { recent, old, uncertain }

/// Ports `classify_purge_activity`: whether a purge candidate has been
/// touched recently enough that removing it now would be surprising.
///
/// A directory's own mtime only changes when its direct children are
/// added or removed, not when a file deep inside it is edited, so a
/// bounded probe still walks the tree looking for anything modified more
/// recently than [purgeMinimumAgeDays] ago even after the top-level mtime
/// itself clears that floor.
class PurgeActivityClassifier {
  PurgeActivityClassifier({
    DateTime Function()? now,
    Directory Function(String path)? directory,
    Duration? probeTimeout,
  }) : _now = now ?? DateTime.now,
       _directory = directory ?? Directory.new,
       _probeTimeout = probeTimeout ?? const Duration(seconds: 5);

  final DateTime Function() _now;
  final Directory Function(String path) _directory;
  final Duration _probeTimeout;

  PurgeActivityState classify(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return PurgeActivityState.old;

    final DateTime modified;
    try {
      modified = File(path).statSync().modified;
    } on FileSystemException {
      return PurgeActivityState.uncertain;
    }

    final now = _now();
    final ageDays = now.difference(modified).inDays;
    if (ageDays < purgeMinimumAgeDays) return PurgeActivityState.recent;

    if (type != FileSystemEntityType.directory) return PurgeActivityState.old;

    return _probeForRecentFile(
      path,
      cutoff: now.subtract(Duration(days: ageDays)),
    );
  }

  /// Walks [path] looking for any file modified after [cutoff], stopping
  /// at the first hit — matching `find ... -print -quit` — and bounded by
  /// [_probeTimeout] so a pathological tree cannot hang classification.
  PurgeActivityState _probeForRecentFile(
    String path, {
    required DateTime cutoff,
  }) {
    final deadline = DateTime.now().add(_probeTimeout);
    var timedOut = false;
    var foundRecent = false;

    void walk(String dir) {
      if (timedOut || foundRecent) return;
      if (DateTime.now().isAfter(deadline)) {
        timedOut = true;
        return;
      }

      final List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        timedOut = true;
        return;
      }

      for (final entity in entries) {
        if (timedOut || foundRecent) return;
        if (DateTime.now().isAfter(deadline)) {
          timedOut = true;
          return;
        }
        if (entity is Directory) {
          walk(entity.path);
        } else if (entity is File) {
          try {
            if (entity.statSync().modified.isAfter(cutoff)) {
              foundRecent = true;
              return;
            }
          } on FileSystemException {
            continue;
          }
        }
      }
    }

    walk(path);

    if (timedOut) return PurgeActivityState.uncertain;
    return foundRecent ? PurgeActivityState.recent : PurgeActivityState.old;
  }
}
