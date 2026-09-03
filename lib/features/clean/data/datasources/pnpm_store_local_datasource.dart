import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports `clean_pnpm_stores` (`lib/clean/dev.sh`, issue #1370): pnpm's own
/// `store prune` reclaims unreferenced package versions from its content-
/// addressable store, whose actual location on disk is only known by
/// asking an installed pnpm binary — never assumed from a fixed default
/// path, since `pnpm config set store-dir` can move it anywhere. Shares
/// [DeveloperToolsLocalDataSource.developerTools]'s section name, the same
/// class npm/corepack/bun's own owner commands live in; this lives
/// separately only because resolving a store path needs a real subprocess
/// round trip per candidate binary, not just a `--version` probe.
///
/// Every candidate binary — the one resolved from `PATH`, plus every
/// `mise`-installed version under `~/.local/share/mise/installs/pnpm` — is
/// tried in turn. `store prune` runs once per distinct resolved store path,
/// not once per binary: two pnpm versions commonly share one global store,
/// and pruning it twice would be wasted work, not a correctness issue.
///
/// Only proposed while no process matches Mole's own busy pattern —
/// `pgrep -f` against `(^|/)pnpm(\.cjs)?([[:space:]]|$)`, which catches
/// Corepack- and npm-installed pnpm (invoked as `node .../pnpm.cjs`) that a
/// plain `-x pnpm` name check would miss. Like npm/corepack/bun, Mole
/// checks this once and does not recheck before running `store prune`
/// (`clean_tool_cache` has no guard parameter), so no
/// [CleanSectionTargets.recheckProcessGuards] entry is carried here either.
class PnpmStoreLocalDataSource {
  PnpmStoreLocalDataSource({
    required this.home,
    ProcessGuard? guard,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessGuard _guard;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  static const _busyPattern = r'(^|/)pnpm(\.cjs)?([[:space:]]|$)';

  Future<CleanSectionTargets> enumerate() async {
    if (await _guard.check(patterns: [_busyPattern]) !=
        ProcessLiveness.notRunning) {
      return _empty();
    }

    final paths = <String>[];
    final ownerCommands = <String, List<String>>{};
    final seenStores = <String>{};

    for (final bin in _candidateBinaries()) {
      if (!await _usable(bin)) continue;

      final storePath = await _storePath(bin);
      if (storePath == null || !_isSafeStorePath(storePath)) continue;
      final normalized = storePath.endsWith('/')
          ? storePath.substring(0, storePath.length - 1)
          : storePath;
      if (!seenStores.add(normalized)) continue;

      paths.add(normalized);
      ownerCommands[normalized] = [
        'env',
        'COREPACK_ENABLE_DOWNLOAD_PROMPT=0',
        bin,
        'store',
        'prune',
      ];
    }

    return CleanSectionTargets(
      DeveloperToolsLocalDataSource.developerTools,
      paths,
      ownerCommands: ownerCommands,
    );
  }

  CleanSectionTargets _empty() => const CleanSectionTargets(
    DeveloperToolsLocalDataSource.developerTools,
    [],
  );

  /// The bare `pnpm` name (resolved through `PATH` the same way a shell
  /// would, by the OS exec search `Process.start` already does) plus every
  /// executable `pnpm` under a `mise`-installed version directory. A
  /// binary that turns out not to run is filtered by [_usable], not here.
  List<String> _candidateBinaries() => [
    'pnpm',
    for (final versionDir in _realDirectoriesOf(
      '$home/.local/share/mise/installs/pnpm',
    ))
      if (_isExecutable('$versionDir/pnpm')) '$versionDir/pnpm',
  ];

  /// Never lets Corepack prompt to download a different major version.
  Future<bool> _usable(String bin) async {
    final result = await _probe.run('env', [
      'COREPACK_ENABLE_DOWNLOAD_PROMPT=0',
      bin,
      '--version',
    ]);
    return result.isSuccess;
  }

  Future<String?> _storePath(String bin) async {
    final result = await _probe.run('env', [
      'COREPACK_ENABLE_DOWNLOAD_PROMPT=0',
      bin,
      'store',
      'path',
    ]);
    if (!result.isSuccess) return null;
    final output = result.stdout?.trim();
    return (output == null || output.isEmpty) ? null : output;
  }

  bool _isSafeStorePath(String path) {
    if (path.isEmpty || !path.startsWith('/')) return false;
    if (path.contains('/../') || path.endsWith('/..') || path == '..') {
      return false;
    }
    if (path.contains('\n') || path.contains('\r')) return false;
    return true;
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

  bool _isExecutable(String path) {
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    try {
      // Any owner/group/other execute bit (0o111).
      return File(path).statSync().mode & 0x49 != 0;
    } on FileSystemException {
      return false;
    }
  }
}
