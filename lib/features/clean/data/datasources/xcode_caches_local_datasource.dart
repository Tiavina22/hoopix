import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Proposes the Xcode-tooling-guarded slice of `clean_xcode_tools` /
/// `clean_xcode_derived_data` (`lib/clean/app_caches.sh`, called from
/// `clean_developer_tools` — this is Developer tools content, not App
/// caches). Shares [DeveloperToolsLocalDataSource.developerTools]'s
/// section name for the same reason [BrowserProfileCachesLocalDataSource]
/// shares Browsers': the process-liveness dependency belongs in its own
/// class, not bolted onto a class built around simple tool-availability
/// probing.
///
/// `~/Library/Caches/com.apple.dt.Xcode` is blanket-protected as a
/// top-level Caches directory (`com.apple.*`), so `userEssentials` can
/// never reach it; `~/Library/Developer/Xcode/{Products,DerivedData}` sit
/// under a root nothing else in this feature ever looks at. Every
/// DerivedData entry is proposed as its whole project directory, the way
/// Mole does — the funnel underneath still applies per-project protection,
/// whitelist and compiled-model-cache checks.
///
/// Every target here gets a second guard check immediately before its own
/// removal, via [CleanSectionTargets.recheckProcessGuards] — mirrors
/// Mole's `_app_cache_safe_clean_guarded`, which `clean_xcode_tools` and
/// `clean_xcode_derived_data` both route every one of these three targets
/// through, rechecking per item right before deleting (`clean_xcode_derived_data`
/// even names why: "Sizing is timeout-bounded but can still take long
/// enough for a build to start").
///
/// Not ported: Simulator caches
/// (`~/Library/Developer/CoreSimulator/{Caches,Devices/*/data/tmp}`,
/// `~/Library/Logs/CoreSimulator`). Mole's own guard for those is stronger
/// than a process-name check — `_coresimulator_activity_state` also asks
/// `xcrun simctl list devices booted` whether any simulator device is
/// live, since a booted device can hold active CoreSimulator state with no
/// matching foreground process. [ProcessGuard] does not have an
/// `xcrun`/`simctl` equivalent yet, and a plain process-name check alone
/// would be a strictly weaker guard than Mole's — left out rather than
/// shipped with a known gap.
class XcodeCachesLocalDataSource {
  XcodeCachesLocalDataSource({
    required this.home,
    ProcessGuard? guard,
    Directory Function(String path)? directory,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessGuard _guard;
  final Directory Function(String path) _directory;

  /// Port of `xcode_build_tooling_process_state`
  /// (`lib/core/app_protection.sh`).
  static const _xcodeToolingProcesses = [
    'Xcode',
    'xcodebuild',
    'xctest',
    'XCTRunner',
    'XCBBuildService',
    'swift-frontend',
  ];

  Future<CleanSectionTargets> enumerate() async {
    final liveness = await _guard.check(exactNames: _xcodeToolingProcesses);
    if (liveness != ProcessLiveness.notRunning) {
      return const CleanSectionTargets(
        DeveloperToolsLocalDataSource.developerTools,
        [],
      );
    }

    final targets = <String>[
      ..._childrenOf('$home/Library/Caches/com.apple.dt.Xcode'),
      ..._childrenOf('$home/Library/Developer/Xcode/Products'),
      ..._realDirectoriesOf('$home/Library/Developer/Xcode/DerivedData'),
    ];
    final recheck = ProcessRecheck(exactNames: _xcodeToolingProcesses);
    return CleanSectionTargets(
      DeveloperToolsLocalDataSource.developerTools,
      targets,
      recheckProcessGuards: {for (final path in targets) path: recheck},
    );
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
}
