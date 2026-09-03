/// The six states a maintenance task can end in — a direct port of
/// `MOLE_OPTIMIZE_OUTCOME_*` (`lib/optimize/outcomes.sh`). Kept as Mole's own
/// contract rather than a narrower "did it work" boolean, because a task
/// that found nothing to do and a task that could not run at all read very
/// differently to the person watching, even though neither changed anything.
enum OptimizeOutcome {
  /// A change completed (or would, in a preview).
  applied,

  /// Inspection completed and nothing needed to change.
  unchanged,

  /// Policy or run context intentionally prevented the task — no admin
  /// access, a precondition not met, the run's own scope excluding it.
  skipped,

  /// The host lacks what the task needs (a missing binary, an unresolvable
  /// database path).
  unavailable,

  /// Inspection found something only the person using the app can decide
  /// on; the task itself does not act on it.
  attention,

  /// An eligible operation was attempted and did not complete.
  failed,
}

/// [Mole's own `optimize_task_result_from_counts`](../../../../../../Mole/lib/optimize/outcomes.sh):
/// the common shape most tasks reduce their sub-steps to one outcome with.
/// `failed` wins over everything else — a task with any failed sub-step is
/// not a success just because other sub-steps went fine.
OptimizeOutcome optimizeOutcomeFromCounts({
  required int applied,
  required int failed,
  int skipped = 0,
}) {
  if (failed > 0) return OptimizeOutcome.failed;
  if (applied > 0) return OptimizeOutcome.applied;
  if (skipped > 0) return OptimizeOutcome.skipped;
  return OptimizeOutcome.unchanged;
}
