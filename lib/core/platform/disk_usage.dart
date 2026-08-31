import 'dart:io';

import 'package:flutter/services.dart';

/// What files actually occupy on disk, as `du` counts it.
///
/// Dart's [FileStat] exposes only the logical length, so a sparse file or an
/// iCloud placeholder would be reported at its full nominal size and the file
/// rows would disagree with the `du` directory totals beside them. The real
/// figure comes from `st_blocks`, which only native code can read — see
/// `macos/Runner/DiskUsageChannel.swift`.
class DiskUsage {
  const DiskUsage([this.channel = const MethodChannel(_channelName)]);

  static const _channelName = 'fit.hoopix/disk_usage';

  final MethodChannel channel;

  /// On-disk bytes for each of [paths], in the same order. An entry is null
  /// when the path is unreadable or is not a regular file.
  ///
  /// Sent as one batch: a directory listing sizes hundreds of files, and a
  /// channel round trip each would cost more than the stats themselves.
  Future<List<int?>> actualSizes(List<String> paths) async {
    if (paths.isEmpty) return const [];

    try {
      final sizes = await channel.invokeListMethod<Object?>('actualSizes', {
        'paths': paths,
      });
      if (sizes != null && sizes.length == paths.length) {
        return [
          for (final size in sizes) size is int ? size : null,
        ];
      }
    } on Object {
      // Falls through to the logical sizes below.
    }

    // No native side answering — a plain `flutter test` run, or a platform
    // where the channel is not registered. Logical sizes are the honest
    // approximation rather than no sizes at all.
    return [for (final path in paths) await _logicalSize(path)];
  }

  Future<int?> _logicalSize(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type != FileSystemEntityType.file) return null;
      return stat.size;
    } on Object {
      return null;
    }
  }
}
