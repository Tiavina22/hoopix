import 'dart:io';

import 'package:hoopix/core/platform/privileged_command.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_disk_permissions_repair` / `needs_permissions_repair`
/// (`lib/optimize/tasks.sh`): `diskutil resetUserPermissions` resets a
/// whole volume's worth of ACL/POSIX permissions against its own default
/// set, so this only ever runs once [_needsRepair] finds real evidence
/// something is actually wrong — the home directory owned by someone else,
/// or the home/Library/Preferences directories themselves not writable —
/// never as a routine pass.
class DiskPermissionsRepairTask implements OptimizeTaskRunner {
  DiskPermissionsRepairTask({
    required this.home,
    PrivilegedCommand? privilegedCommand,
    ProcessRunner? probe,
  }) : _privilegedCommand = privilegedCommand ?? const PrivilegedCommand(),
       _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5));

  final String home;
  final PrivilegedCommand _privilegedCommand;
  final ProcessRunner _probe;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'disk_permissions_repair',
    name: 'Permission Repair',
    description: 'Fix user directory permission issues',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    if (!await _needsRepair()) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final uid = await _currentUid();
    if (uid == null) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
    }

    final failure = await _privilegedCommand.run(
      'reset_user_permissions',
      arguments: {'uid': uid},
    );
    return OptimizeTaskResult(
      task: task,
      outcome: failure == null
          ? OptimizeOutcome.applied
          : OptimizeOutcome.failed,
    );
  }

  Future<bool> _needsRepair() async {
    final owner = await _probe.run('stat', ['-f', '%Su', home]);
    final ownerName = owner.stdout?.trim();
    final currentUser = Platform.environment['USER'];
    if (owner.isSuccess &&
        ownerName != null &&
        ownerName.isNotEmpty &&
        currentUser != null &&
        ownerName != currentUser) {
      return true;
    }

    for (final path in [home, '$home/Library', '$home/Library/Preferences']) {
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        continue;
      }
      final writable = await _probe.run('test', ['-w', path]);
      if (!writable.isSuccess) return true;
    }
    return false;
  }

  Future<String?> _currentUid() async {
    final result = await _probe.run('id', ['-u']);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }
}
