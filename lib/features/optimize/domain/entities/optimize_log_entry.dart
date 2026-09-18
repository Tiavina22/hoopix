import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// What a finished maintenance task puts on the operation log, or null when
/// it should leave no record.
///
/// The log is a record of what was done and what was decided against, so
/// only a task that changed something ([OptimizeOutcome.applied]), tried to
/// and did not complete ([OptimizeOutcome.failed]), or was held back on
/// purpose ([OptimizeOutcome.skipped]) is written down. A task that found
/// nothing to change, could not run on this Mac, or only raised a point for
/// the person to decide on did nothing, so there is nothing to audit.
///
/// A failure is recorded as [OperationOutcome.refused], the meaning that word
/// already carries for a Trash move that did not go through.
class OptimizeLogEntry {
  const OptimizeLogEntry({required this.outcome, this.detail});

  final OperationOutcome outcome;
  final String? detail;
}

OptimizeLogEntry? optimizeLogEntryFor(OptimizeTaskResult result) =>
    switch (result.outcome) {
      OptimizeOutcome.applied => OptimizeLogEntry(
        outcome: OperationOutcome.applied,
        detail: result.detail,
      ),
      OptimizeOutcome.failed => OptimizeLogEntry(
        outcome: OperationOutcome.refused,
        detail: result.detail,
      ),
      OptimizeOutcome.skipped => OptimizeLogEntry(
        outcome: OperationOutcome.skipped,
        detail: result.detail,
      ),
      OptimizeOutcome.unchanged ||
      OptimizeOutcome.unavailable ||
      OptimizeOutcome.attention => null,
    };
