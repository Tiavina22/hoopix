import 'dart:io';

import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_saved_state_cleanup` (`lib/optimize/tasks.sh`): a
/// `*.savedState` bundle under `~/Library/Saved Application State` is the
/// window-restore snapshot an app rebuilds the next time it launches, so
/// this is a permanent delete rather than a Trash move — same reasoning as
/// [CacheRefreshTask]. Only bundles untouched for 30+ days qualify, the
/// same floor Mole uses, so a session still in use today is never touched.
class SavedStateCleanupTask implements OptimizeTaskRunner {
  SavedStateCleanupTask({
    required this.home,
    Directory Function(String path)? directory,
    DateTime Function()? now,
  }) : _directory = directory ?? Directory.new,
       _now = now ?? DateTime.now;

  final String home;
  final Directory Function(String path) _directory;
  final DateTime Function() _now;

  static const _minimumAgeDays = 30;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'saved_state_cleanup',
    name: 'App State Cleanup',
    description: 'Remove old saved application states (30+ days)',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final root = _directory('$home/Library/Saved Application State');

    final List<FileSystemEntity> entries;
    try {
      entries = root.listSync(followLinks: false);
    } on FileSystemException {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    var applied = 0;
    var failed = 0;
    final cutoff = _now().subtract(const Duration(days: _minimumAgeDays));

    for (final entity in entries) {
      if (entity is! Directory) continue;
      if (!entity.path.endsWith('.savedState')) continue;

      final FileStat stat;
      try {
        stat = entity.statSync();
      } on FileSystemException {
        continue;
      }
      if (stat.modified.isAfter(cutoff)) continue;
      if (shouldProtectPath(entity.path, home: home)) continue;

      try {
        await entity.delete(recursive: true);
        applied++;
      } on FileSystemException {
        failed++;
      }
    }

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: applied, failed: failed),
    );
  }
}
