import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';

/// Read-only access to what hoopix has already recorded doing. Nothing here
/// deletes, retries, or otherwise acts on the log — history is a record of
/// the past, not another delete surface.
abstract class HistoryRepository {
  /// The most recent operations, newest first, up to [limit]. A line the
  /// log holds but this cannot make sense of — a future command's own
  /// shape, a line torn by a crash mid-write — is silently left out rather
  /// than surfaced as an error: a shorter history is a far better failure
  /// mode than a screen that cannot open.
  Future<List<OperationHistoryEntry>> recentOperations({int limit = 200});
}
