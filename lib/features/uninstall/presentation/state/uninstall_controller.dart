import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/usecases/watch_uninstall_inventory.dart';

/// Drives the read-only Uninstall screen: no selection, no approve/delete —
/// this only ever reflects [WatchUninstallInventory]'s own stream, the same
/// progressive-sizing shape Clean and Purge use.
class UninstallController extends ChangeNotifier {
  UninstallController(this._watchUninstallInventory);

  final WatchUninstallInventory _watchUninstallInventory;

  StreamSubscription<List<InstalledApp>>? _subscription;

  List<InstalledApp>? apps;
  Object? error;
  bool isScanning = false;

  void start() {
    _subscription?.cancel();
    apps = null;
    error = null;
    isScanning = true;
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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
