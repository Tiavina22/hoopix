import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Proposes Developer-tools targets that need a quick, read-only probe of
/// the owning tool first — "is npm even installed" — which
/// [CleanSectionsLocalDataSource] deliberately never does; that one stays
/// pure filesystem enumeration. This is why the two live in separate
/// classes rather than one growing an optional [ProcessRunner].
///
/// Mirrors the guard-free, default-path slice of Mole's `clean_dev_npm`
/// (`lib/clean/dev.sh`): a tool present on PATH has its cache reclaimed
/// through its own cache-clean command, via [CleanSectionTargets.ownerCommands]
/// — `npm cache clean --force` does not touch every leaf npm itself leaves
/// behind, so those residual directories are still swept as plain paths.
/// A tool that is not installed falls back to sweeping its default cache
/// directory directly.
///
/// Not ported: pnpm (`clean_pnpm_stores`) needs multi-binary discovery
/// across Corepack/Volta/global-npm shims plus a live "pnpm busy" process
/// guard hoopix does not have; `npm config get cache` / `bun pm cache`
/// custom-path resolution is skipped in favor of each tool's well-known
/// default, so a user with a relocated cache keeps it out of this sweep.
class DeveloperToolsLocalDataSource {
  DeveloperToolsLocalDataSource({
    required this.home,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  static const developerTools = 'Developer tools';

  Future<CleanSectionTargets> enumerate() async {
    final paths = <String>[];
    final ownerCommands = <String, List<String>>{};

    await _addNpm(paths, ownerCommands);
    await _addCorepack(paths, ownerCommands);
    await _addBun(paths, ownerCommands);
    paths.addAll(_childrenOf('$home/.tnpm/_cacache'));
    paths.addAll(_childrenOf('$home/.tnpm/_logs'));
    paths.addAll(_childrenOf('$home/.yarn/cache'));
    paths.addAll(_childrenOf('$home/Library/Caches/Yarn'));

    return CleanSectionTargets(
      developerTools,
      paths,
      ownerCommands: ownerCommands,
    );
  }

  /// `npm cache clean --force` only when npm is on PATH — otherwise Mole
  /// leaves the whole cache root for manual review, not a filesystem sweep,
  /// since without npm nothing can tell a live index from garbage. The
  /// residual leaves it never removes are swept unconditionally either way.
  Future<void> _addNpm(
    List<String> paths,
    Map<String, List<String>> ownerCommands,
  ) async {
    final npmCache = '$home/.npm';
    if (_isRealDirectory(npmCache) && await _available('npm')) {
      paths.add(npmCache);
      ownerCommands[npmCache] = const ['npm', 'cache', 'clean', '--force'];
    }
    for (final leaf in ['_cacache', '_npx', '_logs', '_prebuilds']) {
      paths.addAll(_childrenOf('$npmCache/$leaf'));
    }
  }

  Future<void> _addCorepack(
    List<String> paths,
    Map<String, List<String>> ownerCommands,
  ) async {
    final configured = Platform.environment['COREPACK_HOME'];
    final corepackHome = (configured != null && configured.startsWith('/'))
        ? configured
        : '$home/.cache/node/corepack';
    // Mirrors Mole's unsafe-root guard: never treat home or Library itself
    // as "the corepack cache".
    if (corepackHome == home || corepackHome == '$home/Library') return;
    if (!_isRealDirectory(corepackHome)) return;

    if (await _available('corepack')) {
      paths.add(corepackHome);
      ownerCommands[corepackHome] = const ['corepack', 'cache', 'clean'];
    } else {
      paths.addAll(_childrenOf(corepackHome));
    }
  }

  Future<void> _addBun(
    List<String> paths,
    Map<String, List<String>> ownerCommands,
  ) async {
    final bunCache = '$home/.bun/install/cache';
    if (!_isRealDirectory(bunCache)) return;

    if (await _available('bun')) {
      paths.add(bunCache);
      ownerCommands[bunCache] = const ['bun', 'pm', 'cache', 'rm'];
    } else {
      paths.addAll(_childrenOf(bunCache));
    }
  }

  Future<bool> _available(String executable) async {
    final result = await _probe.run(executable, const ['--version']);
    return result.isSuccess;
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

  bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;
}
