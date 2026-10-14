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
/// pnpm's own store prune (`clean_pnpm_stores`) is ported separately, in
/// `PnpmStoreLocalDataSource` — it needs a real subprocess round trip to
/// resolve the store path, not just a `--version` probe.
///
/// An owner command cleans whatever root its tool is configured for, not
/// the directory hoopix happens to show, so npm and bun are asked first
/// (`npm config get cache`, `bun pm cache`) exactly as Mole does: that
/// reported root is the candidate, and the whitelist and protection rules
/// apply to it. Each one is asked again right before its command runs
/// ([stillOwnerRoot]); a tool that now reports a different root is
/// refused rather than trusted.
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

  /// Name [stillOwnerRoot] to `CleanRepositoryImpl`, through
  /// [CleanCandidate.revalidatorKey].
  static const npmRevalidatorKey = 'npm-cache-root';
  static const bunRevalidatorKey = 'bun-cache-root';

  static const _npmRootQuery = ['npm', 'config', 'get', 'cache'];
  static const _bunRootQuery = ['bun', 'pm', 'cache'];

  Future<CleanSectionTargets> enumerate() async {
    final paths = <String>[];
    final ownerCommands = <String, List<String>>{};
    final revalidatorKeys = <String, String>{};

    await _addNpm(paths, ownerCommands, revalidatorKeys);
    await _addCorepack(paths, ownerCommands);
    await _addBun(paths, ownerCommands, revalidatorKeys);
    paths.addAll(_childrenOf('$home/.tnpm/_cacache'));
    paths.addAll(_childrenOf('$home/.tnpm/_logs'));
    paths.addAll(_childrenOf('$home/.yarn/cache'));
    paths.addAll(_childrenOf('$home/Library/Caches/Yarn'));

    return CleanSectionTargets(
      developerTools,
      paths,
      ownerCommands: ownerCommands,
      revalidatorKeys: revalidatorKeys,
    );
  }

  /// Whether [path] is still the root its tool reports, asked again at the
  /// moment its owner command would run.
  Future<bool> stillOwnerRoot(String path, String key) async {
    final query = switch (key) {
      npmRevalidatorKey => _npmRootQuery,
      bunRevalidatorKey => _bunRootQuery,
      _ => null,
    };
    if (query == null) return false;
    final root = await _reportedRoot(query);
    return root != null && _samePlace(root, path);
  }

  /// Port of Mole's `clean_dev_npm`: `npm cache clean --force` on the root
  /// npm reports, only when npm runs at all — otherwise Mole leaves the
  /// whole cache root for manual review, not a filesystem sweep, since
  /// without npm nothing can tell a live index from garbage. The residual
  /// leaves the command never removes are swept under the default root,
  /// and under the reported one too when it is somewhere else.
  Future<void> _addNpm(
    List<String> paths,
    Map<String, List<String>> ownerCommands,
    Map<String, String> revalidatorKeys,
  ) async {
    final defaultCache = '$home/.npm';
    var roots = [defaultCache];
    if (await _available('npm')) {
      final root = await _reportedRoot(_npmRootQuery) ?? defaultCache;
      if (!_isUnsafeRoot(root) && _isRealDirectory(root)) {
        paths.add(root);
        ownerCommands[root] = const ['npm', 'cache', 'clean', '--force'];
        revalidatorKeys[root] = npmRevalidatorKey;
      }
      if (!_samePlace(root, defaultCache) && !_isUnsafeRoot(root)) {
        roots = [defaultCache, root];
      }
    }
    for (final root in roots) {
      for (final leaf in ['_cacache', '_npx', '_logs', '_prebuilds']) {
        paths.addAll(_childrenOf('$root/$leaf'));
      }
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

  /// Port of the bun half of `clean_dev_npm`: `bun pm cache rm` on the
  /// root bun reports; a default cache left behind after bun moved
  /// elsewhere is swept as orphaned, and without bun the default cache is
  /// swept directly.
  Future<void> _addBun(
    List<String> paths,
    Map<String, List<String>> ownerCommands,
    Map<String, String> revalidatorKeys,
  ) async {
    final defaultCache = '$home/.bun/install/cache';
    if (!await _available('bun')) {
      paths.addAll(_childrenOf(defaultCache));
      return;
    }

    final root = await _reportedRoot(_bunRootQuery) ?? defaultCache;
    if (!_isUnsafeRoot(root) && _isRealDirectory(root)) {
      paths.add(root);
      ownerCommands[root] = const ['bun', 'pm', 'cache', 'rm'];
      revalidatorKeys[root] = bunRevalidatorKey;
    }
    if (!_samePlace(root, defaultCache)) {
      paths.addAll(_childrenOf(defaultCache));
    }
  }

  /// The absolute root a tool prints for [query], or null when it cannot
  /// say: not installed, timed out, or an answer that is not a path.
  Future<String?> _reportedRoot(List<String> query) async {
    final result = await _probe.run(query.first, query.sublist(1));
    if (!result.isSuccess) return null;
    final lines = result.stdout!.trim().split('\n');
    final root = lines.last.trim();
    if (!root.startsWith('/')) return null;
    return root.length > 1 && root.endsWith('/')
        ? root.substring(0, root.length - 1)
        : root;
  }

  /// A root no cache command may ever be pointed at: home itself, its
  /// Library, or the whole disk — Mole's own unsafe-root guard.
  bool _isUnsafeRoot(String root) =>
      root == '/' || root == home || root == '$home/Library';

  /// The same directory once symlinks are resolved, as Mole compares with
  /// `pwd -P`; spelling alone when either cannot be resolved.
  bool _samePlace(String a, String b) {
    if (a == b) return true;
    try {
      return _directory(a).resolveSymbolicLinksSync() ==
          _directory(b).resolveSymbolicLinksSync();
    } on FileSystemException {
      return false;
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
