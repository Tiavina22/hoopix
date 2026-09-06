import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_repository.dart';

class ApprovePurgePlan {
  const ApprovePurgePlan(this._repository);

  final PurgeRepository _repository;

  Future<Map<String, String>> call(List<PurgeCandidate> approved) =>
      _repository.approve(approved);
}
