import 'dart:io';

import 'package:hoopix/features/clean/data/datasources/system_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// One age sweep: which root, which filenames, how deep, how old, and
/// whether removing a match needs administrator privileges.
class _AgeSweep {
  const _AgeSweep({
    required this.root,
    required this.patterns,
    required this.maxDepth,
    required this.olderThanDays,
    required this.privileged,
  });

  final String root;

  /// Filename globs, in the two shapes Mole actually passes: `*` for every
  /// name, and `*.ext` for one extension.
  final List<String> patterns;

  /// Levels below [root], counted the way `find -maxdepth` counts them: a
  /// file directly inside the root is depth 1.
  final int maxDepth;
  final int olderThanDays;

  /// False for a root the invoking user can write, whose matches go to the
  /// Trash like any ordinary candidate.
  final bool privileged;
}

/// Ports the age-based sweeps of `clean_deep_system` (`lib/clean/system.sh`):
/// stale system caches, crash reports, system logs, and Adobe's own logs.
/// Shares [SystemLocalDataSource.system]'s section name.
///
/// Mole runs `find … -delete` under one sudo session. hoopix cannot: the
/// scan happens every time the Clean screen opens, and a privileged scan
/// would mean a password prompt just to look. So the enumeration here is
/// unprivileged — every one of these roots is world-readable, or is simply
/// skipped when it is not — and only the removal is elevated. That is
/// strictly better for the user than a bulk sweep: every match goes through
/// the same funnel as any other candidate (protection, whitelist, dedup,
/// sizing) and is shown by path before anything is approved.
///
/// Only regular files are ever proposed, never a directory, and symlinks
/// are neither followed nor proposed — with `followLinks: false` a symlink
/// is not a [File], so both fall out for free.
///
/// `/Library/Caches` matches go to the Trash rather than the privileged
/// channel: it is `drwxrwxrwt`, and a privileged path-based delete must not
/// cross an ancestor the invoking user can write. Mole draws the same line
/// through `_mole_privileged_path_has_mutable_ancestor`, which downgrades
/// exactly these to an unprivileged removal.
///
/// Not ported: `/private/tmp` and `/private/var/tmp` are deliberately left
/// alone — Mole's own comment is that age and a bounded scan do not prove
/// third-party runtime state is disposable. `/Library/Updates` and
/// `/macOS Install Data` stay untouched too: Software Update owns them.
/// The `/private/var/folders` sweeps (browser code-signature clones, GPU
/// shader caches, aborted Aerial downloads) need a privileged *scan* to see
/// anything at all, which is the one thing this design refuses to do.
class SystemAgedSweepsLocalDataSource {
  SystemAgedSweepsLocalDataSource({
    Directory Function(String path)? directory,
    DateTime Function()? now,
    this.visitBudget = 20000,
  }) : _directory = directory ?? Directory.new,
       _now = now ?? DateTime.now;

  final Directory Function(String path) _directory;
  final DateTime Function() _now;

  /// How many entries one enumerate() may look at across all sweeps.
  /// `/Library/Caches` five levels deep is unbounded in principle, and
  /// Mole bounds the same work with a two-minute section deadline; this is
  /// the same idea in the shape hoopix can enforce. Stopping early yields
  /// fewer candidates, never a wrong one.
  final int visitBudget;

  /// Mole's retention constants: MOLE_TEMP_FILE_AGE_DAYS,
  /// MOLE_LOG_AGE_DAYS and MOLE_CRASH_REPORT_AGE_DAYS are all 7.
  static const _retentionDays = 7;

  static const _sweeps = [
    // `*.log` is folded in here because Mole only runs its second
    // /Library/Caches pass when the log and temp-file retentions differ,
    // and today they are both 7 days.
    _AgeSweep(
      root: '/Library/Caches',
      patterns: ['*.cache', '*.tmp', '*.log'],
      maxDepth: 5,
      olderThanDays: _retentionDays,
      privileged: false,
    ),
    _AgeSweep(
      root: '/Library/Logs/DiagnosticReports',
      patterns: ['*'],
      maxDepth: 1,
      olderThanDays: _retentionDays,
      privileged: true,
    ),
    _AgeSweep(
      root: '/private/var/log',
      patterns: ['*.log', '*.gz', '*.asl'],
      maxDepth: 3,
      olderThanDays: _retentionDays,
      privileged: true,
    ),
    _AgeSweep(
      root: '/Library/Logs/Adobe',
      patterns: ['*'],
      maxDepth: 5,
      olderThanDays: _retentionDays,
      privileged: true,
    ),
    _AgeSweep(
      root: '/Library/Logs/CreativeCloud',
      patterns: ['*'],
      maxDepth: 5,
      olderThanDays: _retentionDays,
      privileged: true,
    ),
  ];

  CleanSectionTargets enumerate() {
    var budget = visitBudget;
    final paths = <String>[];
    final privileged = <String>{};

    for (final sweep in _sweeps) {
      final matches = <String>[];
      budget = _collect(sweep, matches, budget);
      paths.addAll(matches);
      if (sweep.privileged) privileged.addAll(matches);
      if (budget <= 0) break;
    }

    return CleanSectionTargets(
      SystemLocalDataSource.system,
      paths,
      privilegedDeletionPaths: privileged,
    );
  }

  /// Walks [sweep]'s root, appending matches to [into]. Returns what is
  /// left of [budget]. A root that is a symlink is refused outright, the
  /// way Mole refuses to search one.
  int _collect(_AgeSweep sweep, List<String> into, int budget) {
    final root = _directory(sweep.root).path;
    if (FileSystemEntity.typeSync(root, followLinks: false) !=
        FileSystemEntityType.directory) {
      return budget;
    }

    final cutoff = _now().subtract(Duration(days: sweep.olderThanDays));
    var remaining = budget;

    void walk(String dir, int depth) {
      if (remaining <= 0 || depth > sweep.maxDepth) return;
      final List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        // An unreadable directory is simply not offered. A non-privileged
        // scan degrades by seeing less, never by guessing.
        return;
      }

      for (final entity in entries) {
        if (remaining <= 0) return;
        remaining--;

        if (entity is Directory) {
          walk(entity.path, depth + 1);
          continue;
        }
        if (entity is! File) continue;
        if (!_matchesAny(entity.path.split('/').last, sweep.patterns)) continue;
        if (!_isOlderThan(entity, cutoff)) continue;
        into.add(entity.path);
      }
    }

    walk(root, 1);
    return remaining;
  }

  bool _matchesAny(String name, List<String> patterns) {
    for (final pattern in patterns) {
      if (pattern == '*') return true;
      if (pattern.startsWith('*.') && name.endsWith(pattern.substring(1))) {
        return true;
      }
      if (pattern == name) return true;
    }
    return false;
  }

  /// Unreadable metadata is not evidence of age, so the file is kept.
  bool _isOlderThan(File file, DateTime cutoff) {
    try {
      return file.statSync().modified.isBefore(cutoff);
    } on FileSystemException {
      return false;
    }
  }
}
