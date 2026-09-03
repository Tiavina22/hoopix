import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_quarantine_cleanup` (`lib/optimize/tasks.sh`): clears
/// Gatekeeper's "where did this download come from" history table. This
/// only erases the tracking metadata — it does not touch the quarantine
/// extended attribute already set on any downloaded file, so it cannot be
/// used to bypass Gatekeeper on anything already on disk. macOS recreates
/// the database as needed, and `VACUUM` after the delete is what actually
/// reclaims the freed space.
///
/// In practice this always reports `unchanged`: the database's own
/// filename, `com.apple.LaunchServices.QuarantineEventsV2`, trips
/// [shouldProtectPath]'s blanket `com.apple.*` keyword rule — the same
/// quirk `CacheRefreshTask` documents, and true in Mole itself too, since
/// `opt_quarantine_cleanup` runs the identical `should_protect_path
/// "$quarantine_db"` guard before touching it. The count/delete path below
/// is kept faithful to Mole's source rather than dropped, so a future,
/// more specific exception has somewhere to land.
class QuarantineCleanupTask implements OptimizeTaskRunner {
  QuarantineCleanupTask({
    required this.home,
    ProcessRunner? probe,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 20));

  final String home;
  final ProcessRunner _probe;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'quarantine_cleanup',
    name: 'Quarantine Database Cleanup',
    description: 'Clear Gatekeeper download tracking history',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final available = await _probe.run('sqlite3', ['-version']);
    if (!available.isSuccess) {
      return OptimizeTaskResult(
        task: task,
        outcome: OptimizeOutcome.unavailable,
      );
    }

    final path =
        '$home/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2';
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }
    if (shouldProtectPath(path, home: home)) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final count = await _probe.run('sqlite3', [
      path,
      'SELECT COUNT(*) FROM LSQuarantineEvent;',
    ]);
    final rowCount = int.tryParse(count.stdout?.trim() ?? '');
    if (!count.isSuccess || rowCount == null) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
    }
    if (rowCount == 0) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final clear = await _probe.run('sqlite3', [
      path,
      'DELETE FROM LSQuarantineEvent; VACUUM;',
    ]);
    return OptimizeTaskResult(
      task: task,
      outcome: clear.isSuccess ? OptimizeOutcome.applied : OptimizeOutcome.failed,
    );
  }
}
