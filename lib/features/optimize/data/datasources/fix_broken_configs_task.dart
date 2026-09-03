import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_fix_broken_configs` / `fix_broken_preferences`
/// (`lib/optimize/maintenance.sh`): a preference plist that fails `plutil
/// -lint` is genuinely malformed, not merely unfamiliar, and removing it
/// lets the owning app regenerate a fresh one on next launch instead of
/// silently failing to read its settings.
///
/// Two roots, two depths, matching Mole's own two calls: the top level of
/// `~/Library/Preferences` (direct files only — nothing below it is a
/// preference plist Mole repairs this way) additionally protects
/// `loginwindow.plist`; `~/Library/Preferences/ByHost` is walked fully and
/// does not. Every `com.apple.*` or `.GlobalPreferences*` name is protected
/// in both. [shouldProtectPath] runs again on each lint failure, the same
/// second check Mole's own `_repair_preference_plists_in_dir` makes right
/// before its `safe_remove`.
///
/// Not ported: Mole's batched `plutil -lint` (512 files at a time, a shell
/// performance optimization) and its 15-second scan time budget. A typical
/// `~/Library/Preferences` tree is small enough that linting one file at a
/// time, bounded by [ProcessRunner]'s own per-call timeout, does not need
/// either.
class FixBrokenConfigsTask implements OptimizeTaskRunner {
  FixBrokenConfigsTask({
    required this.home,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'fix_broken_configs',
    name: 'Broken Config Repair',
    description: 'Fix corrupted preferences files',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    var repaired = 0;
    var failed = 0;

    final prefsDir = '$home/Library/Preferences';
    final (topRepaired, topFailed) = await _repairPlistsIn(
      prefsDir,
      recursive: false,
      protectLoginwindow: true,
    );
    repaired += topRepaired;
    failed += topFailed;

    final (byHostRepaired, byHostFailed) = await _repairPlistsIn(
      '$prefsDir/ByHost',
      recursive: true,
      protectLoginwindow: false,
    );
    repaired += byHostRepaired;
    failed += byHostFailed;

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: repaired, failed: failed),
    );
  }

  Future<(int, int)> _repairPlistsIn(
    String dir, {
    required bool recursive,
    required bool protectLoginwindow,
  }) async {
    final List<FileSystemEntity> entries;
    try {
      entries = _directory(
        dir,
      ).listSync(recursive: recursive, followLinks: false);
    } on FileSystemException {
      return (0, 0);
    }

    var repaired = 0;
    var failed = 0;

    for (final entity in entries) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.plist')) continue;
      if (_isProtectedByName(
        entity.path,
        protectLoginwindow: protectLoginwindow,
      )) {
        continue;
      }

      final lint = await _probe.run('plutil', ['-lint', entity.path]);
      if (lint.isSuccess) continue; // valid plist, nothing to repair

      if (shouldProtectPath(entity.path, home: home)) continue;

      try {
        await entity.delete();
        repaired++;
      } on FileSystemException {
        failed++;
      }
    }

    return (repaired, failed);
  }

  bool _isProtectedByName(String path, {required bool protectLoginwindow}) {
    final filename = path.split('/').last;
    if (filename.startsWith('com.apple.')) return true;
    if (filename.startsWith('.GlobalPreferences')) return true;
    if (protectLoginwindow && filename == 'loginwindow.plist') return true;
    return false;
  }
}
