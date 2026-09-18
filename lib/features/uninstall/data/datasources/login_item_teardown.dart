import 'dart:io';

import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';

/// Deletes every System Events login item whose name is exactly the first
/// argument, walking the list backwards so deleting one never shifts the
/// index of the next — the same loop as Mole's `remove_login_item`. The name
/// arrives through `argv` rather than being spliced into the script text, so
/// no quoting or escaping of an app name can change what the script does.
const _removeLoginItemScript = [
  'on run argv',
  'set targetName to item 1 of argv',
  'tell application "System Events"',
  'try',
  'set itemCount to count of login items',
  'repeat with i from itemCount to 1 by -1',
  'try',
  'if name of login item i is targetName then delete login item i',
  'end try',
  'end repeat',
  'end try',
  'end tell',
  'end run',
];

/// Ports the login-item half of Mole's uninstall teardown
/// (`lib/uninstall/batch.sh`): `remove_login_item`,
/// `discover_login_item_helper_bundle_ids`, and `bootout_login_item_helpers`.
///
/// Deliberate difference from Mole: an `osascript` timeout in
/// [removeLoginItem] is not a reason to abandon the batch. The first call
/// from hoopix raises macOS' "hoopix wants to control System Events"
/// Automation prompt, and osascript waits on it; treating that wait as
/// launchd-style unresponsiveness would fail the very first uninstall on
/// every machine. A login item left behind only points at an app that is no
/// longer there, so the timeout is longer (to leave time to answer) and
/// merely reported.
class LoginItemTeardown {
  LoginItemTeardown({
    ProcessRunner? runner,
    ProcessRunner? scriptRunner,
    List<String> Function(String directory)? listNames,
    FileSystemEntityType Function(String path)? typeOf,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _scriptRunner =
           scriptRunner ?? const ProcessRunner(timeout: Duration(seconds: 30)),
       _listNames = listNames ?? listDirectoryNames,
       _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false));

  final ProcessRunner _runner;
  final ProcessRunner _scriptRunner;
  final List<String> Function(String directory) _listNames;
  final FileSystemEntityType Function(String path) _typeOf;

  /// Removes the login items named after [appName]. Returns
  /// [LaunchTeardownResult.timedOut] only so the caller can report it; see
  /// the class comment for why it never stops the batch.
  Future<LaunchTeardownResult> removeLoginItem(String appName) async {
    final name = appName.endsWith('.app')
        ? appName.substring(0, appName.length - '.app'.length)
        : appName;
    if (name.isEmpty) return LaunchTeardownResult.completed;

    final result = await _scriptRunner.run('osascript', [
      for (final line in _removeLoginItemScript) ...['-e', line],
      name,
    ]);
    return result.failure?.kind == ProcessFailureKind.timedOut
        ? LaunchTeardownResult.timedOut
        : LaunchTeardownResult.completed;
  }

  /// Ports `discover_login_item_helper_bundle_ids`: the bundle id of every
  /// `.app` directly under the app's own `Contents/Library/LoginItems`,
  /// reverse-DNS ones only. Must run while the bundle is still on disk. A
  /// timeout yields no helpers rather than an error, as in Mole.
  Future<List<String>> discoverHelperIds(String appPath) async {
    final root = '$appPath/Contents/Library/LoginItems';
    final ids = <String>[];
    for (final name in _listNames(root)) {
      if (!name.endsWith('.app')) continue;
      final info = '$root/$name/Contents/Info.plist';
      if (_typeOf(info) != FileSystemEntityType.file) continue;
      final result = await _runner.run('plutil', [
        '-extract',
        'CFBundleIdentifier',
        'raw',
        info,
      ]);
      if (result.failure?.kind == ProcessFailureKind.timedOut) return const [];
      final id = result.isSuccess ? result.stdout?.trim() ?? '' : '';
      if (isReverseDnsBundleId(id)) ids.add(id);
    }
    return ids;
  }

  /// Ports `bootout_login_item_helpers`: `launchctl bootout gui/<uid>/<id>`
  /// for each helper, never for Apple's own namespace whatever a helper's
  /// Info.plist claims. A bootout of a helper that is not running fails
  /// harmlessly; only a timeout stops the loop.
  Future<LaunchTeardownResult> bootoutHelpers(List<String> helperIds) async {
    final ids = [
      for (final id in helperIds)
        if (isReverseDnsBundleId(id) && !id.startsWith('com.apple.')) id,
    ];
    if (ids.isEmpty) return LaunchTeardownResult.completed;

    final uidResult = await _runner.run('id', ['-u']);
    final uid = uidResult.isSuccess ? uidResult.stdout?.trim() ?? '' : '';
    if (int.tryParse(uid) == null) return LaunchTeardownResult.completed;

    for (final id in ids) {
      final result = await _runner.run('launchctl', [
        'bootout',
        'gui/$uid/$id',
      ]);
      if (result.failure?.kind == ProcessFailureKind.timedOut) {
        return LaunchTeardownResult.timedOut;
      }
    }
    return LaunchTeardownResult.completed;
  }
}
