import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/dns_flush_tracker.dart';
import 'package:hoopix/features/optimize/data/datasources/system_maintenance_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_privileged_command.dart';
import '../../../support/fake_process_runner.dart';

void main() {
  test('action id matches the catalog', () async {
    final result = await SystemMaintenanceTask(
      privilegedCommand: FakePrivilegedCommand({'flush_dns': null}),
      probe: FakeProcessRunner({
        'mdutil -s /': ProcessResult.success('Indexing enabled.'),
      }),
    ).run();

    expect(result.task.action, 'system_maintenance');
  });

  test('applies the DNS flush and sets the shared tracker', () async {
    final tracker = DnsFlushTracker();
    final privileged = FakePrivilegedCommand({'flush_dns': null});

    final result = await SystemMaintenanceTask(
      privilegedCommand: privileged,
      dnsFlushTracker: tracker,
      probe: FakeProcessRunner({
        'mdutil -s /': ProcessResult.success('Indexing enabled.'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(tracker.flushed, isTrue);
    expect(privileged.calls, ['flush_dns']);
  });

  test(
    'reports failed and leaves the tracker unset when elevation fails',
    () async {
      final tracker = DnsFlushTracker();

      final result = await SystemMaintenanceTask(
        privilegedCommand: FakePrivilegedCommand({'flush_dns': 'declined'}),
        dnsFlushTracker: tracker,
        probe: FakeProcessRunner({
          'mdutil -s /': ProcessResult.success('Indexing enabled.'),
        }),
      ).run();

      expect(result.outcome, OptimizeOutcome.failed);
      expect(tracker.flushed, isFalse);
    },
  );

  test(
    'a Spotlight probe failure adds to the failed count alongside a working flush',
    () async {
      final result = await SystemMaintenanceTask(
        privilegedCommand: FakePrivilegedCommand({'flush_dns': null}),
        probe: FakeProcessRunner({
          'mdutil -s /': ProcessResult.failure(
            ProcessFailure.timedOut('mdutil', const Duration(seconds: 5)),
          ),
        }),
      ).run();

      // applied=1 (dns) and failed=1 (spotlight) — failed wins.
      expect(result.outcome, OptimizeOutcome.failed);
    },
  );

  test('Indexing disabled is just a message, not a failure', () async {
    final result = await SystemMaintenanceTask(
      privilegedCommand: FakePrivilegedCommand({'flush_dns': null}),
      probe: FakeProcessRunner({
        'mdutil -s /': ProcessResult.success('Indexing disabled.'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });
}
