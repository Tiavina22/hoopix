import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/optimize/data/datasources/dns_flush_tracker.dart';
import 'package:hoopix/features/optimize/data/datasources/network_optimization_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_privileged_command.dart';

void main() {
  test('action id matches the catalog', () async {
    final result = await NetworkOptimizationTask(
      privilegedCommand: FakePrivilegedCommand({'flush_dns': null}),
    ).run();

    expect(result.task.action, 'network_optimization');
  });

  test('unchanged when the tracker already shows a flush this run', () async {
    final tracker = DnsFlushTracker()..flushed = true;
    final privileged = FakePrivilegedCommand({'flush_dns': null});

    final result = await NetworkOptimizationTask(
      privilegedCommand: privileged,
      dnsFlushTracker: tracker,
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(privileged.calls, isEmpty);
  });

  test(
    'flushes DNS itself and sets the tracker when nothing flushed yet',
    () async {
      final tracker = DnsFlushTracker();

      final result = await NetworkOptimizationTask(
        privilegedCommand: FakePrivilegedCommand({'flush_dns': null}),
        dnsFlushTracker: tracker,
      ).run();

      expect(result.outcome, OptimizeOutcome.applied);
      expect(tracker.flushed, isTrue);
    },
  );

  test('reports failed when elevation is declined', () async {
    final result = await NetworkOptimizationTask(
      privilegedCommand: FakePrivilegedCommand({'flush_dns': 'declined'}),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
