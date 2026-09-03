import 'package:flutter/foundation.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/optimize/domain/usecases/run_optimize.dart';

/// Drives the Optimize screen. Unlike Clean, there is no plan to approve
/// first — every task in the catalog is Mole's own `SAFE_VALUES=true`, so
/// showing the catalog before running is the whole "explain before it
/// happens" step; running is one action over the whole list, not a
/// per-item selection.
class OptimizeController extends ChangeNotifier {
  OptimizeController(this._runOptimize);

  final RunOptimize _runOptimize;

  List<OptimizeTask> get catalog => _runOptimize.catalog;

  /// Results so far, keyed by [OptimizeTask.action]. A task absent here
  /// has not finished yet (or a run has not started).
  final Map<String, OptimizeTaskResult> results = {};

  bool isRunning = false;
  Object? error;

  Future<void> run() async {
    if (isRunning) return;

    isRunning = true;
    results.clear();
    error = null;
    notifyListeners();

    try {
      await for (final result in _runOptimize()) {
        results[result.task.action] = result;
        notifyListeners();
      }
    } on Object catch (err) {
      error = err;
    }

    isRunning = false;
    notifyListeners();
  }
}
