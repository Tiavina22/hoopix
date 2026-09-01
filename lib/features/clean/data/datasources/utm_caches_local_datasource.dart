import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Proposes the one non-redundant target inside `clean_utm_caches`
/// (`lib/clean/user.sh`): UTM's sandbox temp directory, only while UTM
/// itself is confirmed not running. Shares
/// [CleanSectionsLocalDataSource.virtualization]'s section name, for the
/// same reason [XcodeCachesLocalDataSource] shares Developer tools': the
/// [ProcessGuard] dependency belongs in its own class.
///
/// Mole's `clean_utm_caches` also lists `~/Library/Caches/com.utmapp.UTM/*`
/// and `~/Library/Containers/com.utmapp.UTM/Data/Library/Caches/*`, but
/// neither is ported here: `com.utmapp.UTM` is not blanket-protected
/// (verified against `shouldProtectPath`), so `userEssentials`'s top-level
/// Caches sweep already reaches the first one whole, and the container
/// cache is already reached — unconditionally, with no process guard at
/// all — by [CleanSectionsLocalDataSource]'s generic per-container sweep
/// (`process_container_cache` in Mole, which likewise has no UTM-specific
/// guard). Repeating either here would only double-count size that is
/// already counted elsewhere. `Data/tmp` sits under a root neither sweep
/// looks at, so it is the only target that is genuinely unique to this
/// guard.
class UtmCachesLocalDataSource {
  UtmCachesLocalDataSource({
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

  Future<CleanSectionTargets> enumerate() async {
    final liveness = await _guard.check(exactNames: ['UTM']);
    if (liveness != ProcessLiveness.notRunning) {
      return const CleanSectionTargets(
        CleanSectionsLocalDataSource.virtualization,
        [],
      );
    }

    return CleanSectionTargets(CleanSectionsLocalDataSource.virtualization, [
      ..._childrenOf('$home/Library/Containers/com.utmapp.UTM/Data/tmp'),
    ]);
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
}
