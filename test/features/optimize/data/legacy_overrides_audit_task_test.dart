import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/legacy_overrides_audit_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notSet() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('defaults', 1, ''));

void main() {
  test('action id matches the catalog', () async {
    final result = await LegacyOverridesAuditTask(
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'legacy_overrides_audit');
  });

  test('unchanged when nothing is overridden', () async {
    final result = await LegacyOverridesAuditTask(
      probe: FakeProcessRunner({
        'defaults read -g NSAppSleepDisabled': _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify': _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-locked':
            _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-remote':
            _notSet(),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('deletes a truthy override and reports applied', () async {
    final result = await LegacyOverridesAuditTask(
      probe: FakeProcessRunner({
        'defaults read -g NSAppSleepDisabled': ProcessResult.success('1\n'),
        'defaults delete -g NSAppSleepDisabled': ProcessResult.success(''),
        'defaults read com.apple.frameworks.diskimages skip-verify': _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-locked':
            _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-remote':
            _notSet(),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('a falsy value is left alone, not deleted', () async {
    final result = await LegacyOverridesAuditTask(
      probe: FakeProcessRunner({
        'defaults read -g NSAppSleepDisabled': ProcessResult.success('0\n'),
        'defaults read com.apple.frameworks.diskimages skip-verify': _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-locked':
            _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-remote':
            _notSet(),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('reports failed when the delete does not stick', () async {
    final result = await LegacyOverridesAuditTask(
      probe: FakeProcessRunner({
        'defaults read -g NSAppSleepDisabled': ProcessResult.success('1\n'),
        'defaults delete -g NSAppSleepDisabled': ProcessResult.failure(
          ProcessFailure.nonZeroExit('defaults', 1, 'denied'),
        ),
        'defaults read com.apple.frameworks.diskimages skip-verify': _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-locked':
            _notSet(),
        'defaults read com.apple.frameworks.diskimages skip-verify-remote':
            _notSet(),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
