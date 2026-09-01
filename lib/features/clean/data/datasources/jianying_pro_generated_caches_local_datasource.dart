import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports `clean_jianying_pro_generated_caches` (`lib/clean/app_caches.sh`,
/// issue #1277): JianyingPro (剪映专业版 / CapCut CN, `com.lemon.lvpro`)
/// keeps heavy generated caches under `~/Movies/JianyingPro/User Data/Cache`
/// instead of `~/Library/Caches`, where standard cleanup never reaches
/// them. Shares [AppsAndUtilitiesLocalDataSource.appsAndUtilities]'s
/// section name, the same one
/// `FinalCutProGeneratedCachesLocalDataSource` uses — Mole groups both
/// under `clean_video_tools`.
///
/// Only the explicit allowlist of regenerable subdirectories Mole
/// verified on a real install is proposed — subtitle-recognition scratch,
/// frame thumbnails, audio waveforms, algorithm scratch, and
/// prerender/remux temp — each proposed as its whole directory, matching
/// Mole. `image/` and `importcache3/` are deliberately excluded: both hold
/// copies of material the user imported, and the encrypted
/// `draft_info.json` cannot prove they are unreferenced. `User Data/Projects`
/// (the user's actual drafts) is never looked at — only the fixed `Cache`
/// leaf under it.
///
/// Only proposed while JianyingPro's main editor process (not its
/// always-resident tray helper) is confirmed not running. Unlike Final Cut
/// Pro, Mole checks this once and does not recheck immediately before
/// deleting (`clean_jianying_pro_generated_caches` calls plain
/// `safe_clean`, not the guarded double-check framework), so no
/// [CleanSectionTargets.recheckProcessGuards] entry is carried here either.
class JianyingProGeneratedCachesLocalDataSource {
  JianyingProGeneratedCachesLocalDataSource({
    required this.home,
    ProcessGuard? guard,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5)));

  final String home;
  final ProcessGuard _guard;

  /// Verified on a real machine (macOS 15.7 Intel, JianyingPro 11.1.0):
  /// removing this set reclaimed ~70GB and the editor recreated every
  /// directory on next launch.
  static const _regenerableSubdirs = [
    'recognize',
    'frameThumbnail',
    'audioWave',
    'AlgorithmCache',
    'ILASDKDB',
    'RemuxCache',
    'prerender',
    'segmentPrerenderCache',
    'MotionBlurCache',
    'ttsTemp',
    'tmp',
  ];

  Future<CleanSectionTargets> enumerate() async {
    final cacheRoot = '$home/Movies/JianyingPro/User Data/Cache';
    if (!_isRealDirectory(cacheRoot)) return _empty();

    // Narrowed to the main executable path so the always-resident
    // menu-bar tray helper (.../Frameworks/VideoFusion-macOSTrayHelper.app/...)
    // does not read as "editor running" and permanently block cleanup.
    final liveness = await _guard.check(
      exactNames: ['VideoFusion-macOS'],
      patterns: ['/VideoFusion-macOS.app/Contents/MacOS/VideoFusion-macOS'],
    );
    if (liveness != ProcessLiveness.notRunning) return _empty();

    final targets = [
      for (final subdir in _regenerableSubdirs)
        if (_isRealDirectory('$cacheRoot/$subdir')) '$cacheRoot/$subdir',
    ];
    return CleanSectionTargets(
      AppsAndUtilitiesLocalDataSource.appsAndUtilities,
      targets,
    );
  }

  CleanSectionTargets _empty() => const CleanSectionTargets(
    AppsAndUtilitiesLocalDataSource.appsAndUtilities,
    [],
  );

  bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;
}
