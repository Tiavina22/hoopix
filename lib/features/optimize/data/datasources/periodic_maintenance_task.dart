import 'dart:io';

import 'package:hoopix/core/platform/privileged_command.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_periodic_maintenance` (`lib/optimize/tasks.sh`): runs macOS's
/// own daily/weekly/monthly maintenance scripts when they look stale — a
/// missing or 7+ day old `/var/log/daily.out` — rather than every run.
/// `periodic` itself was removed in macOS 26, so its absence at the fixed
/// path Apple ships it at is reported as `unavailable`, not `failed`.
class PeriodicMaintenanceTask implements OptimizeTaskRunner {
  PeriodicMaintenanceTask({
    PrivilegedCommand? privilegedCommand,
    FileSystemEntityType Function(String path)? typeOf,
    DateTime Function()? now,
    String? periodicPath,
    String? dailyLogPath,
  }) : _privilegedCommand = privilegedCommand ?? const PrivilegedCommand(),
       _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false)),
       _now = now ?? DateTime.now,
       _periodicPath = periodicPath ?? '/usr/sbin/periodic',
       _dailyLogPath = dailyLogPath ?? '/var/log/daily.out';

  final PrivilegedCommand _privilegedCommand;
  final FileSystemEntityType Function(String path) _typeOf;
  final DateTime Function() _now;
  final String _periodicPath;
  final String _dailyLogPath;

  static const _staleAfter = Duration(days: 7);

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'periodic_maintenance',
    name: 'Periodic Maintenance',
    description: 'Run macOS daily/weekly/monthly maintenance scripts if stale',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    if (_typeOf(_periodicPath) != FileSystemEntityType.file) {
      return OptimizeTaskResult(
        task: task,
        outcome: OptimizeOutcome.unavailable,
      );
    }

    final logFile = File(_dailyLogPath);
    if (logFile.existsSync()) {
      final DateTime modified;
      try {
        modified = logFile.statSync().modified;
      } on FileSystemException {
        return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
      }
      if (_now().difference(modified) < _staleAfter) {
        return OptimizeTaskResult(
          task: task,
          outcome: OptimizeOutcome.unchanged,
        );
      }
    }
    // A missing log is treated as stale — it means periodic has never run
    // on this machine, which is exactly the case a run should fix.

    final failure = await _privilegedCommand.run('run_periodic_maintenance');
    return OptimizeTaskResult(
      task: task,
      outcome: failure == null
          ? OptimizeOutcome.applied
          : OptimizeOutcome.failed,
    );
  }
}
