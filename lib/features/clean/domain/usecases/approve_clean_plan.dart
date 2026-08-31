import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/repositories/clean_repository.dart';

class ApproveCleanPlan {
  const ApproveCleanPlan(this._repository);

  final CleanRepository _repository;

  Future<Map<String, String>> call(List<CleanCandidate> approved) =>
      _repository.approve(approved);
}
