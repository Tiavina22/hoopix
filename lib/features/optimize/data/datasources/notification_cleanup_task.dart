import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_notification_cleanup` (`lib/optimize/tasks.sh`): trims
/// delivered notifications older than 30 days once the live database
/// crosses 50MB, then restarts `NotificationCenter` so it reopens the
/// compacted file instead of holding the old one mapped.
///
/// The database path itself moved between macOS releases — Sequoia keeps it
/// under a Group Container, older releases under the per-user Darwin
/// directory — so both are tried, in that order, the same as
/// `resolve_notification_center_db`. Neither path resolving is reported as
/// `unavailable`, not `unchanged`: Mole added this distinction after a
/// missed Sequoia path first looked like a healthy no-op (issue #1368).
class NotificationCleanupTask implements OptimizeTaskRunner {
  NotificationCleanupTask({
    required this.home,
    ProcessRunner? probe,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 20));

  final String home;
  final ProcessRunner _probe;

  static const _sizeThresholdBytes = 50 * 1024 * 1024;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'notification_cleanup',
    name: 'Notifications',
    description: 'Clean old delivered notifications to reduce database bloat',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final dbPath = await _resolveDb();
    if (dbPath == null) {
      return OptimizeTaskResult(
        task: task,
        outcome: OptimizeOutcome.unavailable,
      );
    }

    final int size;
    try {
      size = File(dbPath).statSync().size;
    } on FileSystemException {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
    }
    if (size < _sizeThresholdBytes) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final available = await _probe.run('sqlite3', ['-version']);
    if (!available.isSuccess) {
      return OptimizeTaskResult(
        task: task,
        outcome: OptimizeOutcome.unavailable,
      );
    }

    final clean = await _probe.run('sqlite3', [
      dbPath,
      "DELETE FROM record WHERE delivered_date < strftime('%s','now','-30 days'); VACUUM;",
    ]);
    if (!clean.isSuccess) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
    }

    // Best-effort: launchd respawns it, and a missing process is not a
    // reason to call the database cleanup itself a failure.
    await _probe.run('killall', ['NotificationCenter']);

    return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.applied);
  }

  Future<String?> _resolveDb() async {
    final groupContainer =
        '$home/Library/Group Containers/group.com.apple.usernoted/db2/db';
    if (FileSystemEntity.typeSync(groupContainer, followLinks: false) ==
        FileSystemEntityType.file) {
      return groupContainer;
    }

    final darwinDir = await _probe.run('getconf', ['DARWIN_USER_DIR']);
    final base = darwinDir.stdout?.trim();
    if (!darwinDir.isSuccess || base == null || base.isEmpty) return null;

    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final legacyPath = '$trimmed/com.apple.notificationcenter/db2/db';
    if (FileSystemEntity.typeSync(legacyPath, followLinks: false) ==
        FileSystemEntityType.file) {
      return legacyPath;
    }
    return null;
  }
}
