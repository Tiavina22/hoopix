import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/usecases/approve_uninstall.dart';
import 'package:hoopix/features/uninstall/domain/usecases/watch_uninstall_inventory.dart';

/// Drives the Uninstall screen: an inventory to review, and the selection
/// and removal of what the user leaves checked, the same shape
/// [WatchUninstallInventory]/[ApproveUninstall] and Clean's own controller
/// already share.
class UninstallController extends ChangeNotifier {
  UninstallController(this._watchUninstallInventory, this._approveUninstall);

  final WatchUninstallInventory _watchUninstallInventory;
  final ApproveUninstall _approveUninstall;

  StreamSubscription<List<InstalledApp>>? _subscription;

  List<InstalledApp>? apps;
  Object? error;
  bool isScanning = false;

  /// Paths the user has unchecked. A set of exclusions, not inclusions, so
  /// an app a fresh scan finds starts selected without this needing to
  /// know about it in advance.
  final Set<String> _deselectedPaths = {};

  bool isSelected(String path) => !_deselectedPaths.contains(path);

  void toggle(String path) {
    if (!_deselectedPaths.add(path)) _deselectedPaths.remove(path);
    notifyListeners();
  }

  /// Selects or clears every discovered app at once, for the screen's own
  /// master checkbox.
  void setAllSelected(bool selected) {
    if (selected) {
      _deselectedPaths.clear();
    } else {
      _deselectedPaths.addAll([for (final app in apps ?? const []) app.path]);
    }
    notifyListeners();
  }

  /// The apps the user has left checked — what [approve] actually acts on.
  List<InstalledApp> get selectedApps => [
    for (final app in apps ?? const [])
      if (isSelected(app.path)) app,
  ];

  int get selectedReclaimableBytes =>
      selectedApps.fold(0, (total, app) => total + (app.sizeBytes ?? 0));

  void start() {
    _subscription?.cancel();
    apps = null;
    error = null;
    isScanning = true;
    // A fresh scan starts everyone selected; stale exclusions from a scan
    // that no longer exists have no meaning to carry forward.
    _deselectedPaths.clear();
    notifyListeners();

    _subscription = _watchUninstallInventory().listen(
      (value) {
        apps = value;
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
      !isRemoving && !isScanning && selectedApps.isNotEmpty;

  /// Removes everything the user left checked — each app's bundle and its
  /// exact known leftovers — to the Trash, then re-scans so the screen
  /// reflects the disk rather than what it remembered.
  ///
  /// Returns the paths that did not go, mapped to why.
  Future<Map<String, String>> approve() async {
    final approved = selectedApps;
    if (approved.isEmpty) return const {};

    isRemoving = true;
    notifyListeners();

    final failures = await _approveUninstall(approved);

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
