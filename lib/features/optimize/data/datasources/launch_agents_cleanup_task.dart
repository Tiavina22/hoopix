import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_launch_agents_cleanup` (`lib/optimize/tasks.sh`): a user
/// LaunchAgent whose own binary is genuinely gone will never start
/// correctly again, so `launchctl` stops retrying it and its plist is
/// removed. Deliberately narrow about what counts as broken: a bare
/// command name (`node`, `python3`) resolves through `$PATH` at launch
/// time, not at scan time, and a path under `/Volumes/<disk>` that is not
/// currently mounted just means the drive is unplugged right now — neither
/// is treated as broken, matching `launch_agent_volume_mounted`.
///
/// User-domain agents unload and remove without any `sudo` — the same
/// reason [LaunchServicesRebuildTask]'s own rescan needs none for the
/// domains it can actually reach.
class LaunchAgentsCleanupTask implements OptimizeTaskRunner {
  LaunchAgentsCleanupTask({
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
    action: 'launch_agents_cleanup',
    name: 'Launch Agents Cleanup',
    description: 'Remove broken LaunchAgents whose binaries no longer exist',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final agentsDir = _directory('$home/Library/LaunchAgents');

    final List<FileSystemEntity> entries;
    try {
      entries = agentsDir.listSync(followLinks: false);
    } on FileSystemException {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final broken = <String>[];
    for (final entity in entries) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.plist')) continue;
      if (await _isBroken(entity.path)) broken.add(entity.path);
    }

    if (broken.isEmpty) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    var removed = 0;
    var failed = 0;
    for (final plist in broken) {
      // Best-effort: an agent that already isn't loaded, or an ordinary
      // unload failure, must not stop the plist itself from being removed.
      await _probe.run('launchctl', ['unload', plist]);
      try {
        await File(plist).delete();
        removed++;
      } on FileSystemException {
        failed++;
      }
    }

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: removed, failed: failed),
    );
  }

  Future<bool> _isBroken(String plistPath) async {
    var binary = await _plistString(plistPath, 'ProgramArguments:0');
    if (binary == null || binary.isEmpty) {
      binary = await _plistString(plistPath, 'Program');
    }
    if (binary == null || binary.isEmpty || !binary.startsWith('/')) {
      return false;
    }
    if (FileSystemEntity.typeSync(binary, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    return _volumeMounted(binary);
  }

  Future<String?> _plistString(String plistPath, String key) async {
    final result = await _probe.run('/usr/libexec/PlistBuddy', [
      '-c',
      'Print :$key',
      plistPath,
    ]);
    if (!result.isSuccess) return null;
    return result.stdout?.trim();
  }

  bool _volumeMounted(String path) {
    const prefix = '/Volumes/';
    if (!path.startsWith(prefix)) return true;
    final rest = path.substring(prefix.length);
    final volume = rest.split('/').first;
    if (volume.isEmpty) return false;
    return FileSystemEntity.typeSync('$prefix$volume', followLinks: false) ==
        FileSystemEntityType.directory;
  }
}
