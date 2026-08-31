import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';

class RevealInFinder {
  const RevealInFinder(this._repository);

  final AnalyzeRepository _repository;

  Future<bool> call(String path) => _repository.revealInFinder(path);
}
