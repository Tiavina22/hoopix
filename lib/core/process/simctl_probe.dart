import 'dart:io';

import 'process_guard.dart';
import 'process_runner.dart';

/// Resolves `simctl` and answers whether any simulator device is booted —
/// port of `_resolve_simctl_developer_dir`, `_run_simctl` and
/// `_coresimulator_booted_device_state` (`lib/clean/dev.sh`).
///
/// A booted device holds live CoreSimulator state with no matching
/// foreground process, so a process-name check alone is a strictly weaker
/// guard than this one. Every answer is fail-closed: anything that cannot
/// be established reads as [ProcessLiveness.unknown], never as "nothing is
/// running".
///
/// `simctl` is resolved without touching the machine-wide `xcode-select`
/// setting: an explicit `DEVELOPER_DIR` is authoritative (an invalid one
/// never silently falls through to a different Xcode), then the selected
/// developer directory, and only for a Command Line Tools selection does it
/// look at installed `Xcode*.app` bundles — where exactly one usable
/// candidate resolves and two or more are ambiguous, which is unavailable
/// rather than a guess.
class SimctlProbe {
  SimctlProbe({
    ProcessRunner? probe,
    List<String>? xcodeAppRoots,
    String? home,
    String? explicitDeveloperDir,
    bool readEnvironment = true,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _xcodeAppRoots =
           xcodeAppRoots ??
           ['/Applications', if (home != null) '$home/Applications'],
       _explicitDeveloperDir =
           explicitDeveloperDir ??
           (readEnvironment ? Platform.environment['DEVELOPER_DIR'] : null),
       _directory = directory ?? Directory.new;

  final ProcessRunner _probe;
  final List<String> _xcodeAppRoots;
  final String? _explicitDeveloperDir;
  final Directory Function(String path) _directory;

  String? _resolvedDeveloperDir;
  bool _resolutionAttempted = false;

  /// Whether any simulator device is currently booted.
  Future<ProcessLiveness> bootedDeviceState() async {
    final developerDir = await _developerDir();
    if (developerDir == null) return ProcessLiveness.unknown;

    final result = await _probe.run('env', [
      'DEVELOPER_DIR=$developerDir',
      'xcrun',
      'simctl',
      'list',
      'devices',
      'booted',
      '-j',
    ]);
    if (!result.isSuccess) return ProcessLiveness.unknown;

    final output = result.stdout ?? '';
    // A response that is not the expected shape proves nothing either way.
    if (!output.contains('"devices"')) return ProcessLiveness.unknown;
    return output.contains('"udid"')
        ? ProcessLiveness.running
        : ProcessLiveness.notRunning;
  }

  /// The developer directory `simctl` runs under, resolved once per probe.
  Future<String?> _developerDir() async {
    if (_resolutionAttempted) return _resolvedDeveloperDir;
    _resolutionAttempted = true;
    _resolvedDeveloperDir = await _resolveDeveloperDir();
    return _resolvedDeveloperDir;
  }

  Future<String?> _resolveDeveloperDir() async {
    final explicit = _explicitDeveloperDir;
    if (explicit != null && explicit.isNotEmpty) {
      // Authoritative: an invalid explicit setting is an answer, not a
      // reason to switch the caller to another Xcode.
      return await _isUsable(explicit) ? explicit : null;
    }

    final selected = await _selectedDeveloperDir();
    if (selected == null || selected.isEmpty) return null;

    final selectedIsCommandLineTools =
        selected == '/Library/Developer/CommandLineTools' ||
        selected == '/Library/Developer/CommandLineTools/';
    if (!selectedIsCommandLineTools) {
      return await _isUsable(selected) ? selected : null;
    }

    // Command Line Tools carry no simulator runtime, so fall back to the
    // installed Xcode apps — but only when exactly one of them works.
    final candidates = <String>[];
    for (final root in _xcodeAppRoots) {
      for (final app in _xcodeAppsIn(root)) {
        final developerDir = '$app/Contents/Developer';
        if (await _isUsable(developerDir)) candidates.add(developerDir);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  Future<String?> _selectedDeveloperDir() async {
    final result = await _probe.run('xcode-select', ['-p']);
    if (!result.isSuccess) return null;
    return result.stdout?.trim();
  }

  Future<bool> _isUsable(String developerDir) async {
    if (FileSystemEntity.typeSync(developerDir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    final result = await _probe.run('env', [
      'DEVELOPER_DIR=$developerDir',
      'xcrun',
      '--find',
      'simctl',
    ]);
    return result.isSuccess;
  }

  List<String> _xcodeAppsIn(String root) {
    try {
      return [
        for (final entity in _directory(root).listSync(followLinks: false))
          if (entity is Directory &&
              entity.path.split('/').last.startsWith('Xcode') &&
              entity.path.endsWith('.app'))
            entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }
}
