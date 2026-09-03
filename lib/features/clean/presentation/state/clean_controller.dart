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

  /// Paths the user has unchecked. A set of exclusions, not inclusions, so
  /// a candidate the funnel hasn't seen yet (a size arriving later in the
  /// same scan, or a fresh scan after cleaning) starts selected without
  /// this needing to know about it in advance.
  final Set<String> _deselectedPaths = {};

  bool isSelected(String path) => !_deselectedPaths.contains(path);

  void toggle(String path) {
    if (!_deselectedPaths.add(path)) _deselectedPaths.remove(path);
    notifyListeners();
  }

  /// Selects or clears every eligible candidate in [section] at once, for
  /// the section header's own checkbox.
  void setSectionSelected(String section, bool selected) {
    final paths = [
      for (final candidate
          in plan?.bySection[section] ?? const <CleanCandidate>[])
        candidate.path,
    ];
    if (selected) {
      _deselectedPaths.removeAll(paths);
    } else {
      _deselectedPaths.addAll(paths);
    }
    notifyListeners();
  }

  /// Selects or clears every eligible candidate across the whole plan, for
  /// the screen's own master checkbox.
  void setAllSelected(bool selected) {
    if (selected) {
      _deselectedPaths.clear();
    } else {
      _deselectedPaths.addAll([
        for (final candidate in plan?.eligible ?? const []) candidate.path,
      ]);
    }
    notifyListeners();
  }

  /// The eligible candidates the user has left checked — what [approve]
  /// actually acts on, and what the header/dialog show instead of the
  /// plan's own full eligible count.
  List<CleanCandidate> get selectedEligible => [
    for (final candidate in plan?.eligible ?? const [])
      if (isSelected(candidate.path)) candidate,
  ];

  int get selectedReclaimableBytes =>
      selectedEligible.fold(0, (total, c) => total + (c.sizeBytes ?? 0));

  int get selectedIrreversibleCount =>
      selectedEligible.where((c) => !c.isRecoverable).length;

  void start() {
    _subscription?.cancel();
    plan = null;
    error = null;
    isScanning = true;
    // A fresh scan starts everyone selected; stale exclusions from a plan
    // that no longer exists have no meaning to carry forward.
    _deselectedPaths.clear();
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

  /// Whether there is anything checked to approve yet. Guards the button
  /// rather than letting an empty approval look like it did something.
  bool get canApprove =>
      !isRemoving && !isScanning && selectedEligible.isNotEmpty;

  /// Moves everything the user left checked to the Trash, then re-scans so
  /// the screen reflects the disk rather than what it remembered.
  ///
  /// Returns the paths that did not go, mapped to why.
  Future<Map<String, String>> approve() async {
    final approved = selectedEligible;
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
