import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_prevent_network_dsstore` (`lib/optimize/tasks.sh`): a Finder
/// preference toggle, not a deletion — nothing here can be undone by
/// mistake the way a file removal can, since flipping either key back is
/// itself just another `defaults write`.
class PreventNetworkDsStoreTask implements OptimizeTaskRunner {
  PreventNetworkDsStoreTask({ProcessRunner? probe})
    : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5));

  final ProcessRunner _probe;

  static const _domain = 'com.apple.desktopservices';
  static const _keys = ['DSDontWriteNetworkStores', 'DSDontWriteUSBStores'];

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'prevent_network_dsstore',
    name: 'Prevent Finder .DS_Store',
    description:
        'Stop Finder writing .DS_Store on network shares and USB drives',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    var applied = 0;
    var failed = 0;

    for (final key in _keys) {
      final current = await _probe.run('defaults', ['read', _domain, key]);
      if (current.isSuccess && current.stdout?.trim() == '1') continue;

      final write = await _probe.run('defaults', [
        'write',
        _domain,
        key,
        '-bool',
        'true',
      ]);
      if (write.isSuccess) {
        applied++;
      } else {
        failed++;
      }
    }

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: applied, failed: failed),
    );
  }
}
