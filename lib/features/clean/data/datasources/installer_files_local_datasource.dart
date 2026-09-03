import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports `bin/installer.sh`: known-safe installer payloads left behind in
/// Downloads, Desktop, and a handful of other well-known drop points —
/// `.dmg`, `.pkg`, `.mpkg`, `.iso`, `.xip` outright, plus a `.zip` only when
/// its own listing shows an installer payload inside (an `.app`, `.pkg`,
/// `.dmg`, or `.xip` entry among its first 50), the same signal Mole's own
/// `is_installer_zip` uses to avoid flagging an ordinary data archive.
/// Scanned up to two directory levels deep from each root, matching
/// `INSTALLER_SCAN_MAX_DEPTH_DEFAULT`; a file symlink is skipped outright,
/// and a symlinked directory is never descended into (`listSync` with
/// `followLinks: false` reports it as a link, not a directory).
///
/// Unlike Mole's own picker — a dedicated `mo installer` command, never
/// part of its interactive menu — this rides Clean's existing
/// plan/selection/Trash machinery as one more section: the same sizing
/// pass, the same per-item checkbox, and the same race-safe recheck
/// ([stillEligible], by [CleanCandidate.revalidatorKey]) immediately before
/// removal that a stale identity check like this one is for — the file
/// could have been replaced by a fresh download under the same name
/// between the scan and the user approving the plan.
///
/// Not ported: Mole's Homebrew-hash-prefix display stripping and its
/// per-item source badge (Downloads/Desktop/Homebrew/...) — both cosmetic,
/// and `CleanCandidate` carries no slot for either without widening a
/// shared entity for one section's own decoration.
class InstallerFilesLocalDataSource {
  InstallerFilesLocalDataSource({
    required this.home,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 2)),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  static const section = 'Installers';

  /// Names this datasource's own [stillEligible] to `CleanRepositoryImpl`,
  /// through [CleanCandidate.revalidatorKey].
  static const revalidatorKey = 'installer-files';

  static const _maxDepth = 2;
  static const _maxZipEntries = 50;
  static final _zipPayloadPattern = RegExp(r'\.(app|pkg|dmg|xip)(/|$)');
  static const _directExtensions = ['.dmg', '.pkg', '.mpkg', '.iso', '.xip'];

  /// The identity each proposed file reported when it was found eligible,
  /// so [stillEligible] can prove it is still the same file.
  final _identitiesAtScan = <String, String>{};

  List<String> _scanRoots() => [
    '$home/Downloads',
    '$home/Desktop',
    '$home/Documents',
    '$home/Public',
    '$home/Library/Downloads',
    '/Users/Shared',
    '/Users/Shared/Downloads',
    '$home/Library/Caches/Homebrew',
    '$home/Library/Mobile Documents/com~apple~CloudDocs/Downloads',
    '$home/Library/Containers/com.apple.mail/Data/Library/Mail Downloads',
    '$home/Library/Application Support/Telegram Desktop',
    '$home/Downloads/Telegram Desktop',
  ];

  Future<CleanSectionTargets> enumerate() async {
    _identitiesAtScan.clear();

    final found = <String>{};
    for (final root in _scanRoots()) {
      await _scan(root, depth: 0, into: found);
    }

    final paths = <String>[];
    for (final path in found) {
      final identity = await _identity(path);
      if (identity == null) continue;
      paths.add(path);
      _identitiesAtScan[path] = identity;
    }
    paths.sort();

    return CleanSectionTargets(
      section,
      paths,
      revalidatorKeys: {for (final path in paths) path: revalidatorKey},
    );
  }

  /// Whether [path] is still the exact file this datasource found
  /// eligible. Fail-closed: an unrecognized path, or one that no longer
  /// stats to the identity recorded at scan time, is not eligible.
  Future<bool> stillEligible(String path) async {
    final expected = _identitiesAtScan[path];
    if (expected == null) return false;
    return await _identity(path) == expected;
  }

  Future<void> _scan(
    String dir, {
    required int depth,
    required Set<String> into,
  }) async {
    if (depth >= _maxDepth) return;

    final List<FileSystemEntity> entries;
    try {
      entries = _directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      return;
    }

    for (final entity in entries) {
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _scan(entity.path, depth: depth + 1, into: into);
        continue;
      }
      if (type != FileSystemEntityType.file) continue; // skips symlinks too
      if (await _isCandidate(entity.path)) into.add(entity.path);
    }
  }

  Future<bool> _isCandidate(String path) async {
    final lower = path.toLowerCase();
    if (_directExtensions.any(lower.endsWith)) return true;
    if (lower.endsWith('.zip')) return _isInstallerZip(path);
    return false;
  }

  /// First 50 entries of the archive's own listing, checked for an
  /// installer payload — enough to catch a `.app`/`.pkg`/`.dmg`/`.xip` near
  /// the top without reading a very large archive's full listing.
  Future<bool> _isInstallerZip(String path) async {
    var output = (await _probe.run('zipinfo', ['-1', path])).stdout;
    if (output == null || output.trim().isEmpty) {
      output = (await _probe.run('unzip', ['-Z', '-1', path])).stdout;
    }
    if (output == null || output.trim().isEmpty) return false;

    return output
        .split('\n')
        .take(_maxZipEntries)
        .any(_zipPayloadPattern.hasMatch);
  }

  /// `dev:inode:mtime` for [path] — Mole's own cheap proof that a file at a
  /// given path is still the exact file it was last time this ran. Null
  /// when [path] cannot be stat'd at all.
  Future<String?> _identity(String path) async {
    final result = await _probe.run('stat', ['-f%d:%i:%m', path]);
    if (!result.isSuccess) return null;
    final output = result.stdout?.trim();
    return (output == null || output.isEmpty) ? null : output;
  }
}
