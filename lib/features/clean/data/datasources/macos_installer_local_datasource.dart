import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/macos_installer_probe.dart';
import 'package:hoopix/features/clean/data/datasources/system_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports the macOS-installer-apps slice of `clean_deep_system`
/// (`lib/clean/system.sh`): a stale `/Applications/Install macOS *.app`
/// left behind by Software Update, removed through the same
/// administrator-privileges channel [SystemLocalDataSource] uses. Shares
/// its `System` section name.
///
/// Eligibility mirrors `macos_installer_candidate_still_eligible` exactly:
/// - at least 14 days old, by the bundle's own `mtime`;
/// - Software Update reports no pending update — a read failure or
///   anything but an explicitly empty list is treated as pending
///   ([MacosInstallerProbe.softwareUpdatePending]'s fail-closed contract);
/// - the installer process itself is not running (`pgrep -f <path>`);
/// - the installer's own `Contents/Info.plist` names a major macOS version
///   different from the one currently running — recovery safety: never
///   remove the installer for the OS the machine is actually running,
///   even if it happens to be old.
///
/// Mole rechecks this whole eligibility function a second time between its
/// two probes, to close the race a size measurement can open. hoopix's own
/// gap is larger — every eligible candidate gets sized, then the user
/// reviews the whole plan, before approval — so the full recheck happens
/// once, at the true deletion boundary: [stillEligible] re-reads the
/// bundle's identity and Software Update's state, and
/// [CleanCandidate.recheckProcessGuard] re-checks the installer process,
/// both applied by `CleanRepositoryImpl` immediately before deleting.
class MacosInstallerLocalDataSource {
  MacosInstallerLocalDataSource({
    MacosInstallerProbe? probe,
    ProcessGuard? guard,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const MacosInstallerProbe(),
       _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _directory = directory ?? Directory.new;

  final MacosInstallerProbe _probe;
  final ProcessGuard _guard;
  final Directory Function(String path) _directory;

  static const _minimumAgeDays = 14;

  /// Names this datasource's own [stillEligible] to `CleanRepositoryImpl`,
  /// through [CleanCandidate.revalidatorKey].
  static const revalidatorKey = 'macos-installer';

  /// The identity each proposed installer reported when it was found
  /// eligible, so [stillEligible] can prove it is still the same bundle.
  final _identitiesAtScan = <String, String>{};

  Future<CleanSectionTargets> enumerate() async {
    final currentMajor = await _probe.currentMajorVersion();
    if (currentMajor == null) return _empty();

    final paths = <String>[];
    final recheckProcessGuards = <String, ProcessRecheck>{};
    _identitiesAtScan.clear();

    for (final appPath in _candidateInstallers()) {
      final identity = await _probe.identity(appPath);
      if (identity == null) continue;

      final mtime = _probe.mtimeOf(identity);
      if (mtime == null) continue;
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if ((nowSeconds - mtime) ~/ 86400 < _minimumAgeDays) continue;

      if (await _probe.softwareUpdatePending()) continue;

      if (await _guard.check(patterns: [appPath]) !=
          ProcessLiveness.notRunning) {
        continue;
      }

      final installerMajor = await _probe.installerMajorVersion(appPath);
      if (installerMajor == null || installerMajor == currentMajor) continue;

      paths.add(appPath);
      recheckProcessGuards[appPath] = ProcessRecheck(patterns: [appPath]);
      _identitiesAtScan[appPath] = identity;
    }

    return CleanSectionTargets(
      SystemLocalDataSource.system,
      paths,
      privilegedDeletionPaths: paths.toSet(),
      recheckProcessGuards: recheckProcessGuards,
      revalidatorKeys: {for (final path in paths) path: revalidatorKey},
    );
  }

  /// Whether [path] is still the exact bundle this datasource found
  /// eligible, with Software Update still reporting nothing pending. Both
  /// can change between the scan and the user approving the plan, and both
  /// are fail-closed: an unknown answer keeps the installer.
  Future<bool> stillEligible(String path) async {
    final expected = _identitiesAtScan[path];
    if (expected == null) return false;
    if (await _probe.identity(path) != expected) return false;
    if (await _probe.softwareUpdatePending()) return false;
    return true;
  }

  CleanSectionTargets _empty() =>
      const CleanSectionTargets(SystemLocalDataSource.system, []);

  /// Every real, non-symlink `/Applications/Install macOS *.app` — the
  /// exact basename shape `PrivilegedDeleteChannel.swift`'s own native-side
  /// allowlist checks independently.
  List<String> _candidateInstallers() {
    const applicationsDir = '/Applications';
    try {
      return [
        for (final entity in _directory(
          applicationsDir,
        ).listSync(followLinks: false))
          if (entity is Directory &&
              _isInstallerName(entity.path.split('/').last))
            entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  bool _isInstallerName(String name) =>
      name.startsWith('Install macOS ') && name.endsWith('.app');
}
