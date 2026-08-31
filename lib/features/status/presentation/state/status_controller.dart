import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hoopix/features/status/domain/entities/system_snapshot.dart';
import 'package:hoopix/features/status/domain/usecases/watch_system_status.dart';

/// Drives the Status screen from the [WatchSystemStatus] use case. Pure
/// presentation state — no process/CLI knowledge lives here.
class StatusController extends ChangeNotifier {
  StatusController(this._watchSystemStatus);

  final WatchSystemStatus _watchSystemStatus;
  StreamSubscription<SystemSnapshot>? _subscription;

  SystemSnapshot? snapshot;
  Object? error;

  void start({Duration interval = const Duration(seconds: 2)}) {
    _subscription?.cancel();
    _subscription = _watchSystemStatus(interval: interval).listen(
      (value) {
        snapshot = value;
        error = null;
        notifyListeners();
      },
      onError: (Object err) {
        error = err;
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
