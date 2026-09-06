import 'package:hoopix/core/platform/privileged_command.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

enum _VpnState { active, notActive, unknown }

/// Ports `opt_network_stack_optimize` (`lib/optimize/tasks.sh`): flushes
/// the routing table and ARP cache, but only when a quick health probe
/// shows something is actually wrong, and never while a VPN looks active —
/// flushing routes can disrupt a tunnel's own explicit routes, and
/// `has_active_vpn_interface`'s own comments record a prior false-positive
/// history (issue #959) this mirrors exactly: `scutil --nc list` for a
/// system-managed VPN, then whether the default route's own interface is
/// `utun*` for a full-tunnel third-party one. Split-tunnel VPNs that do not
/// own the default route go undetected here the same way they do in Mole.
class NetworkStackOptimizeTask implements OptimizeTaskRunner {
  NetworkStackOptimizeTask({
    PrivilegedCommand? privilegedCommand,
    ProcessRunner? probe,
  }) : _privilegedCommand = privilegedCommand ?? const PrivilegedCommand(),
       _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5));

  final PrivilegedCommand _privilegedCommand;
  final ProcessRunner _probe;

  static final _connectedVpn = RegExp(r'^\* \(Connected\)', multiLine: true);
  static final _interfaceLine = RegExp(
    r'^\s*interface:\s*(\S+)',
    multiLine: true,
  );
  static final _utunInterface = RegExp(r'^utun[0-9]+$');

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'network_stack_optimize',
    name: 'Network Stack Refresh',
    description: 'Flush routing table and ARP cache to resolve network issues',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final vpn = await _vpnState();
    if (vpn == _VpnState.active) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.skipped);
    }
    if (vpn == _VpnState.unknown) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
    }

    final routeHealthy = (await _probe.run('route', [
      '-n',
      'get',
      'default',
    ])).isSuccess;
    final dnsHealthy = (await _probe.run('dscacheutil', [
      '-q',
      'host',
      '-a',
      'name',
      'example.com',
    ])).isSuccess;
    if (routeHealthy && dnsHealthy) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final routeFailure = await _privilegedCommand.run('flush_route');
    final arpFailure = await _privilegedCommand.run('flush_arp');

    var applied = 0;
    var failed = 0;
    routeFailure == null ? applied++ : failed++;
    arpFailure == null ? applied++ : failed++;

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: applied, failed: failed),
    );
  }

  Future<_VpnState> _vpnState() async {
    final scutil = await _probe.run('scutil', ['--nc', 'list']);
    if (!scutil.isSuccess) return _VpnState.unknown;
    if (_connectedVpn.hasMatch(scutil.stdout ?? '')) return _VpnState.active;

    final route = await _probe.run('route', ['-n', 'get', 'default']);
    if (!route.isSuccess) return _VpnState.unknown;
    final iface = _interfaceLine.firstMatch(route.stdout ?? '')?.group(1);
    if (iface != null && _utunInterface.hasMatch(iface)) {
      return _VpnState.active;
    }
    return _VpnState.notActive;
  }
}
