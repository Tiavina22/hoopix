import 'dart:io';

import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/app_leftovers_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// One entry from Mole's `known_protect_patterns`: a glob over a bundle id
/// or filename, paired with the app paths that prove it is still owned. An
/// empty [appPaths] list means unconditionally protected (Homebrew
/// services, which `brew services` manages rather than any `.app`).
class _ProtectPattern {
  const _ProtectPattern(this.glob, this.appPaths);
  final String glob;
  final List<String> appPaths;

  bool matches(String value) {
    final escaped = glob.split('*').map(RegExp.escape).join('.*');
    return RegExp('^$escaped\$').hasMatch(value);
  }
}

/// Ports `clean_orphaned_system_services` (`lib/clean/apps.sh`): a
/// LaunchDaemon or LaunchAgent plist, or a `PrivilegedHelperTools` file,
/// left behind after its owning app was uninstalled. Shares
/// [AppLeftoversLocalDataSource.appLeftovers]'s section name — Mole calls
/// this right alongside `clean_orphaned_app_data` and
/// `clean_orphaned_container_stubs` in the same "App leftovers" section.
///
/// `/Library/LaunchDaemons`, `/Library/LaunchAgents` and
/// `/Library/PrivilegedHelperTools` are world-readable by default on
/// macOS (verified: `drwxr-xr-x root:wheel`, with `-rw-r--r--` plists
/// inside), so scanning and reading plists here needs no privilege at
/// all — only removal does, since none of the three directories are
/// writable by the invoking user. Mole's own sudo gate exists because its
/// CLI cannot assume that; hoopix scans unprivileged and routes only the
/// deletion through the administrator-privileges channel, the same split
/// [SystemAgedSweepsLocalDataSource] uses.
///
/// A plist is orphaned when its `Program`/`ProgramArguments[0]` binary is
/// known and missing, the binary is not under a package-manager or system
/// directory, and no [_protectPatterns] entry proves the owning app is
/// still installed. A binary shaped like
/// `/Library/PrivilegedHelperTools/*.app/Contents/MacOS/*` is never
/// treated as missing evidence on its own — an in-place updater can swap
/// the leaf executable while the registration stays live (#1447). When the
/// binary lives in `PrivilegedHelperTools` and still exists, the plist is
/// only orphaned if [BundleInstallResolver] cannot find the helper's own
/// parent app (#1082).
///
/// A `PrivilegedHelperTools` file is orphaned when its name is not an
/// obvious data file (`.json`, `.log`, ...), its bundle id is not
/// `com.apple.*`, no protect pattern covers it, and — only for a
/// `com`/`org`/`net`/`io`-prefixed id, matching Mole's own SMJobBless
/// assumption — [BundleInstallResolver] finds no owning app.
///
/// [stillEligible] re-runs the whole check, and for a
/// `PrivilegedHelperTools` candidate specifically also re-scans both
/// LaunchDaemons and LaunchAgents completely for any surviving reference
/// to it — a plist and its `Program` helper are one cleanup family, and a
/// registration that reappears (or cannot be read) keeps the helper. This
/// mirrors `_orphan_service_helper_is_unreferenced`.
///
/// Not ported: Mole's own belt-and-suspenders `dev:inode:mtime` identity
/// recheck around the same guard. The full re-scan [stillEligible] already
/// runs is the dominant safety property here; skipping the extra identity
/// snapshot is a deliberate simplification, not a gap in what it checks.
class OrphanedSystemServicesLocalDataSource {
  OrphanedSystemServicesLocalDataSource({
    String? home,
    BundleInstallResolver? resolver,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _home = home,
       _resolver = resolver ?? BundleInstallResolver(home: home),
       _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _directory = directory ?? Directory.new;

  final BundleInstallResolver _resolver;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  /// Names this datasource's own [stillEligible] to `CleanRepositoryImpl`.
  static const revalidatorKey = 'orphaned-system-services';

  static const _dataFileSuffixes = [
    '.json',
    '.cfg',
    '.conf',
    '.me2me_enabled',
    '.log',
    '.dat',
    '.db',
    '.xml',
    '.yml',
    '.yaml',
    '.ini',
    '.txt',
    '.pid',
    '.sock',
    '.lock',
  ];

  static const _protectPatterns = [
    _ProtectPattern('com.sogou.*', ['/Library/Input Methods/SogouInput.app']),
    _ProtectPattern('com.west2online.ClashX.*', ['/Applications/ClashX.app']),
    _ProtectPattern('com.clashmac.*', ['/Applications/ClashMac.app']),
    _ProtectPattern('com.nektony.AC*', [
      '/Applications/App Cleaner & Uninstaller.app',
    ]),
    _ProtectPattern('cn.i4tools.*', ['/Applications/i4Tools.app']),
    _ProtectPattern('com.macpaw.CleanMyMac*', [
      '/Applications/CleanMyMac X.app',
    ]),
    _ProtectPattern('org.wireshark.ChmodBPF', ['/Applications/Wireshark.app']),
    _ProtectPattern('us.zoom.*', ['/Applications/zoom.us.app']),
    _ProtectPattern('it.remote.cli', ['/Applications/Remote.It.app']),
    _ProtectPattern('com.docker.*', ['/Applications/Docker.app']),
    _ProtectPattern('netbird', ['/usr/local/bin/netbird']),
    _ProtectPattern('com.intego.*', [
      '/Library/Intego',
      '/Applications/Intego',
      '/Library/Application Support/Intego',
    ]),
    // Homebrew-managed services: no .app owns these, brew services does.
    _ProtectPattern('homebrew.mxcl.*', []),
  ];

  final String? _home;
  String get home => _home ?? '';

  Future<CleanSectionTargets> enumerate() async {
    final targets = <String>[];

    for (final plist in [
      ..._plistsIn('/Library/LaunchDaemons'),
      ..._plistsIn('/Library/LaunchAgents'),
    ]) {
      if (await _plistIsOrphaned(plist)) targets.add(plist);
    }
    for (final helper in _filesIn('/Library/PrivilegedHelperTools')) {
      if (await _helperFileIsOrphaned(helper)) targets.add(helper);
    }

    return CleanSectionTargets(
      AppLeftoversLocalDataSource.appLeftovers,
      targets,
      privilegedDeletionPaths: targets.toSet(),
      revalidatorKeys: {for (final path in targets) path: revalidatorKey},
    );
  }

  Future<bool> stillEligible(String path) async {
    if (path.endsWith('.plist')) {
      return _plistIsOrphaned(path);
    }
    // Every non-.plist candidate this datasource ever proposes came from
    // the PrivilegedHelperTools scan, so it always needs the unreferenced
    // recheck — unlike Mole's own path-prefix check, this holds structurally
    // rather than by string comparison, so it stays correct under an
    // injected (test) directory root too.
    if (!await _helperFileIsOrphaned(path)) return false;
    return _helperIsUnreferenced(path);
  }

  Future<bool> _plistIsOrphaned(String plist) async {
    final filename = plist.split('/').last;
    if (filename.startsWith('com.apple.')) return false;
    final bundleId = filename.substring(0, filename.length - '.plist'.length);

    final binary = await _plistBinaryPath(plist);
    if (binary == null) return false;

    // A standalone helper .app's own Program shape is protection on its
    // own — an updater swapping the leaf executable is not proof of
    // absence. See #1447.
    if (RegExp(
      r'^/Library/PrivilegedHelperTools/[^/]+\.app/Contents/MacOS/[^/]+$',
    ).hasMatch(binary)) {
      return false;
    }

    final exists =
        FileSystemEntity.typeSync(binary, followLinks: false) !=
        FileSystemEntityType.notFound;
    if (exists) {
      if (!binary.startsWith('/Library/PrivilegedHelperTools/')) return false;
      final helperBundleId = await _privilegedHelperBundleId(binary);
      return !await _resolver.hasInstalledApp(helperBundleId);
    }

    if (_isPackageManagedBinary(binary)) return false;
    if (await _isProtectedByPattern(bundleId)) return false;
    return true;
  }

  Future<bool> _helperFileIsOrphaned(String helper) async {
    final filename = helper.split('/').last;
    if (_dataFileSuffixes.any(filename.endsWith)) return false;

    final bundleId = filename.endsWith('.plist')
        ? filename.substring(0, filename.length - '.plist'.length)
        : filename;
    if (bundleId.startsWith('com.apple.')) return false;

    if (await _isProtectedByPattern(bundleId, filename: filename)) {
      return false;
    }

    // Bundle-ID-style helpers registered via SMJobBless ship with a
    // reverse-DNS name; anything else is not this shape, and Mole never
    // flags it.
    if (!RegExp(r'^(com|org|net|io)\.').hasMatch(bundleId)) return false;

    return !await _resolver.hasInstalledApp(bundleId);
  }

  /// Whether no surviving LaunchDaemon or LaunchAgent still points at
  /// [helper] — the whole point of treating a plist and its helper as one
  /// family. Any plist this cannot conclusively read keeps the helper.
  Future<bool> _helperIsUnreferenced(String helper) async {
    String? helperResolved;
    try {
      helperResolved = File(helper).resolveSymbolicLinksSync();
    } on FileSystemException {
      helperResolved = null;
    }

    for (final root in ['/Library/LaunchDaemons', '/Library/LaunchAgents']) {
      for (final plist in _plistsIn(root)) {
        final referenced = await _plistBinaryPath(plist);
        if (referenced == null) continue;
        if (referenced == helper) return false;
        if (helperResolved == null) continue;
        try {
          if (File(referenced).resolveSymbolicLinksSync() == helperResolved) {
            return false;
          }
        } on FileSystemException {
          // An unresolvable referenced path is not evidence either way.
        }
      }
    }
    return true;
  }

  Future<bool> _isProtectedByPattern(
    String bundleId, {
    String? filename,
  }) async {
    for (final pattern in _protectPatterns) {
      final matches =
          pattern.matches(bundleId) ||
          (filename != null && pattern.matches(filename));
      if (!matches) continue;
      return _systemServiceAppExists(bundleId, pattern.appPaths);
    }
    return false;
  }

  /// Port of `_system_service_app_exists`: true when any candidate app
  /// path exists directly, at a per-user or Setapp sibling location, or —
  /// for a reverse-DNS id — [BundleInstallResolver] finds it another way.
  Future<bool> _systemServiceAppExists(
    String bundleId,
    List<String> appPaths,
  ) async {
    if (appPaths.isEmpty) return true;

    for (final path in appPaths) {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return true;
      }
      final name = path.split('/').last;
      if (path.startsWith('/Applications/')) {
        if (_exists('$home/Applications/$name')) return true;
        if (_exists('/Applications/Setapp/$name')) return true;
      } else if (path.startsWith('/Library/Input Methods/')) {
        if (_exists('$home/Library/Input Methods/$name')) return true;
      }
    }

    if (isReverseDnsBundleId(bundleId)) {
      return _resolver.hasInstalledApp(bundleId);
    }
    return false;
  }

  Future<String> _privilegedHelperBundleId(String binary) async {
    final bundleMatch = RegExp(
      r'^(/Library/PrivilegedHelperTools/[^/]+\.bundle)/Contents/MacOS/[^/]+$',
    ).firstMatch(binary);
    if (bundleMatch != null) {
      final helperBundleDir = bundleMatch.group(1)!;
      final id = await _bundleIdentifier(
        '$helperBundleDir/Contents/Info.plist',
      );
      if (id != null && id.isNotEmpty) return id;
      final dirName = helperBundleDir.split('/').last;
      return dirName.endsWith('.bundle')
          ? dirName.substring(0, dirName.length - '.bundle'.length)
          : dirName;
    }
    final base = binary.split('/').last;
    return base.endsWith('.plist')
        ? base.substring(0, base.length - '.plist'.length)
        : base;
  }

  Future<String?> _bundleIdentifier(String infoPlist) async {
    final result = await _probe.run('plutil', [
      '-extract',
      'CFBundleIdentifier',
      'raw',
      infoPlist,
    ]);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<String?> _plistBinaryPath(String plist) async {
    return await _plistProgramValue(plist, 'ProgramArguments:0') ??
        await _plistProgramValue(plist, 'Program');
  }

  Future<String?> _plistProgramValue(String plist, String key) async {
    final result = await _probe.run('/usr/libexec/PlistBuddy', [
      '-c',
      'Print :$key',
      plist,
    ]);
    if (!result.isSuccess) return null;
    final value = result.stdout?.trim();
    if (value == null || value.isEmpty || !value.startsWith('/')) return null;
    return value;
  }

  bool _isPackageManagedBinary(String binary) {
    const prefixes = [
      '/usr/local/bin/',
      '/usr/local/sbin/',
      '/opt/homebrew/bin/',
      '/opt/homebrew/sbin/',
      '/usr/bin/',
      '/usr/sbin/',
      '/bin/',
      '/sbin/',
      '/usr/libexec/',
    ];
    if (prefixes.any(binary.startsWith)) return true;
    return RegExp(r'^/opt/homebrew/opt/[^/]+/(bin|sbin)/').hasMatch(binary);
  }

  bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  List<String> _plistsIn(String dir) {
    try {
      return [
        for (final entity in _directory(dir).listSync(followLinks: false))
          if (entity is File && entity.path.endsWith('.plist')) entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  List<String> _filesIn(String dir) {
    try {
      return [
        for (final entity in _directory(dir).listSync(followLinks: false))
          if (entity is File) entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }
}
