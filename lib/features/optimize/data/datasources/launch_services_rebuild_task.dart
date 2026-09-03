import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_launch_services_rebuild` (`lib/optimize/tasks.sh`): rebuilds
/// the LaunchServices database — what maps a file type to "Open With",
/// keeps duplicate or stale app entries out of that menu — by asking
/// `lsregister` itself to garbage-collect and then force a full rescan.
/// Runs entirely in the current user's own context: no `sudo` anywhere in
/// this task, since a user-domain rescan is exactly what `lsregister`
/// grants without elevation, unlike the two other domains it also tries.
///
/// `-gc`'s result is ignored, matching Mole: it is a best-effort cleanup
/// step ahead of the rescan that actually matters. The rescan itself tries
/// `local`, `user`, and `system` domains first; if that combination fails
/// (a non-admin account commonly cannot write the system domain), it
/// retries with `system` dropped rather than treating the whole task as
/// failed.
class LaunchServicesRebuildTask implements OptimizeTaskRunner {
  LaunchServicesRebuildTask({ProcessRunner? probe, this.candidatePaths})
    : _probe = probe ?? const ProcessRunner(timeout: Duration(minutes: 2));

  final ProcessRunner _probe;

  /// Overridable for tests; production always tries both known framework
  /// locations for `lsregister`, in order.
  final List<String>? candidatePaths;

  static const _defaultCandidatePaths = [
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/'
        'LaunchServices.framework/Support/lsregister',
    '/System/Library/CoreServices/Frameworks/LaunchServices.framework/'
        'Support/lsregister',
  ];

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'launch_services_rebuild',
    name: 'LaunchServices Repair',
    description: 'Repair "Open with" menu & file associations',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final lsregister = _resolveLsregister();
    if (lsregister == null) {
      return OptimizeTaskResult(
        task: task,
        outcome: OptimizeOutcome.unavailable,
      );
    }

    await _probe.run(lsregister, ['-gc']);

    final fullRescan = await _probe.run(lsregister, [
      '-r',
      '-f',
      '-domain',
      'local',
      '-domain',
      'user',
      '-domain',
      'system',
    ]);
    if (fullRescan.isSuccess) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.applied);
    }

    final withoutSystemDomain = await _probe.run(lsregister, [
      '-r',
      '-f',
      '-domain',
      'local',
      '-domain',
      'user',
    ]);
    return OptimizeTaskResult(
      task: task,
      outcome: withoutSystemDomain.isSuccess
          ? OptimizeOutcome.applied
          : OptimizeOutcome.failed,
    );
  }

  String? _resolveLsregister() {
    for (final path in candidatePaths ?? _defaultCandidatePaths) {
      if (_isExecutableFile(path)) return path;
    }
    return null;
  }

  bool _isExecutableFile(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    try {
      return File(path).statSync().mode & 0x49 != 0; // any execute bit
    } on FileSystemException {
      return false;
    }
  }
}
