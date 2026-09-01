import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Proposes the two narrow, verified-orphan targets from Mole's
/// `lib/clean/apps.sh` that hoopix's other sections cannot already reach:
/// leftover Claude VM bundles (`clean_orphaned_app_data`) and orphaned
/// CleanMyMac X container stubs (`clean_orphaned_container_stubs`).
///
/// Deliberately not a general orphan-detection engine. Mole's other
/// `clean_orphaned_app_data` candidate sources — bundle-id-named entries
/// under `Library/Caches`, `Library/Logs`, `Saved Application State` — are
/// the exact same top-level directories [CleanSectionsLocalDataSource]'s
/// `userEssentials` and `appCaches` sections already sweep unconditionally.
/// Whether an app is still installed changes nothing about whether *those*
/// sections clean its cache; the funnel's cross-section dedup on identical
/// paths means proposing the same bundle-id directory a second time here
/// adds nothing. `clean_orphaned_system_services` requires root — a
/// non-interactive sudo probe gates the whole function before it looks at
/// anything — and is deferred alongside the System section's privilege
/// escalation work.
class AppLeftoversLocalDataSource {
  AppLeftoversLocalDataSource({
    required this.home,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  static const appLeftovers = 'App leftovers';

  Future<CleanSectionTargets> enumerate() async {
    final targets = <String>[
      ...await _claudeVmBundleTargets(),
      ...await _cleanMyMacStubTargets(),
    ];
    return CleanSectionTargets(appLeftovers, targets);
  }

  /// Port of the Claude VM bundle branch of `clean_orphaned_app_data`: an
  /// `*.bundle` under `Application Support/Claude` is proposed only when
  /// Claude is not currently running, Claude Desktop is not installed
  /// anywhere Spotlight can see, and the bundle has sat untouched for at
  /// least 7 days — the same threshold Mole uses for this specific check
  /// (shorter than the 30-day default elsewhere, because a VM bundle is a
  /// much larger, much more disruptive thing to be wrong about).
  Future<List<String>> _claudeVmBundleTargets() async {
    final claudeSupport = '$home/Library/Application Support/Claude';
    if (!_isRealDirectory(claudeSupport)) return const [];

    if (await _isProcessRunning('Claude')) return const [];
    if (await _isBundleInstalled('com.anthropic.claudefordesktop')) {
      return const [];
    }

    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final targets = <String>[];
    for (final bundle in _bundleDirsUnder(claudeSupport, maxDepth: 3)) {
      final modified = _modified(bundle);
      if (modified != null && modified.isBefore(cutoff)) targets.add(bundle);
    }
    return targets;
  }

  List<String> _bundleDirsUnder(String root, {required int maxDepth}) {
    final targets = <String>[];
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
        if (entity.path.endsWith('.bundle')) targets.add(entity.path);
        walk(entity.path, depth + 1);
      }
    }

    walk(root, 1);
    return targets..sort();
  }

  /// Port of `clean_orphaned_container_stubs`, narrowed to its one
  /// hardcoded target (CleanMyMac X, direct or MAS/TeamID-prefixed): a
  /// container is eligible only when it holds nothing but
  /// containermanagerd's own metadata file — never a container with any
  /// other content — and CleanMyMac X cannot be found at any of its known
  /// install locations or via Spotlight.
  Future<List<String>> _cleanMyMacStubTargets() async {
    final containersDir = '$home/Library/Containers';
    if (!_isRealDirectory(containersDir)) return const [];

    final targets = <String>[];
    for (final container in _realDirectoriesOf(containersDir)) {
      final id = container.split('/').last;
      final looksLikeCleanMyMac =
          id.startsWith('com.macpaw.CleanMyMac') ||
          id.contains('.com.macpaw.CleanMyMac');
      if (!looksLikeCleanMyMac) continue;
      if (!_isStubContainer(container)) continue;
      if (await _cleanMyMacAppExists(id)) continue;
      targets.add(container);
    }
    return targets;
  }

  static const _containerMetadataName =
      '.com.apple.containermanagerd.metadata.plist';

  /// True only when [container]'s sole entry is containermanagerd's own
  /// metadata file — the narrow shape that authorizes touching it at all.
  bool _isStubContainer(String container) {
    if (!_isRealFile('$container/$_containerMetadataName')) return false;
    final entries = _childrenOf(container);
    return entries.length == 1 &&
        entries.single.split('/').last == _containerMetadataName;
  }

  Future<bool> _cleanMyMacAppExists(String bundleId) async {
    const appName = 'CleanMyMac X.app';
    for (final path in [
      '/Applications/$appName',
      '$home/Applications/$appName',
      '/Applications/Setapp/$appName',
      '$home/Library/Application Support/Setapp/Applications/$appName',
    ]) {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return true;
      }
    }
    return _isBundleInstalled(bundleId);
  }

  /// Whether Spotlight can find an app whose bundle id is [bundleId]. A
  /// failed or timed-out probe counts as installed — a stalled Spotlight
  /// index must never turn a live app's data into an orphan.
  Future<bool> _isBundleInstalled(String bundleId) async {
    final result = await _probe.run('mdfind', [
      "kMDItemCFBundleIdentifier == '$bundleId'",
    ]);
    if (!result.isSuccess) return true;
    return (result.stdout ?? '').trim().isNotEmpty;
  }

  Future<bool> _isProcessRunning(String name) async {
    final result = await _probe.run('pgrep', ['-x', name]);
    return result.isSuccess;
  }

  DateTime? _modified(String path) {
    try {
      return FileStat.statSync(path).modified;
    } on FileSystemException {
      return null;
    }
  }

  List<String> _childrenOf(String path) {
    try {
      return [
        for (final entity in _directory(path).listSync(followLinks: false))
          entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  List<String> _realDirectoriesOf(String path) {
    try {
      return [
        for (final entity in _directory(path).listSync(followLinks: false))
          if (entity is Directory) entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;

  bool _isRealFile(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.file;
}
