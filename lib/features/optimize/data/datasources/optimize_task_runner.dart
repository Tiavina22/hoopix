import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// One maintenance task's own metadata and implementation. Each concrete
/// task in this directory is one `opt_*` handler from Mole's
/// `lib/optimize/tasks.sh`; [OptimizeRepositoryImpl] runs a fixed list of
/// these in catalog order, uniformly, without knowing what any one of them
/// actually does.
abstract class OptimizeTaskRunner {
  OptimizeTask get task;

  Future<OptimizeTaskResult> run();
}
