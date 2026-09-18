import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';
import 'package:hoopix/features/history/domain/repositories/history_repository.dart';

class FetchOperationHistory {
  const FetchOperationHistory(this._repository);

  final HistoryRepository _repository;

  Future<List<OperationHistoryEntry>> call({int limit = 200}) =>
      _repository.recentOperations(limit: limit);
}
