import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/optimize/domain/repositories/optimize_repository.dart';

class RunOptimize {
  const RunOptimize(this._repository);

  final OptimizeRepository _repository;

  List<OptimizeTask> get catalog => _repository.catalog;

  Stream<OptimizeTaskResult> call() => _repository.runAll();
}
