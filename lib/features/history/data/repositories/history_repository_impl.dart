import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/features/history/data/datasources/operation_log_reader.dart';
import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';
import 'package:hoopix/features/history/domain/repositories/history_repository.dart';

/// [OperationOutcome] values [OperationLog] can write, keyed by the name
/// [OperationLog.record] serializes them as ([OperationOutcome.name]).
final _outcomesByName = {
  for (final outcome in OperationOutcome.values) outcome.name: outcome,
};

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl({required this.home, OperationLogReader? reader})
    : _reader = reader ?? const OperationLogReader();

  final String home;
  final OperationLogReader _reader;

  String get _logPath => OperationLog(home: home).path;

  @override
  Future<List<OperationHistoryEntry>> recentOperations({
    int limit = 200,
  }) async {
    final raw = await _reader.readRecent(_logPath, limit: limit);
    return raw.map(_toEntry).nonNulls.toList();
  }

  OperationHistoryEntry? _toEntry(RawOperationLogEntry raw) {
    final outcome = _outcomesByName[raw.outcome];
    if (outcome == null) return null;
    final at = DateTime.tryParse(raw.at);
    if (at == null) return null;

    return OperationHistoryEntry(
      at: at,
      command: raw.command,
      outcome: outcome,
      path: raw.path,
      detail: raw.detail,
      sizeBytes: raw.sizeBytes,
    );
  }
}
