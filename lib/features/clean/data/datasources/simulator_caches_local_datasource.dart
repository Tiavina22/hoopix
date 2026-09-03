import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/core/process/simctl_probe.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports the Simulator slice of `clean_xcode_tools` (`lib/clean/app_caches.sh`):
/// CoreSimulator's own caches, each device's `data/tmp`, and the
/// CoreSimulator logs. Shares
/// [DeveloperToolsLocalDataSource.developerTools]'s section name.
///
/// The guard here is `_probe_simulator_activity`, which is stronger than
/// the process-name check the rest of the Xcode targets use: a booted
/// device holds live CoreSimulator state with no matching foreground
/// process, so [SimctlProbe] is asked as well. Mole brackets that probe
/// with the same process check on both sides, because listing devices can
/// take several seconds — long enough for a build to start — and this does
/// the same: process, then booted devices, then process again.
///
/// Every candidate carries both halves of that guard for the pre-removal
/// recheck: [CleanCandidate.recheckProcessGuard] for the cheap process
/// half, and [CleanCandidate.revalidatorKey] for the full bracketed probe,
/// matching how Mole routes these through `_app_cache_safe_clean_guarded`
/// with `_simulator_app_cache_delete_guard_allows`.
class SimulatorCachesLocalDataSource {
  SimulatorCachesLocalDataSource({
    required this.home,
    ProcessGuard? guard,
    SimctlProbe? simctl,
    Directory Function(String path)? directory,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _simctl = simctl ?? SimctlProbe(home: home),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessGuard _guard;
  final SimctlProbe _simctl;
  final Directory Function(String path) _directory;

  /// Names this datasource's own [stillEligible] to `CleanRepositoryImpl`.
  static const revalidatorKey = 'simulator-caches';

  /// Port of `_coresimulator_cache_process_running`. `simctl` is on the
  /// list because a scripted simulator session leaves no Simulator.app
  /// window behind; the launchd-managed CoreSimulator services are not,
  /// since they outlive Simulator and prove nothing on their own (#1319).
  static const _recheck = ProcessRecheck(
    exactNames: [
      'Xcode',
      'Simulator',
      'xcodebuild',
      'xctest',
      'XCTRunner',
      'simctl',
    ],
  );

  Future<CleanSectionTargets> enumerate() async {
    final targets = [
      ..._childrenOf('$home/Library/Developer/CoreSimulator/Caches'),
      for (final device in _realDirectoriesOf(
        '$home/Library/Developer/CoreSimulator/Devices',
      ))
        ..._childrenOf('$device/data/tmp'),
      ..._childrenOf('$home/Library/Logs/CoreSimulator'),
    ];
    // Only pay for the probe once there is something to remove, the way
    // Mole gates its own on `mole_cleanup_targets_exist`.
    if (targets.isEmpty) return _empty();

    if (await _simulatorActivity() != ProcessLiveness.notRunning) {
      return _empty();
    }

    return CleanSectionTargets(
      DeveloperToolsLocalDataSource.developerTools,
      targets,
      recheckProcessGuards: {for (final path in targets) path: _recheck},
      revalidatorKeys: {for (final path in targets) path: revalidatorKey},
    );
  }

  /// Re-runs the whole bracketed probe. [path] is not consulted: every
  /// candidate here shares one piece of state — whether the simulator is
  /// active — so any of them being unsafe makes all of them unsafe.
  Future<bool> stillEligible(String path) async =>
      await _simulatorActivity() == ProcessLiveness.notRunning;

  /// Process, then booted devices, then process again. Any step that is
  /// not a confirmed "nothing running" stops the whole probe there.
  Future<ProcessLiveness> _simulatorActivity() async {
    final before = await _guard.check(exactNames: _recheck.exactNames);
    if (before != ProcessLiveness.notRunning) return before;

    final booted = await _simctl.bootedDeviceState();
    if (booted != ProcessLiveness.notRunning) return booted;

    return _guard.check(exactNames: _recheck.exactNames);
  }

  CleanSectionTargets _empty() => const CleanSectionTargets(
    DeveloperToolsLocalDataSource.developerTools,
    [],
  );

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
}
