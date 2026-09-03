import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_coreduet_cleanup` (`lib/optimize/tasks.sh`): trims rows older
/// than 90 days from Apple's CoreDuet "Knowledge" usage-history database
/// (powers Siri Suggestions, Handoff, and similar usage-aware features)
/// once its combined size (database plus WAL/SHM sidecars) crosses 100MB.
/// `ZCREATIONDATE` is CoreData's own absolute-time epoch — seconds since
/// 2001-01-01, not Unix time — hence the `strftime` offset in the delete.
class CoreduetCleanupTask implements OptimizeTaskRunner {
  CoreduetCleanupTask({required this.home, ProcessRunner? probe})
    : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 20));

  final String home;
  final ProcessRunner _probe;

  static const _sizeThresholdBytes = 100 * 1024 * 1024;
  static const _deleteOldRows =
      "DELETE FROM ZOBJECT WHERE ZCREATIONDATE < (strftime('%s','now','-90 "
      "days') - strftime('%s','2001-01-01')); VACUUM;";

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'coreduet_cleanup',
    name: 'Usage Data',
    description: 'Clean old usage tracking data',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final dbPath = '$home/Library/Application Support/Knowledge/knowledgeC.db';
    if (FileSystemEntity.typeSync(dbPath, followLinks: false) !=
        FileSystemEntityType.file) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final walPath = '$dbPath-wal';
    final shmPath = '$dbPath-shm';
    final totalSize = _sizeOf(dbPath) + _sizeOf(walPath) + _sizeOf(shmPath);
    if (totalSize < _sizeThresholdBytes) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final available = await _probe.run('sqlite3', ['-version']);
    if (!available.isSuccess) {
      return OptimizeTaskResult(
        task: task,
        outcome: OptimizeOutcome.unavailable,
      );
    }

    var applied = 0;
    var failed = 0;
    for (final sidecar in [walPath, shmPath]) {
      if (FileSystemEntity.typeSync(sidecar, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      try {
        await File(sidecar).delete();
        applied++;
      } on FileSystemException {
        failed++;
      }
    }

    final clean = await _probe.run('sqlite3', [dbPath, _deleteOldRows]);
    clean.isSuccess ? applied++ : failed++;

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: applied, failed: failed),
    );
  }

  int _sizeOf(String path) {
    try {
      return File(path).statSync().size;
    } on FileSystemException {
      return 0;
    }
  }
}
