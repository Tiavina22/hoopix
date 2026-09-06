import 'package:hoopix/core/platform/privileged_command.dart';
import 'package:hoopix/features/optimize/data/datasources/dns_flush_tracker.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_network_optimization` (`lib/optimize/tasks.sh`): the same DNS
/// flush [SystemMaintenanceTask] runs, kept as its own catalog entry
/// because Mole registers it separately too. [DnsFlushTracker] is what
/// keeps the two from flushing twice in the same run — this task reports
/// `unchanged` once the tracker shows a flush already happened, mirroring
/// Mole's own `MOLE_DNS_FLUSHED` check.
class NetworkOptimizationTask implements OptimizeTaskRunner {
  NetworkOptimizationTask({
    PrivilegedCommand? privilegedCommand,
    DnsFlushTracker? dnsFlushTracker,
  }) : _privilegedCommand = privilegedCommand ?? const PrivilegedCommand(),
       _dnsFlushTracker = dnsFlushTracker ?? DnsFlushTracker();

  final PrivilegedCommand _privilegedCommand;
  final DnsFlushTracker _dnsFlushTracker;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'network_optimization',
    name: 'Network Cache Refresh',
    description: 'Optimize DNS cache & restart mDNSResponder',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    if (_dnsFlushTracker.flushed) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final failure = await _privilegedCommand.run('flush_dns');
    if (failure == null) _dnsFlushTracker.flushed = true;

    return OptimizeTaskResult(
      task: task,
      outcome: failure == null
          ? OptimizeOutcome.applied
          : OptimizeOutcome.failed,
    );
  }
}
