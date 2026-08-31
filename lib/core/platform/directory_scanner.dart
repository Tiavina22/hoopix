import 'dart:async';

import 'package:flutter/services.dart';

/// One step of a directory walk, as reported by the native scanner.
sealed class ScanEvent {
  const ScanEvent();
}

/// A child that exists. Files arrive with their final size; directories
/// arrive without one and are filled in later by a [ScanSize].
class ScanEntry extends ScanEvent {
  const ScanEntry({
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    required this.accessed,
  });

  final String path;
  final bool isDirectory;
  final int? sizeBytes;

  /// Last access time, which `du` cannot report — it backs the "unused
  /// since" hint on a row.
  final DateTime? accessed;
}

/// Every child has been listed; [pending] directories are still being sized.
class ScanListed extends ScanEvent {
  const ScanListed(this.pending);

  final int pending;
}

/// A directory's recursive total, hardlinks counted once for the whole scan.
class ScanSize extends ScanEvent {
  const ScanSize(this.path, this.sizeBytes);

  final String path;
  final int sizeBytes;
}

class ScanComplete extends ScanEvent {
  const ScanComplete({this.deduped = false});

  /// True when a hardlinked file was charged to only one of the links. Such
  /// a total depends on the order the tree was walked, so it must not be
  /// cached and replayed as if it were stable.
  final bool deduped;
}

/// The directory itself could not be read.
class ScanFailed extends ScanEvent {
  const ScanFailed(this.reason, this.errorCode);

  final String reason;

  /// The `errno` behind it: 1 (EPERM) and 13 (EACCES) mean "not allowed",
  /// anything else is an ordinary failure.
  final int errorCode;

  bool get isPermissionDenied => errorCode == 1 || errorCode == 13;
}

/// Walks directories natively — see `macos/Runner/DirectoryScanChannel.swift`.
///
/// The walk lives on the native side because a directory's true size needs
/// what Dart cannot see: allocated blocks, and `(dev, ino)` identity so a
/// hardlinked file is counted once across the whole scan rather than once
/// per folder it appears in.
class DirectoryScanner {
  DirectoryScanner({
    MethodChannel methods = const MethodChannel(_methodChannelName),
    EventChannel events = const EventChannel(_eventChannelName),
  }) : _methods = methods,
       _events = events;

  static const _methodChannelName = 'fit.hoopix/scan';
  static const _eventChannelName = 'fit.hoopix/scan_events';

  final MethodChannel _methods;
  final EventChannel _events;

  static int _nextId = 0;

  Stream<ScanEvent> scan(String path) {
    final id = _nextId++;
    late StreamController<ScanEvent> controller;
    StreamSubscription<Object?>? subscription;

    Future<void> stop() async {
      await subscription?.cancel();
      subscription = null;
      // Tells the native walk to stop descending; without it, leaving a
      // directory would keep a deep tree churning in the background.
      try {
        await _methods.invokeMethod<void>('cancelScan', {'id': id});
      } on Object {
        // The scan was already finished or the platform is not there.
      }
    }

    controller = StreamController<ScanEvent>(
      onCancel: stop,
      onListen: () async {
        subscription = _events.receiveBroadcastStream().listen((event) {
          if (event is! Map || event['id'] != id) return;
          final parsed = _parse(event);
          if (parsed == null) return;
          controller.add(parsed);
          if (parsed is ScanComplete || parsed is ScanFailed) {
            controller.close();
          }
        }, onError: controller.addError);

        try {
          await _methods.invokeMethod<void>('startScan', {
            'path': path,
            'id': id,
          });
        } on Object catch (error) {
          controller
            ..add(ScanFailed('$error', 0))
            ..close();
        }
      },
    );

    return controller.stream;
  }

  ScanEvent? _parse(Map<Object?, Object?> event) {
    switch (event['kind']) {
      case 'entry':
        final seconds = event['accessed'];
        return ScanEntry(
          path: '${event['path']}',
          isDirectory: event['isDirectory'] == true,
          sizeBytes: event['sizeBytes'] is int
              ? event['sizeBytes']! as int
              : null,
          accessed: seconds is int
              ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
              : null,
        );
      case 'listed':
        return ScanListed(event['pending'] is int ? event['pending']! as int : 0);
      case 'size':
        final size = event['sizeBytes'];
        if (size is! int) return null;
        return ScanSize('${event['path']}', size);
      case 'complete':
        return ScanComplete(deduped: event['deduped'] == true);
      case 'failed':
        return ScanFailed(
          '${event['reason']}',
          event['code'] is int ? event['code']! as int : 0,
        );
      default:
        return null;
    }
  }
}
