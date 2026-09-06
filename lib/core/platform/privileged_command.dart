import 'package:flutter/services.dart';

/// Runs one of a fixed set of named system-maintenance operations through
/// the standard macOS administrator-privileges prompt — see
/// `macos/Runner/PrivilegedCommandChannel.swift`, which owns the literal
/// shell text for every operation id and is the entire safety boundary:
/// this class only ever names which fixed operation to run, never
/// assembles a command itself.
///
/// Deliberately has no Dart fallback, matching [Trash] and
/// [PrivilegedDelete]: no native side means the operation did not run, and
/// the caller is told so rather than the call silently doing nothing.
class PrivilegedCommand {
  const PrivilegedCommand([this.channel = const MethodChannel(_channelName)]);

  static const _channelName = 'fit.hoopix/privileged_command';

  final MethodChannel channel;

  /// Runs [operation] — one of the ids `PrivilegedCommandChannel` knows —
  /// with an administrator-privileges prompt. [arguments] carries the one
  /// caller-supplied value some operations need (`reset_user_permissions`'s
  /// `uid`); the native side validates it before use.
  ///
  /// Returns null on success, or a failure message — a cancelled prompt,
  /// an unknown operation id, or the command's own failure.
  Future<String?> run(
    String operation, {
    Map<String, String>? arguments,
  }) async {
    try {
      await channel.invokeMethod<void>('run', {
        'operation': operation,
        'arguments': arguments ?? const <String, String>{},
      });
      return null;
    } on PlatformException catch (error) {
      return error.message ?? 'operation failed';
    } on MissingPluginException {
      return 'no native privileged-command channel available';
    }
  }
}
