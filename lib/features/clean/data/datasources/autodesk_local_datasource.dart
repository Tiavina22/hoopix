import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// A Fusion version directory that passed the whole evidence chain, with
/// the version its bundle reported.
class _FusionVersionDir {
  const _FusionVersionDir(this.path, this.version);
  final String path;
  final String version;
}

/// Ports Autodesk's two cleanup targets from `clean_3d_tools`
/// (`lib/clean/app_caches.sh`): the `com.autodesk.*` caches, and the old
/// Fusion app bundles its in-app updater leaves under
/// `webdeploy/production` (issue #1438 measured 60GB). Shares
/// [AppsAndUtilitiesLocalDataSource.appsAndUtilities]'s section name.
///
/// Both are gated on nothing Autodesk-related running, using the same wide
/// process list Mole probes (`autodesk_cache_process_state`): the helpers
/// outlive the main window and hold their caches open.
///
/// The Fusion pruner is not a generic Autodesk tree cleanup. A version
/// directory is only eligible with the complete evidence chain intact:
/// - the production root is a real directory whose physical path equals its
///   lexical path, so no symlinked ancestor can redirect the sweep;
/// - the directory is a direct child of that root, named as exactly 40 hex
///   characters, real and not a symlink;
/// - it holds exactly one of `Autodesk Fusion.app` /
///   `Autodesk Fusion 360.app`, with real `Contents`, `MacOS` and
///   `Info.plist` entries;
/// - that bundle's `CFBundleIdentifier` is exactly `com.autodesk.fusion360`,
///   its `CFBundleVersion` is a pure dotted-numeric version, and its
///   `CFBundleExecutable` names a file that really exists and is
///   executable;
/// - its version is strictly older than the current one. Version evidence
///   is stronger than directory mtime, which an updater can preserve or
///   reorder.
/// Everything else — the current version, an equal or newer one, an
/// unrecognized or non-hash directory, a symlink — is kept.
///
/// [stillEligible] re-runs that entire chain immediately before removal,
/// including re-resolving which version is current, because the updater can
/// switch it mid-run. That is [CleanCandidate.revalidatorKey]'s whole
/// purpose here, and it mirrors `_autodesk_fusion_delete_guard_allows`.
///
/// Not ported: Mole can resolve a *Finder alias* at
/// `production/Autodesk Fusion.app` through a JXA/Foundation call. hoopix
/// resolves only a real symlink; an alias file is treated as unresolvable,
/// which keeps every version. Mole's own test and no-auth runs never
/// exercise that branch either — it needs a Fusion-installed Mac.
class AutodeskLocalDataSource {
  AutodeskLocalDataSource({
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

  /// Names this datasource's own [stillEligible] to `CleanRepositoryImpl`.
  static const revalidatorKey = 'autodesk-fusion';

  /// Port of `autodesk_cache_process_state`: the main app plus every
  /// helper that outlives it and keeps SQLite caches open.
  static const _recheck = ProcessRecheck(
    exactNames: [
      'AcCoreConsole',
      'ADPClientService',
      'streamer',
      'Fusion Client Downloader',
      'Fusion 360 Client Downloader',
    ],
    patterns: [
      'com.autodesk.',
      '/AcCoreConsole',
      '/ADPClientService',
      '/streamer',
      'Autodesk Fusion',
      'Fusion 360',
      'Fusion360',
    ],
  );

  static final _hashDirectory = RegExp(r'^[0-9a-f]{40}$');
  static final _numericVersion = RegExp(r'^[0-9]+(\.[0-9]+)*$');

  static const _bundleNames = [
    'Autodesk Fusion.app',
    'Autodesk Fusion 360.app',
  ];

  /// The current version directory and version observed during the scan,
  /// so [stillEligible] can prove the updater has not switched it.
  String? _currentDirAtScan;
  String? _currentVersionAtScan;

  String get _productionDir =>
      '$home/Library/Application Support/Autodesk/webdeploy/production';

  Future<CleanSectionTargets> enumerate() async {
    final cacheTargets = _cacheTargets();
    final fusionTargets = await _fusionOldVersions();
    if (cacheTargets.isEmpty && fusionTargets.isEmpty) return _empty();

    if (await _guard.check(
          exactNames: _recheck.exactNames,
          patterns: _recheck.patterns,
        ) !=
        ProcessLiveness.notRunning) {
      return _empty();
    }

    final paths = [...cacheTargets, ...fusionTargets];
    return CleanSectionTargets(
      AppsAndUtilitiesLocalDataSource.appsAndUtilities,
      paths,
      recheckProcessGuards: {for (final path in paths) path: _recheck},
      // Only the Fusion bundles can stop being eligible between scan and
      // approval; a cache directory has no such state to drift.
      revalidatorKeys: {for (final path in fusionTargets) path: revalidatorKey},
    );
  }

  /// Whether [path] still passes the whole Fusion evidence chain. Anything
  /// unreadable, changed, or no longer older than the current version keeps
  /// the bundle.
  Future<bool> stillEligible(String path) async {
    final productionRoot = _trustedProductionRoot();
    if (productionRoot == null) return false;

    final current = await _resolveCurrentVersion(productionRoot);
    // The updater switching which version is current is exactly what this
    // guard exists to catch.
    if (current == null) return false;
    if (current.path != _currentDirAtScan) return false;
    if (current.version != _currentVersionAtScan) return false;

    if (!_isEligibleVersionDirPath(path, productionRoot, current.path)) {
      return false;
    }

    final candidate = await _versionDirVersion(path);
    if (candidate == null) return false;
    return _isOlder(candidate.version, current.version);
  }

  /// Port of the `~/Library/Caches/com.autodesk.*` sweep: each entry's
  /// children when it has any, else the entry itself. Every one of these
  /// bundle ids is blanket-protected as a top-level Caches directory
  /// (verified against `shouldProtectPath`), so `userEssentials` can never
  /// reach them — this is the only way in, not a redundant repeat.
  List<String> _cacheTargets() {
    final targets = <String>[];
    for (final entry in _childrenOf('$home/Library/Caches')) {
      if (!entry.split('/').last.startsWith('com.autodesk.')) continue;
      final children = _childrenOf(entry);
      targets.addAll(children.isEmpty ? [entry] : children);
    }
    return targets;
  }

  Future<List<String>> _fusionOldVersions() async {
    _currentDirAtScan = null;
    _currentVersionAtScan = null;

    final productionRoot = _trustedProductionRoot();
    if (productionRoot == null) return const [];

    final current = await _resolveCurrentVersion(productionRoot);
    if (current == null) return const [];
    _currentDirAtScan = current.path;
    _currentVersionAtScan = current.version;

    final targets = <String>[];
    for (final dir in _realDirectoriesOf(productionRoot)) {
      if (!_isEligibleVersionDirPath(dir, productionRoot, current.path)) {
        continue;
      }
      final candidate = await _versionDirVersion(dir);
      // An unverified directory is kept, never removed on a guess.
      if (candidate == null) continue;
      if (!_isOlder(candidate.version, current.version)) continue;
      targets.add(dir);
    }
    return targets;
  }

  /// The production root only when it is a real directory that is its own
  /// physical path. A lexical path below Application Support is not
  /// containment when `webdeploy` or `production` redirects elsewhere.
  String? _trustedProductionRoot() {
    final dir = _productionDir;
    if (FileSystemEntity.typeSync(dir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    try {
      final physical = _directory(dir).resolveSymbolicLinksSync();
      return physical == dir ? physical : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Shape-only checks on a candidate directory: a direct, real,
  /// non-symlink 40-hex child of [productionRoot] that is not the current
  /// version.
  bool _isEligibleVersionDirPath(
    String path,
    String productionRoot,
    String currentDir,
  ) {
    if (path == currentDir) return false;
    final name = path.split('/').last;
    if (!_hashDirectory.hasMatch(name)) return false;
    if (path.substring(0, path.length - name.length - 1) != productionRoot) {
      return false;
    }
    return FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.directory;
  }

  /// Resolves `production/Autodesk Fusion.app` to the version directory it
  /// stands for, then reads that directory's version — and re-resolves the
  /// link afterwards, so the pair returned is one stable observation rather
  /// than metadata from a target that has since stopped being current.
  Future<_FusionVersionDir?> _resolveCurrentVersion(
    String productionRoot,
  ) async {
    final versionDir = _resolveCurrentDir(productionRoot);
    if (versionDir == null) return null;

    final resolved = await _versionDirVersion(versionDir);
    if (resolved == null) return null;

    if (_resolveCurrentDir(productionRoot) != versionDir) return null;
    return resolved;
  }

  /// The version directory `production/Autodesk Fusion.app` points at,
  /// whether it names the directory itself or the bundle inside it.
  String? _resolveCurrentDir(String productionRoot) {
    final currentAlias = '$productionRoot/Autodesk Fusion.app';
    if (FileSystemEntity.typeSync(currentAlias, followLinks: false) !=
        FileSystemEntityType.link) {
      // A Finder alias file is not resolvable here; keep everything.
      return null;
    }

    final String target;
    try {
      target = _directory(currentAlias).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }

    final targetName = target.split('/').last;
    final String versionDir;
    if (_hashDirectory.hasMatch(targetName)) {
      if (target.substring(0, target.length - targetName.length - 1) !=
          productionRoot) {
        return null;
      }
      versionDir = target;
    } else if (_bundleNames.contains(targetName)) {
      versionDir = target.substring(0, target.length - targetName.length - 1);
      final versionName = versionDir.split('/').last;
      if (!_hashDirectory.hasMatch(versionName)) return null;
      if (versionDir.substring(
            0,
            versionDir.length - versionName.length - 1,
          ) !=
          productionRoot) {
        return null;
      }
    } else {
      return null;
    }

    return FileSystemEntity.typeSync(versionDir, followLinks: false) ==
            FileSystemEntityType.directory
        ? versionDir
        : null;
  }

  /// The Fusion version [versionDir] holds, or null when any link in the
  /// evidence chain is missing: exactly one known bundle name, real
  /// `Contents`/`MacOS`/`Info.plist`, the exact bundle id, a numeric
  /// version, and a real executable named by the bundle.
  Future<_FusionVersionDir?> _versionDirVersion(String versionDir) async {
    if (FileSystemEntity.typeSync(versionDir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }

    final apps = [
      for (final name in _bundleNames)
        if (FileSystemEntity.typeSync('$versionDir/$name', followLinks: false) ==
            FileSystemEntityType.directory)
          '$versionDir/$name',
    ];
    // Two bundles is ambiguous evidence, not twice as much of it.
    if (apps.length != 1) return null;
    final app = apps.single;

    if (!_isRealDirectory('$app/Contents')) return null;
    if (!_isRealDirectory('$app/Contents/MacOS')) return null;
    final infoPlist = '$app/Contents/Info.plist';
    if (FileSystemEntity.typeSync(infoPlist, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }

    final bundleId = await _plistValue(infoPlist, 'CFBundleIdentifier');
    if (bundleId != 'com.autodesk.fusion360') return null;

    final version = await _plistValue(infoPlist, 'CFBundleVersion');
    if (version == null || !_numericVersion.hasMatch(version)) return null;

    final executable = await _plistValue(infoPlist, 'CFBundleExecutable');
    if (executable != 'Autodesk Fusion' && executable != 'Autodesk Fusion 360') {
      return null;
    }
    if (!_isRealExecutableFile('$app/Contents/MacOS/$executable')) return null;

    return _FusionVersionDir(versionDir, version);
  }

  Future<String?> _plistValue(String plist, String key) async {
    final result = await _probe.run('/usr/bin/plutil', [
      '-extract',
      key,
      'raw',
      plist,
    ]);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Whether [candidate] is strictly older than [current], comparing
  /// dotted-numeric components. A component long enough to overflow is
  /// treated as unknown, which keeps the directory.
  bool _isOlder(String candidate, String current) {
    if (!_numericVersion.hasMatch(candidate)) return false;
    if (!_numericVersion.hasMatch(current)) return false;

    final candidateParts = candidate.split('.');
    final currentParts = current.split('.');
    final count = candidateParts.length > currentParts.length
        ? candidateParts.length
        : currentParts.length;

    for (var index = 0; index < count; index++) {
      final candidatePart = index < candidateParts.length
          ? candidateParts[index]
          : '0';
      final currentPart = index < currentParts.length
          ? currentParts[index]
          : '0';
      if (candidatePart.length > 9 || currentPart.length > 9) return false;
      final candidateNumber = int.tryParse(candidatePart);
      final currentNumber = int.tryParse(currentPart);
      if (candidateNumber == null || currentNumber == null) return false;
      if (candidateNumber < currentNumber) return true;
      if (candidateNumber > currentNumber) return false;
    }
    return false;
  }

  CleanSectionTargets _empty() => const CleanSectionTargets(
    AppsAndUtilitiesLocalDataSource.appsAndUtilities,
    [],
  );

  bool _isRealExecutableFile(String path) {
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

  bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;

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
}
