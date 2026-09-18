import 'dart:io';

import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_runner.dart';

const _plistBuddy = '/usr/libexec/PlistBuddy';

/// The three Dock arrays Mole walks: pinned apps, the right-hand stacks and
/// files, and the recent-apps section.
const _dockArrays = ['persistent-apps', 'persistent-others', 'recent-apps'];

/// One removed app whose Dock tile should go: its bundle path, and the
/// bundle id the removal actually used — `unknown` under the sibling guard,
/// so a surviving install's tile is never matched by bundle id.
class DockTarget {
  const DockTarget({required this.appPath, required this.bundleId});

  final String appPath;
  final String bundleId;
}

/// Ports `remove_apps_from_dock` (`lib/core/common.sh`): deletes the Dock
/// tiles of apps that were just removed, through PlistBuddy on
/// `com.apple.dock.plist`, then restarts the Dock so it rereads the file —
/// only when something actually changed.
///
/// Deliberately narrower than Mole: a tile matches by path only when its
/// file URL decodes to exactly the app's path. Mole's substring test lets
/// `/Applications/Foo.app` also claim `~/Applications/Foo.app`, which is the
/// other install the sibling guard exists to protect.
class DockCleanup {
  DockCleanup({
    required this.home,
    ProcessRunner? runner,
    FileSystemEntityType Function(String path)? typeOf,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false));

  final String home;
  final ProcessRunner _runner;
  final FileSystemEntityType Function(String path) _typeOf;

  String get _plist => '$home/Library/Preferences/com.apple.dock.plist';

  /// Returns whether any tile was removed.
  Future<bool> remove(List<DockTarget> targets) async {
    final usable = [
      for (final target in targets)
        if (target.appPath.startsWith('/') &&
            !target.appPath.contains(RegExp(r'[\x00-\x1f\x7f]')))
          target,
    ];
    if (usable.isEmpty) return false;
    if (_typeOf(_plist) != FileSystemEntityType.file) return false;
    if (_typeOf(_plistBuddy) == FileSystemEntityType.notFound) return false;

    var changed = false;
    for (final array in _dockArrays) {
      var i = 0;
      // Bounded by the Dock's own size: an entry that cannot be read ends
      // the array, exactly as Mole's empty tile-type does.
      while (true) {
        final tileType = await _print('$array:$i:tile-type');
        if (tileType == null || tileType.isEmpty) break;

        final url = await _print('$array:$i:tile-data:file-data:_CFURLString');
        final bundleId = await _print('$array:$i:tile-data:bundle-identifier');

        if (usable.any((t) => _matches(t, url, bundleId))) {
          final deleted = await _runner.run(_plistBuddy, [
            '-c',
            'Delete :$array:$i',
            _plist,
          ]);
          if (deleted.isSuccess) {
            changed = true;
            // The next tile now sits at index i.
            continue;
          }
        }
        i++;
      }
    }

    if (changed) await _runner.run('killall', ['Dock']);
    return changed;
  }

  Future<String?> _print(String key) async {
    final result = await _runner.run(_plistBuddy, [
      '-c',
      'Print :$key',
      _plist,
    ]);
    return result.isSuccess ? result.stdout?.trim() : null;
  }
}

bool _matches(DockTarget target, String? url, String? tileBundleId) {
  if (isReverseDnsBundleId(target.bundleId) &&
      tileBundleId != null &&
      tileBundleId == target.bundleId) {
    return true;
  }
  final tilePath = _filePath(url);
  return tilePath != null && tilePath == _trimSlash(target.appPath);
}

String? _filePath(String? url) {
  if (url == null || !url.startsWith('file://')) return null;
  try {
    return _trimSlash(Uri.parse(url).toFilePath());
  } on FormatException {
    return null;
  } on UnsupportedError {
    return null;
  }
}

String _trimSlash(String path) =>
    path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
