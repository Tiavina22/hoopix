import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports `clean_tart_caches` (`lib/clean/user.sh`): `tart` reclaims its own
/// cache through `tart prune`, the owner-command mechanism, but only when
/// Tart itself is on PATH and confirmed not running — a VM in active use
/// must not have its cache pruned out from under it. Shares
/// [CleanSectionsLocalDataSource.virtualization]'s section name, the same
/// reason [UtmCachesLocalDataSource] shares it.
///
/// Mole re-checks the same process guard twice: once before showing the
/// preview line, again immediately before actually running `tart prune`,
/// closing the window between scan and approval. [enumerate] is the first
/// check; the second is [CleanSectionTargets.recheckProcessGuards], applied
/// by `CleanRepositoryImpl` at the moment it runs the command.
///
/// `--older-than 30` matches the shared 30-day orphan-age default used
/// elsewhere in this feature (`MOLE_ORPHAN_AGE_DAYS` in Mole).
class TartCacheLocalDataSource {
  TartCacheLocalDataSource({
    required this.home,
    ProcessGuard? guard,
    ProcessRunner? probe,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5));

  final String home;
  final ProcessGuard _guard;
  final ProcessRunner _probe;

  static const _pruneCommand = [
    'tart',
    'prune',
    '--entries',
    'caches',
    '--older-than',
    '30',
  ];

  Future<CleanSectionTargets> enumerate() async {
    final cacheRoot = '$home/.tart/cache';
    if (!_isRealDirectory(cacheRoot)) return _empty();
    if (!await _available('tart')) return _empty();

    final liveness = await _guard.check(exactNames: ['tart']);
    if (liveness != ProcessLiveness.notRunning) return _empty();

    return CleanSectionTargets(
      CleanSectionsLocalDataSource.virtualization,
      [cacheRoot],
      ownerCommands: {cacheRoot: _pruneCommand},
      recheckProcessGuards: {
        cacheRoot: const ProcessRecheck(exactNames: ['tart']),
      },
    );
  }

  CleanSectionTargets _empty() => const CleanSectionTargets(
    CleanSectionsLocalDataSource.virtualization,
    [],
  );

  Future<bool> _available(String executable) async {
    final result = await _probe.run(executable, const ['--version']);
    return result.isSuccess;
  }

  bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;
}
