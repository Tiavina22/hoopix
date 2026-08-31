import 'package:flutter/services.dart';

/// Moves paths to the Trash through the native side, which also holds the
/// refusal rules — see `macos/Runner/TrashChannel.swift`.
///
/// Deliberately has no Dart fallback. Every other channel here degrades to an
/// approximation when the native side is absent; a deletion must not. No
/// native side means nothing is deleted and the caller is told so.
class Trash {
  const Trash([this.channel = const MethodChannel(_channelName)]);

  static const _channelName = 'fit.hoopix/trash';

  final MethodChannel channel;

  /// Moves each of [paths] to the Trash, recoverable from there.
  ///
  /// Returns the paths that did not make it, mapped to why. An empty map
  /// means every path was moved. A refusal for one path never stops the
  /// others.
  Future<Map<String, String>> moveToTrash(List<String> paths) async {
    if (paths.isEmpty) return const {};

    final failures = await channel.invokeMapMethod<String, Object?>(
      'moveToTrash',
      {'paths': paths},
    );

    return {
      for (final entry in (failures ?? const {}).entries)
        entry.key: '${entry.value}',
    };
  }
}
