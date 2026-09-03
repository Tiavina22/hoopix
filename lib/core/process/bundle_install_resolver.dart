import 'dart:io';

import 'process_runner.dart';

/// A dotted reverse-DNS shape (`com.foo.bar`), port of
/// `mole_is_reverse_dns_bundle_id` (`lib/core/base.sh`) — at least two
/// dot-separated segments, each starting and made only of letters, digits
/// and hyphens.
bool isReverseDnsBundleId(String bundleId) {
  if (bundleId.isEmpty || bundleId == 'unknown') return false;
  return RegExp(
    r'^[A-Za-z0-9][-A-Za-z0-9]*(\.[A-Za-z0-9][-A-Za-z0-9]*)+$',
  ).hasMatch(bundleId);
}

/// Whether some installed app either carries [bundleId] as its own
/// `CFBundleIdentifier`, or registers a privileged helper with that id via
/// SMJobBless (`Contents/Library/LaunchServices/<id>`). Port of
/// `bundle_has_installed_app` (`lib/core/bundle_resolver.sh`).
///
/// Spotlight is unreliable — indexing can be off for `/Applications`,
/// Homebrew casks sometimes skip metadata importers, and Spotlight rarely
/// indexes a helper embedded inside a `.app` bundle — so an mdfind miss
/// falls back to walking the known app-install roots directly, reading
/// each `Info.plist`. Every inconclusive probe (timeout, unreadable plist,
/// exhausted deadline) counts as "installed": this answers "is it safe to
/// call this orphaned", and a false negative there deletes a live app's
/// registration.
class BundleInstallResolver {
  BundleInstallResolver({
    ProcessRunner? probe,
    String? home,
    List<String>? appRoots,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _appRoots =
           appRoots ??
           [
             '/Applications',
             '/Applications/Setapp',
             '/Applications/Utilities',
             '/System/Applications',
             '/System/Applications/Utilities',
             if (home != null) '$home/Applications',
             if (home != null)
               '$home/Library/Application Support/Setapp/Applications',
             '/opt/homebrew/Caskroom',
             '/usr/local/Caskroom',
             '/Library/Input Methods',
             if (home != null) '$home/Library/Input Methods',
           ],
       _directory = directory ?? Directory.new;

  final ProcessRunner _probe;
  final List<String> _appRoots;
  final Directory Function(String path) _directory;

  static const _helperSuffixes = [
    '.helper',
    '.daemon',
    '.agent',
    '.xpc',
    '.service',
  ];

  /// `autoupdate.helper` / `licensingV2.helper` register once for the whole
  /// Office suite, not per app — any Office app installed protects them.
  static const _mappedBundles = {
    'com.microsoft.autoupdate.helper': [
      'com.microsoft.Word',
      'com.microsoft.Excel',
      'com.microsoft.Powerpoint',
      'com.microsoft.Outlook',
      'com.microsoft.OneNote',
    ],
    'com.microsoft.office.licensingV2.helper': [
      'com.microsoft.Word',
      'com.microsoft.Excel',
      'com.microsoft.Powerpoint',
      'com.microsoft.Outlook',
      'com.microsoft.OneNote',
    ],
  };

  Future<bool> hasInstalledApp(String bundleId) async {
    if (!isReverseDnsBundleId(bundleId)) return false;

    if (await _mdfindHit(bundleId)) return true;

    final bundleIdLower = bundleId.toLowerCase();
    String? parentIdLower;
    for (final suffix in _helperSuffixes) {
      if (bundleIdLower.endsWith(suffix)) {
        parentIdLower = bundleIdLower.substring(
          0,
          bundleIdLower.length - suffix.length,
        );
        break;
      }
    }
    final mapped = _mappedBundles[bundleId] ?? const [];

    for (final root in _appRoots) {
      // Caskroom and Setapp's own Applications folder nest the .app deeper
      // than a plain Applications folder (<cask>/<version>/App.app).
      final depth =
          root.endsWith('Caskroom') || root.endsWith('Setapp/Applications')
          ? 3
          : 1;
      for (final app in _appBundlesUnder(root, maxDepth: depth)) {
        if (FileSystemEntity.typeSync(
              '$app/Contents/Library/LaunchServices/$bundleId',
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound) {
          return true;
        }

        final info = '$app/Contents/Info.plist';
        if (FileSystemEntity.typeSync(info, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final appBundleId = await _bundleIdentifier(info);
        // An unreadable Info.plist is inconclusive, not evidence of absence.
        if (appBundleId == null) return true;
        final appBundleIdLower = appBundleId.toLowerCase();
        if (appBundleIdLower == bundleIdLower ||
            (parentIdLower != null && appBundleIdLower == parentIdLower)) {
          return true;
        }
        if (mapped.contains(appBundleId)) return true;
      }
    }

    return false;
  }

  Future<bool> _mdfindHit(String bundleId) async {
    final result = await _probe.run('mdfind', [
      "kMDItemCFBundleIdentifier == '$bundleId'",
    ]);
    if (!result.isSuccess) return false;
    final output = (result.stdout ?? '').trim();
    return output.isNotEmpty;
  }

  Future<String?> _bundleIdentifier(String infoPlist) async {
    final result = await _probe.run('plutil', [
      '-extract',
      'CFBundleIdentifier',
      'raw',
      infoPlist,
    ]);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Every `*.app` directly under [root], or nested one level of vendor
  /// directory when [maxDepth] is 3 (Caskroom's `<cask>/<version>/*.app`,
  /// Setapp's `<vendor>/*.app`-shaped trees).
  List<String> _appBundlesUnder(String root, {required int maxDepth}) {
    final found = <String>[];
    void walk(String dir, int depth) {
      if (depth > maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        if (entity is! Directory) continue;
        if (entity.path.endsWith('.app')) {
          found.add(entity.path);
        } else {
          walk(entity.path, depth + 1);
        }
      }
    }

    walk(root, 1);
    return found;
  }
}
