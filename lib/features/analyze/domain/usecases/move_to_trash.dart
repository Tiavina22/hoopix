import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';

class MoveToTrash {
  const MoveToTrash(this._repository);

  final AnalyzeRepository _repository;

  Future<Map<String, String>> call(List<String> paths) =>
      _repository.moveToTrash(paths);
}
