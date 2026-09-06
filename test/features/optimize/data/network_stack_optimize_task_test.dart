import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/network_stack_optimize_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_privileged_command.dart';
import '../../../support/fake_process_runner.dart';

ProcessResult _healthyRoute() =>
    ProcessResult.success('   interface: en0\n   gateway: 10.0.0.1');
ProcessResult _healthyDns() => ProcessResult.success('example.com');
ProcessResult _noVpnList() => ProcessResult.success('* (Disconnected) foo');
ProcessResult _fail() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('route', 1, ''));

void main() {
  test('action id matches the catalog', () async {
    final result = await NetworkStackOptimizeTask(
      probe: FakeProcessRunner({
        'scutil --nc list': _noVpnList(),
        'route -n get default': _healthyRoute(),
        'dscacheutil -q host -a name example.com': _healthyDns(),
      }),
    ).run();

    expect(result.task.action, 'network_stack_optimize');
  });

  test('skipped when scutil reports a connected system VPN', () async {
    final result = await NetworkStackOptimizeTask(
      probe: FakeProcessRunner({
        'scutil --nc list': ProcessResult.success('* (Connected) MyVPN'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.skipped);
  });

  test('skipped when the default route is a utun interface', () async {
    final result = await NetworkStackOptimizeTask(
      probe: FakeProcessRunner({
        'scutil --nc list': _noVpnList(),
        'route -n get default': ProcessResult.success('   interface: utun4'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.skipped);
  });

  test('failed when VPN detection itself cannot be trusted', () async {
    final result = await NetworkStackOptimizeTask(
      probe: FakeProcessRunner({'scutil --nc list': _fail()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });

  test('unchanged when route and DNS are both already healthy', () async {
    final result = await NetworkStackOptimizeTask(
      probe: FakeProcessRunner({
        'scutil --nc list': _noVpnList(),
        'route -n get default': _healthyRoute(),
        'dscacheutil -q host -a name example.com': _healthyDns(),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test(
    'flushes route and ARP when DNS resolution is unhealthy, and reports applied',
    () async {
      final privileged = FakePrivilegedCommand({
        'flush_route': null,
        'flush_arp': null,
      });

      final result = await NetworkStackOptimizeTask(
        privilegedCommand: privileged,
        probe: FakeProcessRunner({
          'scutil --nc list': _noVpnList(),
          // Route stays healthy on both the VPN-detection call and the
          // health-probe call (FakeProcessRunner cannot distinguish the two
          // calls to the same command); DNS resolution is what is unhealthy
          // here, which is enough on its own to trigger the flush.
          'route -n get default': _healthyRoute(),
          'dscacheutil -q host -a name example.com': _fail(),
        }),
      ).run();

      expect(result.outcome, OptimizeOutcome.applied);
      expect(privileged.calls, ['flush_route', 'flush_arp']);
    },
  );

  test('reports failed when one flush is declined', () async {
    final result = await NetworkStackOptimizeTask(
      privilegedCommand: FakePrivilegedCommand({
        'flush_route': null,
        'flush_arp': 'declined',
      }),
      probe: FakeProcessRunner({
        'scutil --nc list': _noVpnList(),
        'route -n get default': _healthyRoute(),
        'dscacheutil -q host -a name example.com': _fail(),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
