import 'package:flutter/foundation.dart';
import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';
import 'package:hoopix/features/history/domain/usecases/fetch_operation_history.dart';

/// Drives the History screen. A one-shot fetch rather than a stream: this
/// is a record of the past, not a live feed, so nothing updates on its own
/// while the screen is open — [refresh] is how the user asks to see what
/// changed since.
class HistoryController extends ChangeNotifier {
  HistoryController(this._fetchOperationHistory);

  final FetchOperationHistory _fetchOperationHistory;

  List<OperationHistoryEntry>? entries;
  Object? error;
  bool isLoading = false;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      entries = await _fetchOperationHistory();
    } on Object catch (err) {
      error = err;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();
}
