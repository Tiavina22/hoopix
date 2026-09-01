import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Proposes the process-guarded profile-level caches of `clean_browsers`
/// (`lib/clean/user.sh`) — Chrome, Arc, Dia, Brave, Vivaldi and Firefox
/// each keep Code Cache / GPUCache / DawnCache / shader-cache /
/// component-CRX / crash-report leaves under a per-profile
/// `Application Support` tree that Mole only ever touches while the owning
/// browser is closed. [CleanSectionsLocalDataSource]'s own `_browsersTargets`
/// stays pure filesystem enumeration on purpose, so this lives in its own
/// class the way [DeveloperToolsLocalDataSource] does — but shares the
/// same `Browsers` section name; [BuildCleanPlan] groups candidates by
/// that string, not by which class proposed them.
///
/// Firefox's `~/Library/Caches/Firefox` is blanket-protected as a
/// top-level Caches directory (verified against `shouldProtectPath`, the
/// same check used throughout this feature), so `userEssentials` can
/// never reach it — it is included here rather than left as "redundant".
/// Dia's analogous `~/Library/Caches/Dia/User Data/*/{Cache,Code Cache}`
/// is not blanket-protected, so `userEssentials` already sweeps the whole
/// `Dia` directory whole; those two lines are deliberately left out here
/// to avoid double-counting.
///
/// Chrome and Firefox each get a second guard check immediately before
/// their own removal, via [CleanSectionTargets.recheckProcessGuards] —
/// mirrors Mole's `_clean_chrome_profile_caches_guarded` /
/// `_clean_firefox_caches_guarded`, which recheck the same way right
/// before deleting. Arc, Dia, Brave and Vivaldi only check once in Mole
/// too, so their targets carry no recheck here either.
///
/// Not ported: the Chrome/Edge/Brave old-version pruners — their own
/// evidence chain, left for a focused pass of its own.
class BrowserProfileCachesLocalDataSource {
  BrowserProfileCachesLocalDataSource({
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

  static const _chromeRecheck = ProcessRecheck(
    exactNames: ['Google Chrome', 'Google Chrome Helper'],
    patterns: ['/Google Chrome.app/'],
  );
  static const _firefoxRecheck = ProcessRecheck(exactNames: ['Firefox']);

  Future<CleanSectionTargets> enumerate() async {
    final chrome = await _chromeTargets();
    final firefox = await _firefoxTargets();
    final targets = <String>[
      ...chrome,
      ...await _arcTargets(),
      ...await _diaTargets(),
      ...await _braveTargets(),
      ...await _vivaldiTargets(),
      ...firefox,
    ];
    return CleanSectionTargets(
      CleanSectionsLocalDataSource.browsers,
      targets,
      recheckProcessGuards: {
        for (final path in chrome) path: _chromeRecheck,
        for (final path in firefox) path: _firefoxRecheck,
      },
    );
  }

  Future<List<String>> _chromeTargets() async {
    final root = '$home/Library/Application Support/Google/Chrome';
    if (!await _clearToClean(
      root: root,
      exactNames: ['Google Chrome', 'Google Chrome Helper'],
      patterns: ['/Google Chrome.app/'],
    )) {
      return const [];
    }
    return [
      ..._perProfileLeaves(root, [
        'Application Cache',
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        'GraphiteDawnCache',
      ]),
      ..._topLevelLeaves(root, [
        'component_crx_cache',
        'ShaderCache',
        'GrShaderCache',
        'GraphiteDawnCache',
        'Crashpad/completed',
        'OptGuideOnDeviceModel',
        'OptGuideOnDeviceClassifierModel',
        'optimization_guide_model_store',
      ]),
    ];
  }

  Future<List<String>> _arcTargets() async {
    final root = '$home/Library/Application Support/Arc';
    if (!await _clearToClean(root: root, exactNames: ['Arc'])) return const [];

    final userData = '$root/User Data';
    return [
      ..._perProfileLeaves(root, [
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        'GraphiteDawnCache',
      ]),
      ..._topLevelLeaves(root, [
        'ShaderCache',
        'GrShaderCache',
        'GraphiteDawnCache',
        'Crashpad/completed',
      ]),
      ..._perProfileLeaves(userData, [
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        'GraphiteDawnCache',
      ]),
      ..._topLevelLeaves(userData, [
        'ShaderCache',
        'GrShaderCache',
        'GraphiteDawnCache',
        'component_crx_cache',
        'extensions_crx_cache',
        'Crashpad/completed',
      ]),
    ];
  }

  Future<List<String>> _diaTargets() async {
    final root = '$home/Library/Application Support/Dia';
    if (!await _clearToClean(root: root, exactNames: ['Dia'])) return const [];

    final userData = '$root/User Data';
    return [
      ..._topLevelLeaves(userData, [
        'GraphiteDawnCache',
        'GPUPersistentCache',
        'component_crx_cache',
        'extensions_crx_cache',
      ]),
      ..._perProfileLeaves(userData, [
        'DawnGraphiteCache',
        'DawnWebGPUCache',
        'GPUCache',
      ]),
    ];
  }

  Future<List<String>> _braveTargets() async {
    final root =
        '$home/Library/Application Support/BraveSoftware/Brave-Browser';
    if (!await _clearToClean(root: root, exactNames: ['Brave Browser'])) {
      return const [];
    }

    return [
      ..._perProfileLeaves(root, [
        'Application Cache',
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        'GraphiteDawnCache',
      ]),
      ..._topLevelLeaves(root, [
        'component_crx_cache',
        'ShaderCache',
        'GrShaderCache',
        'GraphiteDawnCache',
        'Crashpad/completed',
      ]),
    ];
  }

  Future<List<String>> _vivaldiTargets() async {
    final root = '$home/Library/Application Support/Vivaldi';
    if (!await _clearToClean(root: root, exactNames: ['Vivaldi'])) {
      return const [];
    }

    return [
      ..._perProfileLeaves(root, [
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        'GraphiteDawnCache',
      ]),
      ..._topLevelLeaves(root, [
        'ShaderCache',
        'GrShaderCache',
        'GraphiteDawnCache',
        'Crashpad/completed',
      ]),
    ];
  }

  Future<List<String>> _firefoxTargets() async {
    final liveness = await _guard.check(exactNames: ['Firefox']);
    if (liveness != ProcessLiveness.notRunning) return const [];

    return [
      ..._childrenOf('$home/Library/Caches/Firefox'),
      ..._perProfileLeaves(
        '$home/Library/Application Support/Firefox/Profiles',
        ['cache2'],
      ),
    ];
  }

  /// True only when [root] exists and [ProcessGuard] confirms none of
  /// [exactNames]/[patterns] are running — anything else (not installed,
  /// running, or a probe that could not tell) proposes nothing.
  Future<bool> _clearToClean({
    required String root,
    List<String> exactNames = const [],
    List<String> patterns = const [],
  }) async {
    if (!_isRealDirectory(root)) return false;
    final liveness = await _guard.check(
      exactNames: exactNames,
      patterns: patterns,
    );
    return liveness == ProcessLiveness.notRunning;
  }

  /// `<root>/<profile>/<leaf>` for every real subdirectory of [root], for
  /// each name in [leaves].
  List<String> _perProfileLeaves(String root, List<String> leaves) => [
    for (final profile in _realDirectoriesOf(root))
      for (final leaf in leaves) ..._childrenOf('$profile/$leaf'),
  ];

  /// `<root>/<leaf>` directly, for each name in [leaves].
  List<String> _topLevelLeaves(String root, List<String> leaves) => [
    for (final leaf in leaves) ..._childrenOf('$root/$leaf'),
  ];

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
}
