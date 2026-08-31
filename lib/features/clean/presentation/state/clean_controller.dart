import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/approve_clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/watch_clean_plan.dart';

/// Drives the Clean screen. The screen shows a plan and nothing else yet:
/// working out what could go is safe, and approving it is the step that
/// follows.
class CleanController extends ChangeNotifier {
  CleanController(this._watchCleanPlan, this._approveCleanPlan);

  final WatchCleanPlan _watchCleanPlan;
  final ApproveCleanPlan _approveCleanPlan;

  StreamSubscription<CleanPlan>? _subscription;

  CleanPlan? plan;
  Object? error;
  bool isScanning = false;

  void start() {
    _subscription?.cancel();
    plan = null;
    error = null;
    isScanning = true;
    notifyListeners();

    _subscription = _watchCleanPlan().listen(
      (value) {
        plan = value;
        error = null;
        notifyListeners();
      },
      onError: (Object err) {
        error = err;
        isScanning = false;
        notifyListeners();
      },
      onDone: () {
        isScanning = false;
        notifyListeners();
      },
    );
  }

  bool isRemoving = false;

  /// Whether there is anything to approve yet. Guards the button rather
  /// than letting an empty approval look like it did something.
  bool get canApprove =>
      !isRemoving && !isScanning && (plan?.eligible.isNotEmpty ?? false);

  /// Moves everything the plan proposes to the Trash, then re-scans so the
  /// screen reflects the disk rather than what it remembered.
  ///
  /// Returns the paths that did not go, mapped to why.
  Future<Map<String, String>> approve() async {
    final approved = plan?.eligible ?? const [];
    if (approved.isEmpty) return const {};

    isRemoving = true;
    notifyListeners();

    final failures = await _approveCleanPlan(approved);

    isRemoving = false;
    start();
    return failures;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
