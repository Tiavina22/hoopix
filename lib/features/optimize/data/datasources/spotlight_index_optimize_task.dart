import 'package:hoopix/core/platform/privileged_command.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_spotlight_index_optimize` (`lib/optimize/tasks.sh`): only
/// triggers Spotlight's own full reindex — a multi-hour background job —
/// once two timed `mdfind` probes, a second apart, both come back slow.
/// The speed check itself never runs on battery, so a slow reading is
/// never measured (and discarded) or, worse, used to justify a rebuild
/// that then drains it further.
class SpotlightIndexOptimizeTask implements OptimizeTaskRunner {
  SpotlightIndexOptimizeTask({
    PrivilegedCommand? privilegedCommand,
    ProcessRunner? probe,
    Duration? probeTimeout,
    Duration? betweenProbesDelay,
  }) : _privilegedCommand = privilegedCommand ?? const PrivilegedCommand(),
       _probe =
           probe ??
           ProcessRunner(timeout: probeTimeout ?? const Duration(seconds: 10)),
       _betweenProbesDelay = betweenProbesDelay ?? const Duration(seconds: 1);

  final PrivilegedCommand _privilegedCommand;
  final ProcessRunner _probe;

  /// The pause between the two speed probes, matching Mole's own `sleep
  /// 1` — overridable so tests do not need a real second per run.
  final Duration _betweenProbesDelay;

  static const _slowThreshold = Duration(seconds: 3);

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'spotlight_index_optimize',
    name: 'Spotlight Optimization',
    description: 'Rebuild index if search is slow (smart detection)',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final status = await _probe.run('mdutil', ['-s', '/']);
    if (!status.isSuccess) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
    }

    final output = (status.stdout ?? '').toLowerCase();
    if (output.contains('indexing disabled')) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.skipped);
    }
    if (!output.contains('indexing enabled') ||
        output.contains('indexing and searching disabled')) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    if (!await _isAcPower()) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.skipped);
    }

    var slowCount = 0;
    var probeFailed = 0;
    for (var attempt = 0; attempt < 2; attempt++) {
      final stopwatch = Stopwatch()..start();
      final probe = await _probe.run('mdfind', [
        "kMDItemFSName == 'Applications'",
      ]);
      stopwatch.stop();

      if (probe.failure?.kind == ProcessFailureKind.timedOut) {
        slowCount++;
      } else if (!probe.isSuccess) {
        probeFailed++;
      } else if (stopwatch.elapsed > _slowThreshold) {
        slowCount++;
      }

      if (attempt == 0) await Future<void>.delayed(_betweenProbesDelay);
    }

    if (probeFailed > 0) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
    }
    if (slowCount < 2) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final failure = await _privilegedCommand.run('rebuild_spotlight_index');
    return OptimizeTaskResult(
      task: task,
      outcome: failure == null
          ? OptimizeOutcome.applied
          : OptimizeOutcome.failed,
    );
  }

  Future<bool> _isAcPower() async {
    final result = await _probe.run('pmset', ['-g', 'batt']);
    return result.isSuccess && (result.stdout ?? '').contains('AC Power');
  }
}
