import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

/// One entry from Mole's optimize catalog (`lib/optimize/catalog.sh`):
/// what a maintenance task is called and does, before it runs. [action] is
/// the catalog's own stable id (`prevent_network_dsstore`, ...), kept as
/// the key results are matched back to their task by.
class OptimizeTask {
  const OptimizeTask({
    required this.action,
    required this.name,
    required this.description,
  });

  final String action;
  final String name;
  final String description;
}

/// What happened when [task] ran.
class OptimizeTaskResult {
  const OptimizeTaskResult({
    required this.task,
    required this.outcome,
    this.detail,
  });

  final OptimizeTask task;
  final OptimizeOutcome outcome;

  /// A short human-readable reason, shown alongside [outcome] when it is
  /// not simply "everything about this ran the way you'd expect" — why it
  /// was skipped, what needs attention, or what failed.
  final String? detail;
}
