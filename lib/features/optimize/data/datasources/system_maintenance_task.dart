import 'package:hoopix/core/platform/privileged_command.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/dns_flush_tracker.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_system_maintenance` (`lib/optimize/tasks.sh`): flushes the OS
/// DNS resolver cache and restarts `mDNSResponder` — both need
/// administrator privileges — then reads Spotlight's own indexing status
/// (a plain, unprivileged `mdutil -s /`) purely to surface it; that read
/// never changes the outcome except when it fails outright.
///
/// Shares [DnsFlushTracker] with [NetworkOptimizationTask]: this task
/// always runs first in the catalog, the same order Mole's own registers
/// them in, so it is the one that sets the flag rather than checks it.
///
/// Unlike Mole's CLI, there is no upfront single sudo session to test
/// before attempting the flush — each privileged call is its own
/// elevation attempt, so a declined administrator prompt here surfaces as
/// `failed` rather than Mole's separate `skipped` state.
class SystemMaintenanceTask implements OptimizeTaskRunner {
  SystemMaintenanceTask({
    PrivilegedCommand? privilegedCommand,
    ProcessRunner? probe,
    DnsFlushTracker? dnsFlushTracker,
  }) : _privilegedCommand = privilegedCommand ?? const PrivilegedCommand(),
       _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _dnsFlushTracker = dnsFlushTracker ?? DnsFlushTracker();

  final PrivilegedCommand _privilegedCommand;
  final ProcessRunner _probe;
  final DnsFlushTracker _dnsFlushTracker;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'system_maintenance',
    name: 'DNS & Spotlight Check',
    description: 'Refresh DNS cache & verify Spotlight status',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final failure = await _privilegedCommand.run('flush_dns');
    final dnsFlushed = failure == null;
    if (dnsFlushed) _dnsFlushTracker.flushed = true;

    var spotlightFailed = 0;
    final status = await _probe.run('mdutil', ['-s', '/']);
    if (!status.isSuccess) spotlightFailed = 1;

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(
        applied: dnsFlushed ? 1 : 0,
        failed: spotlightFailed + (dnsFlushed ? 0 : 1),
      ),
    );
  }
}
