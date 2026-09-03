import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_shared_file_list_repair` (`lib/optimize/tasks.sh`): Finder's
/// favorites and recent-item lists live as `.sfl2`/`.sfl3` plists under
/// `~/Library/Application Support/com.apple.sharedfilelist`; a corrupted
/// one — caught by `plutil -lint` failing — makes Finder's sidebar or
/// recent-items menu misbehave until it's removed and rebuilt.
///
/// `ApplicationRecentDocuments` lists are excluded on purpose: that is a
/// per-app recent-documents history, real user data rather than a cache,
/// so it stays even if this scan reaches it.
class SharedFileListRepairTask implements OptimizeTaskRunner {
  SharedFileListRepairTask({
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
    action: 'shared_file_list_repair',
    name: 'Shared File Lists',
    description: 'Repair corrupted Finder favorites and recent documents',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final root = _directory(
      '$home/Library/Application Support/com.apple.sharedfilelist',
    );

    final List<FileSystemEntity> entries;
    try {
      entries = root.listSync(recursive: true, followLinks: false);
    } on FileSystemException {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    var repaired = 0;
    var failed = 0;

    for (final entity in entries) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.sfl2') && !lower.endsWith('.sfl3')) continue;
      if (entity.path.contains('ApplicationRecentDocuments')) continue;

      final lint = await _probe.run('plutil', ['-lint', entity.path]);
      if (lint.isSuccess) continue; // valid plist, nothing to repair

      try {
        await entity.delete();
        repaired++;
      } on FileSystemException {
        failed++;
      }
    }

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: repaired, failed: failed),
    );
  }
}
