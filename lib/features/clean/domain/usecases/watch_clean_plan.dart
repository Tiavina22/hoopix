import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/repositories/clean_repository.dart';

class WatchCleanPlan {
  const WatchCleanPlan(this._repository);

  final CleanRepository _repository;

  Stream<CleanPlan> call() => _repository.watchPlan();
}
