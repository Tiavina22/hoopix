import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/entities/uninstall_protection.dart';

/// Ports the read-only half of `mo uninstall`'s app inventory
/// (`bin/uninstall.sh`): finds installed `.app` bundles, reads their
/// bundle id and display name, and filters out anything
/// [shouldProtectFromUninstall] refuses or that is a background-only
/// helper not directly in one of the search roots.
///
/// Not ported in this pass: `/Volumes/*/Applications` enumeration,
/// pkg-receipt non-standard install locations, the bundle-id+basename
/// dedup rank, and the mdls Spotlight display-name fast path (a pure
/// performance optimization — `CFBundleDisplayName`/`CFBundleName` alone
/// already give a correct name). Symlinked `.app` bundles are not
/// discovered at all rather than resolved and safety-checked — a real gap
/// against Mole's own reach, but a safe one: under-discovery, never a
/// wrongly-included path, since nothing here deletes anything yet.
class UninstallAppDiscovery {
  UninstallAppDiscovery({
    required this.home,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 3)),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  List<String> get searchRoots => [
    '/Applications',
    '$home/Applications',
    '/Library/Input Methods',
    '$home/Library/Input Methods',
  ];

  Future<List<InstalledApp>> discover() async {
    final apps = <InstalledApp>[];

    for (final root in searchRoots) {
      for (final found in _findAppsUnder(root)) {
        if (_isNestedInsideAnotherApp(found.path)) continue;

        final bundleId = await _resolveBundleId(found.path);
        if (bundleId != 'unknown' && shouldProtectFromUninstall(bundleId)) {
          continue;
        }

        // A direct child of the root is depth 1 in the walk below, which
        // is exactly "directly in a search root" regardless of what path
        // string the root itself resolves to.
        if (await _isBackgroundOnly(found.path) && found.depth != 1) {
          continue;
        }

        apps.add(
          InstalledApp(
            path: found.path,
            bundleId: bundleId,
            displayName: await _resolveDisplayName(found.path),
          ),
        );
      }
    }

    return apps;
  }

  /// Every real (non-symlink) `*.app` directory up to [maxDepth] levels
  /// below [root] — matching `find "$root" -maxdepth 3 -name "*.app"`,
  /// which does not prune at a match either, so a nested app is still
  /// found here and excluded afterward by [_isNestedInsideAnotherApp].
  List<_FoundApp> _findAppsUnder(String root, {int maxDepth = 3}) {
    final found = <_FoundApp>[];

    void walk(String dir, int depth) {
      if (depth > maxDepth) return;

      final List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }

      for (final entity in entries) {
        if (entity is! Directory) continue;
        if (entity.path.endsWith('.app')) {
          found.add(_FoundApp(entity.path, depth));
        }
        if (depth < maxDepth) walk(entity.path, depth + 1);
      }
    }

    walk(root, 1);
    return found;
  }

  bool _isNestedInsideAnotherApp(String appPath) {
    final parent = _parentOf(appPath);
    return parent.endsWith('.app') || parent.contains('.app/');
  }

  String _parentOf(String path) {
    final lastSlash = path.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : path.substring(0, lastSlash);
  }

  Future<String> _resolveBundleId(String appPath) async {
    final value = await _extractPlistString(
      '$appPath/Contents/Info.plist',
      'CFBundleIdentifier',
    );
    return value ?? 'unknown';
  }

  Future<bool> _isBackgroundOnly(String appPath) async {
    final value = await _extractPlistString(
      '$appPath/Contents/Info.plist',
      'LSBackgroundOnly',
    );
    final normalized = value?.toLowerCase();
    return normalized == '1' || normalized == 'yes' || normalized == 'true';
  }

  Future<String> _resolveDisplayName(String appPath) async {
    final appName = appPath.split('/').last.replaceAll(RegExp(r'\.app$'), '');
    final plist = '$appPath/Contents/Info.plist';

    var displayName = appName;
    final bundleDisplayName = await _extractPlistString(
      plist,
      'CFBundleDisplayName',
    );
    final bundleName = await _extractPlistString(plist, 'CFBundleName');
    if (bundleDisplayName != null) {
      displayName = bundleDisplayName;
    } else if (bundleName != null) {
      displayName = bundleName;
    }

    if (displayName.startsWith('/')) displayName = appName;

    // Keep a versioned bundle name ("App 2") distinct from its metadata
    // name ("App") when the two would otherwise collapse to one label.
    if (appName != displayName && appName.startsWith(displayName)) {
      final suffix = appName.substring(displayName.length);
      if (RegExp('[0-9]').hasMatch(suffix)) displayName = appName;
    }

    return displayName;
  }

  Future<String?> _extractPlistString(String plistPath, String key) async {
    if (FileSystemEntity.typeSync(plistPath, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final result = await _probe.run('plutil', [
      '-extract',
      key,
      'raw',
      plistPath,
    ]);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    return (value == null || value.isEmpty || value == '(null)') ? null : value;
  }
}

/// One `.app` bundle found during a walk, with how many levels below its
/// search root it sits — depth 1 means a direct child of the root.
class _FoundApp {
  const _FoundApp(this.path, this.depth);

  final String path;
  final int depth;
}
