import 'dart:convert';
import 'dart:io';

import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/domain/entities/launch_agent_match.dart';

/// Whether [LaunchServiceTeardown.stop] got through every unload, or gave
/// up on one that did not answer in time.
enum LaunchTeardownResult { completed, timedOut }

/// Ports `stop_launch_services` (`lib/uninstall/batch.sh`): unloads the
/// app's LaunchAgents from launchd before any file moves, so a job whose
/// plist is about to go to the Trash is not left running until logout.
/// Removing the plists themselves stays with the Trash step, through the
/// same leftover list every other path goes through — the same split Mole
/// keeps between this and `remove_file_list`.
///
/// Two passes, in Mole's order: plists named after the bundle id (skipped
/// when the sibling guard demoted it to `unknown`), then every plist whose
/// contents reference the app's own path — which catches agents with a
/// bundle id unrelated to the app's, and still runs under the sibling
/// guard, because name-globbed plists are removed either way.
///
/// User domain only. `/Library/LaunchAgents` and `/Library/LaunchDaemons`
/// need `sudo launchctl`, which Mole itself skips without authorization and
/// hoopix never runs; leftover discovery never collects those plists
/// either, so nothing root-owned is unloaded or removed here.
///
/// An ordinary unload failure (a job that was never loaded) is not a reason
/// to stop, matching Mole's `unload_launch_plist` which only propagates a
/// timeout; a timeout is, since it means launchd is not answering.
class LaunchServiceTeardown {
  LaunchServiceTeardown({
    required this.home,
    ProcessRunner? runner,
    List<String> Function(String directory)? listNames,
    Future<List<int>> Function(String path)? readBytes,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _listNames = listNames ?? listDirectoryNames,
       _readBytes = readBytes ?? ((path) => File(path).readAsBytes());

  final String home;
  final ProcessRunner _runner;
  final List<String> Function(String directory) _listNames;
  final Future<List<int>> Function(String path) _readBytes;

  Future<LaunchTeardownResult> stop({
    required String bundleId,
    required String appPath,
  }) async {
    final agentsDir = '$home/Library/LaunchAgents';
    final plists = [
      for (final name in _listNames(agentsDir))
        if (name.endsWith('.plist')) name,
    ];
    if (plists.isEmpty) return LaunchTeardownResult.completed;

    final unloaded = <String>{};

    for (final name in plists) {
      if (!launchAgentNameMatchesBundleId(name, bundleId)) continue;
      final path = '$agentsDir/$name';
      if (!await _unload(path)) return LaunchTeardownResult.timedOut;
      unloaded.add(path);
    }

    if (appPath.isEmpty) return LaunchTeardownResult.completed;
    final needle = utf8.encode(appPath);
    for (final name in plists) {
      final path = '$agentsDir/$name';
      if (unloaded.contains(path)) continue;
      if (!await _references(path, needle)) continue;
      if (!await _unload(path)) return LaunchTeardownResult.timedOut;
      unloaded.add(path);
    }

    return LaunchTeardownResult.completed;
  }

  /// `launchctl unload`, returning false only when it timed out.
  Future<bool> _unload(String plist) async {
    final result = await _runner.run('launchctl', ['unload', plist]);
    return result.failure?.kind != ProcessFailureKind.timedOut;
  }

  /// Ports `grep -qF -- "$app_path" "$plist"`: a raw byte search, so it
  /// matches the path inside a binary plist's ASCII string table as well
  /// as an XML one. An unreadable plist is simply not a match.
  Future<bool> _references(String path, List<int> needle) async {
    final List<int> bytes;
    try {
      bytes = await _readBytes(path);
    } on FileSystemException {
      return false;
    }
    return _indexOf(bytes, needle) >= 0;
  }
}

int _indexOf(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return 0;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
