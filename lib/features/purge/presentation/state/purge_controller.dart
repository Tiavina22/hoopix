import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
import 'package:hoopix/features/purge/domain/usecases/approve_purge_plan.dart';
import 'package:hoopix/features/purge/domain/usecases/watch_purge_plan.dart';

/// Drives the Purge screen. Selection defaults to exclusion, the same
/// shape Clean's own controller uses, so a candidate that arrives later in
/// the same scan — a size landing, a fresh scan after a run — starts
/// selected without this needing to know about it in advance. What starts
/// selected is narrower than Clean's, though: [PurgeCandidate.isDefaultSelected]
/// already excludes anything that looks recently touched or whose
/// staleness could not be confirmed, so the exclusion set only ever grows
/// from there as the user unchecks more.
class PurgeController extends ChangeNotifier {
  PurgeController(this._watchPurgePlan, this._approvePurgePlan);

  final WatchPurgePlan _watchPurgePlan;
  final ApprovePurgePlan _approvePurgePlan;

  StreamSubscription<PurgePlan>? _subscription;

  PurgePlan? plan;
  Object? error;
  bool isScanning = false;
  bool isRemoving = false;

  final Set<String> _deselectedPaths = {};

  bool isSelected(String path) => !_deselectedPaths.contains(path);

  void toggle(String path) {
    if (!_deselectedPaths.add(path)) _deselectedPaths.remove(path);
    notifyListeners();
  }

  void setAllSelected(bool selected) {
    if (selected) {
      _deselectedPaths.clear();
    } else {
      _deselectedPaths.addAll([
        for (final candidate in plan?.candidates ?? const []) candidate.path,
      ]);
    }
    notifyListeners();
  }

  List<PurgeCandidate> get selected => [
    for (final candidate in plan?.candidates ?? const [])
      if (isSelected(candidate.path)) candidate,
  ];

  int get selectedReclaimableBytes =>
      selected.fold(0, (total, c) => total + (c.sizeBytes ?? 0));

  bool get selectedHasCloudSynced => selected.any((c) => c.isCloudSynced);

  void start() {
    _subscription?.cancel();
    plan = null;
    error = null;
    isScanning = true;
    _deselectedPaths.clear();
    notifyListeners();

    var seededDefaults = false;

    _subscription = _watchPurgePlan().listen(
      (value) {
        plan = value;
        error = null;
        // Seed exclusions once, from the first plan that names every
        // candidate — later size-only updates must not re-seed and
        // silently re-select something the user already unchecked.
        if (!seededDefaults) {
          seededDefaults = true;
          _deselectedPaths.addAll([
            for (final candidate in value.candidates)
              if (!candidate.isDefaultSelected) candidate.path,
          ]);
        }
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

  bool get canApprove => !isRemoving && !isScanning && selected.isNotEmpty;

  /// Permanently removes everything the user left checked, then re-scans.
  /// Returns the paths that did not go, mapped to why.
  Future<Map<String, String>> approve() async {
    final approved = selected;
    if (approved.isEmpty) return const {};

    isRemoving = true;
    notifyListeners();

    final failures = await _approvePurgePlan(approved);

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
