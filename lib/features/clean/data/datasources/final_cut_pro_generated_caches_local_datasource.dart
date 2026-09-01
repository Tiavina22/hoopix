import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports `clean_final_cut_pro_generated_caches` (`lib/clean/app_caches.sh`,
/// issue #843): inside every `~/Movies/*.fcpbundle` library, Final Cut Pro
/// keeps regenerable render and proxy media next to the user's actual
/// project data, at a location standard cache cleanup never looks at.
/// Shares [AppsAndUtilitiesLocalDataSource.appsAndUtilities]'s section
/// name, the same reason [XcodeCachesLocalDataSource] shares Developer
/// tools'.
///
/// Safety scope, matching Mole's own first pass exactly:
/// - only `~/Movies/*.fcpbundle` libraries, found up to 4 directories deep
///   (Mole's `find -maxdepth 4`);
/// - within a library, only directories named `High Quality Media` whose
///   immediate parent is `Render Files`, or `Proxy Media` whose immediate
///   parent is `Transcoded Media` — Apple's own documented regenerable
///   render/proxy locations;
/// - `Original Media`, `Analysis Files`, `Motion Templates` and
///   `Final Cut Pro Backups` are never descended into, anywhere they
///   appear. Mole additionally re-checks a found target's path for these
///   four names before deleting it (`final_cut_pro_path_has_protected_component`);
///   here that check would always pass by construction, since pruning
///   already makes it structurally impossible to find a target under one
///   of them, so it is not ported as a separate step.
///
/// Only proposed while Final Cut Pro is confirmed not running, rechecked a
/// second time immediately before removal via
/// [CleanSectionTargets.recheckProcessGuards] — mirrors
/// `_app_cache_safe_clean_guarded`, which Mole routes every one of these
/// targets through.
class FinalCutProGeneratedCachesLocalDataSource {
  FinalCutProGeneratedCachesLocalDataSource({
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

  static const _recheck = ProcessRecheck(
    exactNames: ['Final Cut Pro'],
    patterns: ['/Final Cut Pro.app/'],
  );

  static const _prunedNames = {
    'Original Media',
    'Analysis Files',
    'Motion Templates',
    'Final Cut Pro Backups',
  };

  /// `find`'s own default recursion has no depth cap; this one is a
  /// defensive bound on how deep inside one library the search goes,
  /// matching the generous-but-bounded convention this feature already
  /// uses for unbounded Mole walks (`_containsFileEndingWith`'s maxDepth).
  static const _maxCacheSearchDepth = 10;

  Future<CleanSectionTargets> enumerate() async {
    final targets = _findGeneratedCacheTargets();
    if (targets.isEmpty) return _empty();

    final liveness = await _guard.check(
      exactNames: _recheck.exactNames,
      patterns: _recheck.patterns,
    );
    if (liveness != ProcessLiveness.notRunning) return _empty();

    return CleanSectionTargets(
      AppsAndUtilitiesLocalDataSource.appsAndUtilities,
      targets,
      recheckProcessGuards: {for (final path in targets) path: _recheck},
    );
  }

  CleanSectionTargets _empty() => const CleanSectionTargets(
    AppsAndUtilitiesLocalDataSource.appsAndUtilities,
    [],
  );

  List<String> _findGeneratedCacheTargets() {
    final targets = <String>[];
    for (final library in _findFcpBundles('$home/Movies', maxDepth: 4)) {
      _walkForGeneratedCaches(library, 0, targets);
    }
    return targets..sort();
  }

  /// Every directory under [root] named `*.fcpbundle`, up to [maxDepth]
  /// directories deep, never descending inside one once found.
  List<String> _findFcpBundles(String root, {required int maxDepth}) {
    final found = <String>[];
    void walk(String dir, int depth) {
      if (depth >= maxDepth) return;
      for (final entity in _realDirectoriesOf(dir)) {
        final name = entity.split('/').last;
        if (name.endsWith('.fcpbundle')) {
          found.add(entity);
        } else {
          walk(entity, depth + 1);
        }
      }
    }

    walk(root, 0);
    return found;
  }

  /// Inside one library, every directory named `High Quality Media` under a
  /// `Render Files` parent, or `Proxy Media` under a `Transcoded Media`
  /// parent — pruning [_prunedNames] wherever they appear.
  void _walkForGeneratedCaches(String dir, int depth, List<String> targets) {
    if (depth > _maxCacheSearchDepth) return;
    final parentName = dir.split('/').last;
    for (final entity in _realDirectoriesOf(dir)) {
      final name = entity.split('/').last;
      if (_prunedNames.contains(name)) continue;
      final isRenderTarget =
          name == 'High Quality Media' && parentName == 'Render Files';
      final isProxyTarget =
          name == 'Proxy Media' && parentName == 'Transcoded Media';
      if (isRenderTarget || isProxyTarget) {
        targets.add(entity);
      } else {
        _walkForGeneratedCaches(entity, depth + 1, targets);
      }
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
