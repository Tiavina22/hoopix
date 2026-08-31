import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';

class FindLargeFiles {
  const FindLargeFiles(this._repository);

  final AnalyzeRepository _repository;

  Future<List<AnalyzeEntry>> call(String root) =>
      _repository.findLargeFiles(root);
}
