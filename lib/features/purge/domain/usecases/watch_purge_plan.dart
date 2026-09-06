import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_repository.dart';

class WatchPurgePlan {
  const WatchPurgePlan(this._repository);

  final PurgeRepository _repository;

  Stream<PurgePlan> call() => _repository.watchPlan();
}
