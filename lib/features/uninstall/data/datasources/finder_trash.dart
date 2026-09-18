import 'dart:io';

import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';

/// Asks Finder to move one file to the Trash. The path arrives through
/// `argv`, never spliced into the script text.
const _finderDeleteScript = [
  'on run argv',
  'set p to POSIX file (item 1 of argv)',
  'tell application "Finder"',
  'delete p',
  'end tell',
  'end run',
];

/// Ports `_mole_move_app_to_trash_via_finder` (`lib/core/file_ops.sh`): the
/// retry Mole makes when a direct Trash move of an app bundle is denied.
/// A root-owned bundle — every Mac App Store app — cannot be renamed by the
/// user, but Finder can move it after asking for an administrator password
/// itself, exactly as when the user drags it to the Trash. The result stays
/// recoverable from the Trash.
///
/// Only for an exact one-level `/Applications/<name>.app`, as Mole's
/// `_mole_path_is_application_bundle` insists: nothing else is handed to
/// Finder's elevated delete. Success is judged by the bundle being gone,
/// never by osascript's exit status alone.
///
/// Deliberate difference from Mole: two minutes instead of thirty seconds,
/// because the call waits while the user types the password.
class FinderTrash {
  FinderTrash({
    ProcessRunner? runner,
    FileSystemEntityType Function(String path)? typeOf,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(minutes: 2)),
       _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false));

  final ProcessRunner _runner;
  final FileSystemEntityType Function(String path) _typeOf;

  /// Returns whether the bundle is now gone from `/Applications`.
  Future<bool> moveApplication(String appPath) async {
    if (!isTopLevelApplication(appPath)) return false;

    final result = await _runner.run('osascript', [
      for (final line in _finderDeleteScript) ...['-e', line],
      appPath,
    ]);
    if (result.failure?.kind == ProcessFailureKind.timedOut) return false;
    return _typeOf(appPath) == FileSystemEntityType.notFound;
  }
}

/// `_mole_path_is_application_bundle`: exactly `/Applications/<name>.app`,
/// one level down, with no `..` or empty component to escape through.
bool isTopLevelApplication(String path) {
  const parent = '/Applications/';
  final trimmed = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  if (!trimmed.startsWith(parent)) return false;
  final name = trimmed.substring(parent.length);
  return name.endsWith('.app') &&
      name.length > '.app'.length &&
      !name.contains('/') &&
      name != '..' &&
      name != '.';
}
