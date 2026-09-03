import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_cache_refresh` (`lib/optimize/tasks.sh`): resets QuickLook's
/// thumbnail cache and icon services, both fully regenerated on demand, so
/// this deletes them permanently rather than through the Trash — the same
/// distinction Mole's own `safe_remove` (a plain `rm -rf`, not its
/// Trash-routed `mole_delete`) draws for optimize's regenerable caches.
///
/// [shouldProtectPath] blocks all three targets in practice: each basename
/// starts with `com.apple.`, which trips the blanket keyword rule in
/// `shouldProtectData` (step 6/7 of `should_protect_path` in Mole's own
/// `lib/core/app_protection.sh`, ported line for line). Mole's own
/// `opt_cache_refresh` runs the identical `should_protect_path "$target" &&
/// continue` guard before its own `safe_remove`, so this is not a
/// divergence — on real macOS, Mole's task also only ever refreshes
/// QuickLook and never actually removes these three files. The deletion
/// step is kept (rather than dropped) so a future, more specific exception
/// — the way `knownRebuildableCache` already carves one out for Codex — has
/// somewhere to land without another port pass through Mole's source.
class CacheRefreshTask implements OptimizeTaskRunner {
  CacheRefreshTask({
    required this.home,
    ProcessRunner? probe,
    FileSystemEntityType Function(String path)? typeOf,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 10)),
       _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false));

  final String home;
  final ProcessRunner _probe;
  final FileSystemEntityType Function(String path) _typeOf;

  List<String> get _cachePaths => [
    '$home/Library/Caches/com.apple.QuickLook.thumbnailcache',
    '$home/Library/Caches/com.apple.iconservices.store',
    '$home/Library/Caches/com.apple.iconservices',
  ];

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'cache_refresh',
    name: 'Finder Cache Refresh',
    description: 'Refresh QuickLook thumbnails and icon services cache',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    var applied = 0;
    var failed = 0;

    final resetCache = await _probe.run('qlmanage', ['-r', 'cache']);
    resetCache.isSuccess ? applied++ : failed++;
    final restart = await _probe.run('qlmanage', ['-r']);
    restart.isSuccess ? applied++ : failed++;

    for (final path in _cachePaths) {
      final type = _typeOf(path);
      if (type == FileSystemEntityType.notFound) continue;
      if (shouldProtectPath(path, home: home)) continue;

      try {
        if (type == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
        } else {
          await File(path).delete();
        }
        applied++;
      } on FileSystemException {
        failed++;
      }
    }

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: applied, failed: failed),
    );
  }
}
