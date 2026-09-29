import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_launch_agents_cleanup` (`lib/optimize/tasks.sh`, Mole #1617):
/// reports each user LaunchAgent whose absolute program is missing and
/// leaves it alone. A missing executable does not prove the service is
/// unwanted — it may just have been moved — and the plist is the
/// configuration the user would otherwise have to rebuild by hand once the
/// program is back. No `launchctl unload` either, since that acts on the
/// label and can stop a live job loaded from another file.
///
/// Deliberately narrow about what counts as broken: a bare command name
/// (`node`, `python3`) resolves through `$PATH` at launch time, not at scan
/// time, and a path under `/Volumes/<disk>` that is not currently mounted
/// just means the drive is unplugged right now — neither is reported,
/// matching `launch_agent_volume_mounted`.
///
/// The action id stays `launch_agents_cleanup`, as in Mole, so the task
/// keeps its identity across the change.
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
    description: 'Report LaunchAgents whose binaries no longer exist',
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
      final missing = await _missingProgram(entity.path);
      if (missing == null) continue;
      final label = await _plistString(entity.path, 'Label');
      final name = (label == null || label.isEmpty)
          ? _basenameWithoutPlist(entity.path)
          : label;
      broken.add('$name: program missing at ${_tildePath(missing)}');
    }

    if (broken.isEmpty) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    broken.sort();
    return OptimizeTaskResult(
      task: task,
      outcome: OptimizeOutcome.attention,
      detail:
          '${broken.join('\n')}\n'
          'Left in ~/Library/LaunchAgents.',
    );
  }

  /// The agent's absolute program path when it is genuinely missing, or
  /// null when the agent is not broken by this task's narrow definition.
  Future<String?> _missingProgram(String plistPath) async {
    var binary = await _plistString(plistPath, 'ProgramArguments:0');
    if (binary == null || binary.isEmpty) {
      binary = await _plistString(plistPath, 'Program');
    }
    if (binary == null || binary.isEmpty || !binary.startsWith('/')) {
      return null;
    }
    if (FileSystemEntity.typeSync(binary, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return null;
    }
    return _volumeMounted(binary) ? binary : null;
  }

  String _basenameWithoutPlist(String path) {
    final name = path.split('/').last;
    return name.toLowerCase().endsWith('.plist')
        ? name.substring(0, name.length - '.plist'.length)
        : name;
  }

  String _tildePath(String path) => path == home || path.startsWith('$home/')
      ? '~${path.substring(home.length)}'
      : path;

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
