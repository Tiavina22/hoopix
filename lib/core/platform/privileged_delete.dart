import 'package:flutter/services.dart';

/// Deletes specific root-owned system paths through the standard macOS
/// administrator-privileges prompt — see `macos/Runner/PrivilegedDeleteChannel.swift`,
/// which also holds the allowlist of roots this may ever touch. Not
/// recoverable the way [Trash] is: this is `rm -rf`, run once with
/// elevation, for the narrow set of system caches Mole itself only ever
/// reaches through `sudo`.
///
/// Deliberately has no Dart fallback, matching [Trash]: no native side
/// means nothing is deleted and the caller is told so, not silently
/// skipped.
class PrivilegedDelete {
  const PrivilegedDelete([this.channel = const MethodChannel(_channelName)]);

  static const _channelName = 'fit.hoopix/privileged_delete';

  final MethodChannel channel;

  /// Deletes each of [paths] after one administrator-privileges prompt for
  /// the whole batch.
  ///
  /// Returns the paths that did not make it, mapped to why — a refusal for
  /// one path never stops the others, but a cancelled prompt naturally
  /// fails every path in the same batch at once. An empty map means every
  /// path was removed.
  Future<Map<String, String>> deletePaths(List<String> paths) async {
    if (paths.isEmpty) return const {};

    final failures = await channel.invokeMapMethod<String, Object?>(
      'deletePaths',
      {'paths': paths},
    );

    return {
      for (final entry in (failures ?? const {}).entries)
        entry.key: '${entry.value}',
    };
  }
}
