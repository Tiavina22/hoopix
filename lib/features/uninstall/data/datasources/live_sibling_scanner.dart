import 'dart:io';

import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_runner.dart';
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
/// Not ported in this pass: `/Volumes/*` enumeration, pkg-receipt
/// non-standard install locations, and the dev:inode:mtime fingerprint
/// capture Mole re-verifies immediately before its own delete call — that
/// fingerprint only matters once an actual deletion path exists, which
/// this port does not have yet. `-ef` (same-inode) self-exclusion is
/// simplified to a path-string comparison.
class LiveSiblingScanner {
  LiveSiblingScanner({
    ProcessRunner? probe,
    Directory Function(String path)? directory,
    Duration? timeout,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _directory = directory ?? Directory.new,
       _timeout = timeout ?? const Duration(seconds: 60);

  final ProcessRunner _probe;
  final Directory Function(String path) _directory;
  final Duration _timeout;

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

    for (final root in _liveAppRoots(home)) {
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

    return inconclusive
        ? LiveSiblingScanResult.inconclusive
        : LiveSiblingScanResult.absent;
  }

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
