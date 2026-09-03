import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// One Chromium-family browser's four facts, the same four
/// `_clean_chromium_old_versions` (`lib/clean/user.sh`) takes as
/// parameters: everything else about removing its old versions is
/// identical between Chrome, Edge and Brave.
class _ChromiumBrowser {
  const _ChromiumBrowser({
    required this.bundleName,
    required this.framework,
    required this.recheck,
  });

  final String bundleName;
  final String framework;
  final ProcessRecheck recheck;
}

/// Ports `clean_chrome_old_versions` / `clean_edge_old_versions` /
/// `clean_brave_old_versions` (`lib/clean/user.sh`), which are three thin
/// wrappers over one table-driven helper in Mole and are one class here for
/// the same reason: Chrome, Edge and Brave are all Chromium, with the same
/// versioned framework layout (`Contents/Frameworks/<X>.framework/Versions`
/// with a `Current` symlink) and the same keep-rules.
///
/// Shares [CleanSectionsLocalDataSource.browsers]'s section name.
///
/// Two versions are always kept: whatever `Current` points at, and — when
/// it is newer than `Current` by mtime — the newest staged one, which is a
/// freshly downloaded auto-update `Current` will point at on next launch.
/// A `Versions` directory with no `Current` symlink, an unreadable one, or
/// one pointing at a directory that no longer exists is left completely
/// alone: without knowing which version is live, nothing here is safe to
/// remove. An unreadable `Current` mtime counts as epoch zero, so the
/// newest staged version is kept rather than removed — Mole's own
/// `stat ... || echo "0"` fallback lands in the same place.
///
/// Every candidate carries a recheck of its own browser's process guard:
/// Mole rechecks the same probe per directory, on both sides of measuring
/// it, before removing anything.
///
/// Not ported: Mole falls back to `safe_sudo_remove` when a sudo session
/// already happens to be open. hoopix has no ambient sudo session to
/// inherit — its privileged channel is an explicit per-batch prompt over a
/// narrow allowlist — so these go to the Trash like Mole's own
/// no-sudo-session path (`safe_remove`), and an old version owned by root
/// simply fails to move, reported per path.
class ChromiumOldVersionsLocalDataSource {
  ChromiumOldVersionsLocalDataSource({
    required this.home,
    ProcessGuard? guard,
    List<String>? applicationRoots,
    Directory Function(String path)? directory,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _applicationRoots =
           applicationRoots ?? ['/Applications', '$home/Applications'],
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessGuard _guard;
  final List<String> _applicationRoots;
  final Directory Function(String path) _directory;

  static const _browsers = [
    _ChromiumBrowser(
      bundleName: 'Google Chrome.app',
      framework: 'Google Chrome Framework.framework',
      // Chrome also runs under a helper process name, so this is wider
      // than an exact-name check, matching `is_google_chrome_running`.
      recheck: ProcessRecheck(
        exactNames: ['Google Chrome', 'Google Chrome Helper'],
        patterns: ['/Google Chrome.app/'],
      ),
    ),
    _ChromiumBrowser(
      bundleName: 'Microsoft Edge.app',
      framework: 'Microsoft Edge Framework.framework',
      // Exact name only: "Microsoft Edge" must not match Microsoft Teams.
      recheck: ProcessRecheck(exactNames: ['Microsoft Edge']),
    ),
    _ChromiumBrowser(
      bundleName: 'Brave Browser.app',
      framework: 'Brave Browser Framework.framework',
      recheck: ProcessRecheck(exactNames: ['Brave Browser']),
    ),
  ];

  Future<CleanSectionTargets> enumerate() async {
    final paths = <String>[];
    final rechecks = <String, ProcessRecheck>{};

    for (final browser in _browsers) {
      final oldVersions = [
        for (final root in _applicationRoots)
          ..._oldVersionsIn('$root/${browser.bundleName}', browser.framework),
      ];
      // Only ask about the process once there is something to remove, the
      // way Mole gates its own probe behind a non-empty candidate list.
      if (oldVersions.isEmpty) continue;

      final liveness = await _guard.check(
        exactNames: browser.recheck.exactNames,
        patterns: browser.recheck.patterns,
      );
      if (liveness != ProcessLiveness.notRunning) continue;

      for (final versionDir in oldVersions) {
        paths.add(versionDir);
        rechecks[versionDir] = browser.recheck;
      }
    }

    return CleanSectionTargets(
      CleanSectionsLocalDataSource.browsers,
      paths,
      recheckProcessGuards: rechecks,
    );
  }

  /// Every version directory inside [appPath]'s framework that is neither
  /// the live one nor a newer staged update.
  List<String> _oldVersionsIn(String appPath, String framework) {
    if (!_isRealDirectory(appPath)) return const [];
    final versionsDir = '$appPath/Contents/Frameworks/$framework/Versions';
    if (!_isRealDirectory(versionsDir)) return const [];

    final currentVersion = _currentVersionName(versionsDir);
    if (currentVersion == null) return const [];
    // A `Current` pointing at a directory that is gone means the live
    // version cannot be identified — never guess which one to keep.
    if (!_isRealDirectory('$versionsDir/$currentVersion')) return const [];

    final versionDirs = [
      for (final dir in _realDirectoriesOf(versionsDir))
        if (dir.split('/').last != 'Current') dir,
    ];

    final stagedUpdate = _stagedUpdateName(
      versionsDir: versionsDir,
      currentVersion: currentVersion,
      versionDirs: versionDirs,
    );

    return [
      for (final dir in versionDirs)
        if (dir.split('/').last != currentVersion &&
            dir.split('/').last != stagedUpdate)
          dir,
    ];
  }

  /// The basename `Current` resolves to, or null when there is no `Current`
  /// symlink at all or it cannot be read.
  String? _currentVersionName(String versionsDir) {
    final currentLink = '$versionsDir/Current';
    if (FileSystemEntity.typeSync(currentLink, followLinks: false) !=
        FileSystemEntityType.link) {
      return null;
    }
    try {
      final target = Link(currentLink).targetSync();
      final name = target.split('/').last;
      return name.isEmpty ? null : name;
    } on FileSystemException {
      return null;
    }
  }

  /// The newest version by mtime when it is newer than [currentVersion] —
  /// a staged auto-update to keep — or null when nothing is newer.
  String? _stagedUpdateName({
    required String versionsDir,
    required String currentVersion,
    required List<String> versionDirs,
  }) {
    final currentMtime =
        _mtimeOf('$versionsDir/$currentVersion') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    String? newestName;
    DateTime? newestMtime;
    for (final dir in versionDirs) {
      final mtime = _mtimeOf(dir);
      if (mtime == null) continue;
      if (newestMtime == null || mtime.isAfter(newestMtime)) {
        newestMtime = mtime;
        newestName = dir.split('/').last;
      }
    }

    if (newestMtime == null || !newestMtime.isAfter(currentMtime)) return null;
    return newestName;
  }

  DateTime? _mtimeOf(String path) {
    try {
      return _directory(path).statSync().modified;
    } on FileSystemException {
      return null;
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
}
