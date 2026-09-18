import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_log_entry.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

OptimizeTaskResult _result(OptimizeOutcome outcome, {String? detail}) =>
    OptimizeTaskResult(
      task: const OptimizeTask(action: 'a', name: 'A', description: 'd'),
      outcome: outcome,
      detail: detail,
    );

void main() {
  test('applied, failed and skipped are recorded, keeping the detail', () {
    final applied = optimizeLogEntryFor(_result(OptimizeOutcome.applied));
    final failed = optimizeLogEntryFor(
      _result(OptimizeOutcome.failed, detail: 'boom'),
    );
    final skipped = optimizeLogEntryFor(
      _result(OptimizeOutcome.skipped, detail: 'why'),
    );

    expect(applied!.outcome, OperationOutcome.applied);
    expect(failed!.outcome, OperationOutcome.refused);
    expect(failed.detail, 'boom');
    expect(skipped!.outcome, OperationOutcome.skipped);
    expect(skipped.detail, 'why');
  });

  test('a task that did nothing has no entry', () {
    for (final outcome in [
      OptimizeOutcome.unchanged,
      OptimizeOutcome.unavailable,
      OptimizeOutcome.attention,
    ]) {
      expect(optimizeLogEntryFor(_result(outcome)), isNull, reason: '$outcome');
    }
  });

  test('exactly the outcomes that acted are recorded', () {
    // The switch is exhaustive, so a new OptimizeOutcome fails to compile
    // rather than being silently dropped; this pins today's split.
    final recorded = [
      for (final o in OptimizeOutcome.values)
        if (optimizeLogEntryFor(_result(o)) != null) o,
    ];

    expect(recorded, [
      OptimizeOutcome.applied,
      OptimizeOutcome.skipped,
      OptimizeOutcome.failed,
    ]);
  });
}
