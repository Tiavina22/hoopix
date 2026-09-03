import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

abstract class OptimizeRepository {
  /// The maintenance tasks a run performs, in the order they run — shown
  /// before anything runs, so a run is explained rather than a surprise.
  List<OptimizeTask> get catalog;

  /// Runs every task in [catalog], in order, emitting each result as it
  /// finishes. One task's result never waits on the others: the screen
  /// updates task by task the same way `mo optimize`'s own terminal output
  /// announces one action at a time.
  Stream<OptimizeTaskResult> runAll();
}
