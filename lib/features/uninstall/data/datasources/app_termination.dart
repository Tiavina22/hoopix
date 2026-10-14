import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_runner.dart';

/// Asks the app named by argv to quit through the standard Quit Apple
/// Event — by bundle id when there is one (display names are localized),
/// by name otherwise. The target arrives through `argv`, never spliced into
/// the script text.
const _quitByIdScript = [
  'on run argv',
  'tell application id (item 1 of argv) to quit',
  'end run',
];
const _quitByNameScript = [
  'on run argv',
  'tell application (item 1 of argv) to quit',
  'end run',
];

/// Process names an app bundle may claim as its `CFBundleExecutable` but
/// that must never be quit or signalled: a third-party bundle sets that
/// string freely, so it is refused rather than trusted, as Mole's
/// `force_kill_app` does.
const _systemProcessNames = {
  'Finder',
  'Dock',
  'loginwindow',
  'WindowServer',
  'SystemUIServer',
  'launchd',
  'coreaudiod',
  'NotificationCenter',
  'ControlCenter',
  'Spotlight',
};

/// Port of Mole's `force_kill_app` (`lib/core/app_protection.sh`): stops
/// an app about to be uninstalled. The user has confirmed the removal, so
/// after a graceful Quit — which lets the app save its state, or ask to —
/// a process that is still there gets SIGTERM, then SIGKILL. Each step is
/// skipped as soon as the process is gone.
///
/// Not ported: Mole's final `sudo pkill -9` retry, which only ever runs on
/// an already-cached sudo session; hoopix has none and never prompts for
/// this. macOS lets a running app's bundle be removed (the process keeps
/// its mapped code), so a process that survives does not stop the
/// uninstall: the caller reports it instead.
class AppTermination {
  AppTermination({
    ProcessRunner? runner,
    ProcessRunner? scriptRunner,
    Future<void> Function(Duration duration)? sleep,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _scriptRunner =
           scriptRunner ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _sleep = sleep ?? Future<void>.delayed;

  final ProcessRunner _runner;
  final ProcessRunner _scriptRunner;
  final Future<void> Function(Duration duration) _sleep;

  /// The process name [appPath] runs as when it is running now, or null.
  Future<String?> runningProcess(
    String appPath, {
    required String displayName,
  }) async {
    final name = (await _identity(appPath, displayName)).processName;
    if (name == null) return null;
    return await _isRunning(name) ? name : null;
  }

  /// Stops [appPath] if it is running. Returns false only when a process
  /// is still there at the end, or its name is one that is never signalled.
  Future<bool> quit(String appPath, {required String displayName}) async {
    final identity = await _identity(appPath, displayName);
    final name = identity.processName;
    if (name == null) return true;
    if (_systemProcessNames.contains(name)) return false;
    if (!await _isRunning(name)) return true;

    final bundleId = identity.bundleId;
    await _scriptRunner.run('/usr/bin/osascript', [
      for (final line
          in bundleId != null ? _quitByIdScript : _quitByNameScript) ...[
        '-e',
        line,
      ],
      bundleId ?? displayName,
    ]);
    if (await _waitForExit(name)) return true;

    await _runner.run('/usr/bin/pkill', ['-x', name]);
    if (await _waitForExit(name)) return true;

    await _runner.run('/usr/bin/pkill', ['-9', '-x', name]);
    return _waitForExit(name);
  }

  /// `CFBundleExecutable` and `CFBundleIdentifier` from the bundle's own
  /// Info.plist, falling back to the display name for matching, as Mole
  /// does.
  Future<({String? processName, String? bundleId})> _identity(
    String appPath,
    String displayName,
  ) async {
    final info = '$appPath/Contents/Info.plist';
    final executable = await _plistValue(info, 'CFBundleExecutable');
    final bundleId = await _plistValue(info, 'CFBundleIdentifier');
    final fallback = displayName.endsWith('.app')
        ? displayName.substring(0, displayName.length - '.app'.length)
        : displayName;
    final name = (executable == null || executable.isEmpty)
        ? fallback
        : executable;
    return (
      processName: name.isEmpty ? null : name,
      bundleId: bundleId != null && isReverseDnsBundleId(bundleId)
          ? bundleId
          : null,
    );
  }

  Future<String?> _plistValue(String plist, String key) async {
    final result = await _runner.run('/usr/bin/plutil', [
      '-extract',
      key,
      'raw',
      plist,
    ]);
    return result.isSuccess ? result.stdout?.trim() : null;
  }

  /// `pgrep -x`: exit 0 is a match, anything else is treated as not
  /// running — best effort, as in Mole, since the uninstall goes ahead
  /// either way and only the report depends on it.
  Future<bool> _isRunning(String name) async =>
      (await _runner.run('/usr/bin/pgrep', ['-x', name])).isSuccess;

  /// Polls for up to two seconds, Mole's `_mole_wait_for_app_exit` budget,
  /// returning as soon as the process is gone.
  Future<bool> _waitForExit(String name) async {
    for (var tick = 0; tick < 20; tick++) {
      if (!await _isRunning(name)) return true;
      await _sleep(const Duration(milliseconds: 100));
    }
    return !await _isRunning(name);
  }
}
