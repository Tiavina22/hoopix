import 'dart:io';

import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/pkg_receipt_apps.dart';
import 'package:hoopix/features/uninstall/domain/entities/sibling_guard.dart';

/// Ports the tri-state result of `uninstall_live_bundle_has_other_install`
/// (`lib/uninstall/batch.sh`): absence is a claim only an exhaustive scan
/// can make. [inconclusive] means the scan ran but could not read every
/// candidate — treated identically to [found] by a caller deciding whether
/// teardown is safe to widen, since a listing that could not finish can
/// never prove a sibling is not there.
enum LiveSiblingScanResult { found, absent, inconclusive }

/// Ports `uninstall_live_bundle_has_other_install`: the live, authoritative
/// re-scan that actually gates bundle-id-derived teardown, run immediately
/// before deletion rather than trusted from the preview-time inventory
/// ([bundleIdHasSurvivingSibling], which explicitly cannot authorize
/// anything on its own). Every root here must complete, and every
/// candidate's bundle id must be readable, before this returns [absent].
///
/// Beyond the fixed app roots it also covers every mounted volume's
/// top-level `Applications` folder and top-level `.app` bundles, and every
/// app a package receipt installed under `/usr/local` or `/opt`
/// ([PkgReceiptApps]). A volume or receipt it cannot read makes the answer
/// [inconclusive], never [absent].
///
/// Not ported: the dev:inode:mtime fingerprint Mole compares between its
/// preview and its delete, since hoopix's removal runs this scan itself
/// immediately before deleting rather than trusting an earlier one. `-ef`
/// (same-inode) self-exclusion is simplified to a path-string comparison.
class LiveSiblingScanner {
  LiveSiblingScanner({
    ProcessRunner? probe,
    Directory Function(String path)? directory,
    Duration? timeout,
    PkgReceiptApps? pkgReceipts,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _directory = directory ?? Directory.new,
       _timeout = timeout ?? const Duration(seconds: 60),
       _pkgReceipts = pkgReceipts ?? PkgReceiptApps();

  final ProcessRunner _probe;
  final Directory Function(String path) _directory;
  final Duration _timeout;
  final PkgReceiptApps _pkgReceipts;

  static const _volumesRoot = '/Volumes';

  List<String> _liveAppRoots(String home) => [
    '/Applications',
    '$home/Applications',
    '/System/Applications',
    '/Library/Input Methods',
    '$home/Library/Input Methods',
    '$home/Library/Application Support/Setapp/Applications',
    '/opt/homebrew/Caskroom',
    '/usr/local/Caskroom',
  ];

  Future<LiveSiblingScanResult> scan({
    required String home,
    required String bundleId,
    required String excludePath,
  }) async {
    if (!isReverseDnsBundleId(bundleId)) return LiveSiblingScanResult.absent;

    final deadline = DateTime.now().add(_timeout);
    final bundleIdLower = normalizeBundleId(bundleId);
    var inconclusive = false;

    // Receipts first, as Mole does: a receipt walk that cannot finish is a
    // doubt carried forward, not a reason to stop looking elsewhere.
    final receipts = await _pkgReceipts.nonstandardAppPaths(deadline: deadline);
    if (!receipts.complete) inconclusive = true;

    final volumes = _volumeRoots();
    if (!volumes.complete) inconclusive = true;

    // A `.app` sitting directly on a volume is its own candidate, not a
    // folder to search inside.
    final directCandidates = [...volumes.apps, ...receipts.appPaths];

    for (final root in [..._liveAppRoots(home), ...volumes.roots]) {
      if (DateTime.now().isAfter(deadline)) {
        inconclusive = true;
        break;
      }

      final resolvedRoot = _directory(root);
      final List<FileSystemEntity> entries;
      try {
        entries = resolvedRoot.listSync(followLinks: false);
      } on FileSystemException {
        // Missing root is fine (most apps do not install into every one
        // of these); unreadable is not — either way this pass cannot
        // trust what it did not see.
        if (FileSystemEntity.typeSync(resolvedRoot.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          inconclusive = true;
        }
        continue;
      }

      for (final app in _appsIn(entries, root: root, maxDepth: 3)) {
        if (DateTime.now().isAfter(deadline)) {
          inconclusive = true;
          break;
        }
        if (app == excludePath) continue;

        final otherBundleId = await _bundleIdOf(app);
        if (otherBundleId == null) {
          inconclusive = true;
          continue;
        }
        if (normalizeBundleId(otherBundleId) == bundleIdLower) {
          return LiveSiblingScanResult.found;
        }
      }
    }

    final checked = <String>{};
    for (final app in directCandidates) {
      if (app == excludePath || !checked.add(app)) continue;
      if (DateTime.now().isAfter(deadline)) {
        inconclusive = true;
        break;
      }
      // A candidate a receipt or a volume listing named but whose bundle id
      // cannot be read is a doubt, as Mole's missing_info_is_unknown says.
      final otherBundleId = await _bundleIdOf(app);
      if (otherBundleId == null) {
        inconclusive = true;
        continue;
      }
      if (normalizeBundleId(otherBundleId) == bundleIdLower) {
        return LiveSiblingScanResult.found;
      }
    }

    return inconclusive
        ? LiveSiblingScanResult.inconclusive
        : LiveSiblingScanResult.absent;
  }

  /// `find /Volumes -mindepth 2 -maxdepth 2 \( -type d -name Applications
  /// \) -o \( \( -type d -o -type l \) -name '*.app' \)`: each mounted
  /// volume's `Applications` folder, as a root to search, and each `.app`
  /// directly on it. A volume that is itself a symlink — `Macintosh HD`
  /// points at `/` — is never followed, exactly as `find` does not.
  ({List<String> roots, List<String> apps, bool complete}) _volumeRoots() {
    final roots = <String>[];
    final apps = <String>[];
    final List<FileSystemEntity> volumes;
    try {
      volumes = _directory(_volumesRoot).listSync(followLinks: false);
    } on FileSystemException {
      final missing =
          FileSystemEntity.typeSync(
            _directory(_volumesRoot).path,
            followLinks: false,
          ) ==
          FileSystemEntityType.notFound;
      return (roots: roots, apps: apps, complete: missing);
    }

    var complete = true;
    for (final volume in volumes) {
      if (volume is! Directory) continue;
      final volumePath = '$_volumesRoot/${_basename(volume.path)}';
      final List<FileSystemEntity> entries;
      try {
        entries = _directory(volumePath).listSync(followLinks: false);
      } on FileSystemException {
        complete = false;
        continue;
      }
      for (final entry in entries) {
        final name = _basename(entry.path);
        final path = '$volumePath/$name';
        if (entry is Directory && name == 'Applications') {
          roots.add(path);
        } else if ((entry is Directory || entry is Link) &&
            name.endsWith('.app')) {
          // The listed path, like every other root's candidates, so the
          // bundle id is read from exactly what was listed.
          apps.add(entry.path);
        }
      }
    }
    return (roots: roots, apps: apps, complete: complete);
  }

  String _basename(String path) => path.substring(path.lastIndexOf('/') + 1);

  /// Every `.app` reachable within [maxDepth] levels of [root], excluding
  /// one nested inside another `.app` — a helper belongs to its containing
  /// app, not a distinct installation.
  List<String> _appsIn(
    List<FileSystemEntity> rootEntries, {
    required String root,
    required int maxDepth,
  }) {
    final found = <String>[];

    void walk(List<FileSystemEntity> entries, int depth) {
      for (final entity in entries) {
        if (entity is! Directory) continue;
        if (entity.path.endsWith('.app')) {
          found.add(entity.path);
          continue; // a matched app's own children are never re-scanned
        }
        if (depth >= maxDepth) continue;
        final List<FileSystemEntity> children;
        try {
          children = _directory(entity.path).listSync(followLinks: false);
        } on FileSystemException {
          continue;
        }
        walk(children, depth + 1);
      }
    }

    walk(rootEntries, 1);
    return found;
  }

  Future<String?> _bundleIdOf(String appPath) async {
    var info = '$appPath/Contents/Info.plist';
    if (FileSystemEntity.typeSync(info, followLinks: false) !=
        FileSystemEntityType.file) {
      // iOS/iPadOS apps on Apple Silicon have no Contents/ at all; the real
      // plist sits under Wrapper/<name>.app/Info.plist instead.
      final wrapperDir = Directory('$appPath/Wrapper');
      String? wrapped;
      try {
        for (final entity in wrapperDir.listSync(followLinks: false)) {
          if (entity is Directory && entity.path.endsWith('.app')) {
            final candidate = '${entity.path}/Info.plist';
            if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
                FileSystemEntityType.file) {
              wrapped = candidate;
              break;
            }
          }
        }
      } on FileSystemException {
        return null;
      }
      if (wrapped == null) return null;
      info = wrapped;
    }

    final result = await _probe.run('plutil', [
      '-extract',
      'CFBundleIdentifier',
      'raw',
      info,
    ]);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    return (value == null || value.isEmpty || value == '(null)') ? null : value;
  }
}
