import 'dart:async';
import 'dart:math' as math;

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/core/platform/du_output.dart';

/// Measures directory sizes with `du`, a bounded number at a time.
///
/// Shared by Analyze's overview and Clean so both size things the same way. Flags match Mole's own analyzer (`du -skPx`): summarize, 1024-byte
/// blocks, never follow symlinks, never cross mount points.
class SizeProbe {
  const SizeProbe(this._processRunner);

  final ProcessRunner _processRunner;

  /// How many `du` probes run at once. Enough to hide the slow ones behind
  /// the fast ones without thrashing the disk.
  static const concurrentProbes = 4;

  Future<int?> sizeOf(String path) async {
    final result = await _processRunner.run('du', ['-skPx', path]);

    // `du` exits non-zero as soon as any descendant is unreadable — routine
    // under `~/Library` — while still printing a usable total, so the exit
    // status alone is not a verdict. Mole's analyzer does the same. Parse
    // whatever came back and only give up when there is nothing to parse
    // (which is also the timeout case).
    final stdout = result.stdout;
    if (stdout == null) return null;
    return parseDuSizeBytes(stdout);
  }

  /// Sums [paths] as one figure, skipping any that cannot be read. Used for
  /// Home, which is measured as its children minus `~/Library` so the two
  /// overview rows don't count the same bytes twice.
  Future<int?> sumOf(List<String> paths) async {
    var total = 0;
    var measured = false;
    await for (final probe in pool(paths, sizeOf)) {
      final size = probe.sizeBytes;
      if (size == null) continue;
      total += size;
      measured = true;
    }
    return measured ? total : null;
  }

  /// Runs [measure] over [keys], at most [concurrentProbes] at a time,
  /// emitting each result as it lands rather than waiting for the batch.
  static Stream<({T key, int? sizeBytes})> pool<T>(
    List<T> keys,
    Future<int?> Function(T key) measure,
  ) {
    final controller = StreamController<({T key, int? sizeBytes})>();
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < keys.length) {
        final key = keys[nextIndex++];
        final sizeBytes = await measure(key);
        if (controller.isClosed) return;
        controller.add((key: key, sizeBytes: sizeBytes));
      }
    }

    // Navigating away stops the queue: probes already in flight finish (the
    // process has no external cancel handle), but no further ones start.
    controller.onCancel = () => nextIndex = keys.length;

    final workers = [
      for (var i = 0; i < math.min(concurrentProbes, keys.length); i++)
        worker(),
    ];
    unawaited(Future.wait(workers).whenComplete(controller.close));

    return controller.stream;
  }
}
