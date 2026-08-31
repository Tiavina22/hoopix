import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';

class GetLocalSnapshotCount {
  const GetLocalSnapshotCount(this._repository);

  final AnalyzeRepository _repository;

  Future<int?> call() => _repository.localSnapshotCount();
}
