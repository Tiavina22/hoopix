import 'dart:io';

import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/domain/entities/brew_cask_token.dart';

/// Where `brew` lives on Apple Silicon and Intel Macs. A Finder-launched app
/// inherits a PATH without either, so `brew` is always called by absolute
/// path rather than resolved through PATH the way Mole's shell does.
const _brewCandidates = ['/opt/homebrew/bin/brew', '/usr/local/bin/brew'];

/// `HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 NONINTERACTIVE=1`, the
/// environment Mole gives every brew call so it never pauses to update
/// itself or waits on a prompt nobody can answer.
const _brewEnv = [
  'HOMEBREW_NO_ENV_HINTS=1',
  'HOMEBREW_NO_AUTO_UPDATE=1',
  'NONINTERACTIVE=1',
];

enum CaskDetectionKind { none, cask, unknown, timedOut }

/// What [BrewCask.detect] learned about one app: not Homebrew's, a cask
/// with its [token], or — the two states Mole refuses to guess through — an
/// install state it could not read, or a probe that did not answer.
class CaskDetection {
  const CaskDetection._(this.kind, [this.token]);

  static const none = CaskDetection._(CaskDetectionKind.none);
  static const unknown = CaskDetection._(CaskDetectionKind.unknown);
  static const timedOut = CaskDetection._(CaskDetectionKind.timedOut);
  factory CaskDetection.cask(String token) =>
      CaskDetection._(CaskDetectionKind.cask, token);

  final CaskDetectionKind kind;
  final String? token;
}

/// `is_brew_cask_installed`'s exit codes 0/1/2, plus its timeout.
enum CaskInstallState { installed, notInstalled, unknown, timedOut }

enum CaskUninstallResult { removed, failed, timedOut }

/// Ports `lib/uninstall/brew.sh`: finds whether Homebrew manages an app
/// bundle, and uninstalls it through Homebrew when it does, so `brew list`
/// never goes on reporting an app that is no longer there.
///
/// Detection keeps Mole's four stages, cheapest and most certain first: the
/// fully resolved path lands in a Caskroom; exactly one Caskroom holds a
/// bundle of that name and `brew info` confirms it owns this app; the app is
/// a symlink straight into a Caskroom; a cask token equal to the app's name
/// is installed and `brew info` confirms it. Name-based stages never
/// succeed on the name alone.
class BrewCask {
  BrewCask({
    ProcessRunner? probe,
    ProcessRunner Function(Duration timeout)? uninstallRunner,
    FileSystemEntityType Function(String path)? typeOf,
    String? Function(String path)? resolvePath,
    String? Function(String path)? readLink,
    List<String> Function(String directory)? listNames,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 10)),
       _uninstallRunner =
           uninstallRunner ?? ((timeout) => ProcessRunner(timeout: timeout)),
       _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false)),
       _resolvePath = resolvePath ?? _resolveSymbolicLinks,
       _readLink = readLink ?? _linkTarget,
       _listNames = listNames ?? listDirectoryNames;

  final ProcessRunner _probe;
  final ProcessRunner Function(Duration timeout) _uninstallRunner;
  final FileSystemEntityType Function(String path) _typeOf;
  final String? Function(String path) _resolvePath;
  final String? Function(String path) _readLink;
  final List<String> Function(String directory) _listNames;

  String? get _brew {
    for (final candidate in _brewCandidates) {
      if (_typeOf(candidate) != FileSystemEntityType.notFound) return candidate;
    }
    return null;
  }

  Future<ProcessResult> _run(
    ProcessRunner runner,
    String brew,
    List<String> args,
  ) => runner.run('/usr/bin/env', [..._brewEnv, brew, ...args]);

  /// Detects every app in [appPaths], sharing one `brew list --cask` across
  /// all of them instead of paying for it once per app.
  Future<Map<String, CaskDetection>> detectAll(List<String> appPaths) async {
    final brew = _brew;
    if (brew == null) {
      return {for (final path in appPaths) path: CaskDetection.none};
    }

    Future<ProcessResult>? caskList;
    Future<ProcessResult> list() =>
        caskList ??= _run(_probe, brew, ['list', '--cask']);

    return {for (final path in appPaths) path: await _detect(brew, path, list)};
  }

  Future<CaskDetection> detect(String appPath) async =>
      (await detectAll([appPath]))[appPath]!;

  /// Ports `get_brew_cask_name`.
  Future<CaskDetection> _detect(
    String brew,
    String appPath,
    Future<ProcessResult> Function() list,
  ) async {
    if (_typeOf(appPath) == FileSystemEntityType.notFound) {
      return CaskDetection.none;
    }
    final bundleName = appPath.split('/').last;

    // Stage 1: the fully resolved path is inside a Caskroom.
    final resolved = _resolvePath(appPath);
    if (resolved != null && resolved.split('/').last == bundleName) {
      final token = caskTokenFromCaskroomPath(resolved);
      if (token != null) return CaskDetection.cask(token);
    }

    // Stage 2: exactly one Caskroom token holds a bundle of this name.
    final tokens = _caskroomTokensHolding(bundleName);
    if (tokens.length == 1) {
      final verdict = await _confirmOwnership(
        brew,
        tokens.single,
        appPath,
        list,
      );
      if (verdict.kind != CaskDetectionKind.none) return verdict;
    }

    // Stage 3: the app is a symlink pointing straight into a Caskroom.
    if (_typeOf(appPath) == FileSystemEntityType.link) {
      final target = _readLink(appPath);
      if (target != null && target.split('/').last == bundleName) {
        final token = caskTokenFromCaskroomPath(target);
        if (token != null) return CaskDetection.cask(token);
      }
    }

    // Stage 4: an installed cask named after the app, confirmed by info.
    final listed = await list();
    if (listed.failure?.kind == ProcessFailureKind.timedOut) {
      return CaskDetection.timedOut;
    }
    if (!listed.isSuccess) return CaskDetection.unknown;
    final named = caskListMatchingName(listed.stdout ?? '', bundleName);
    if (named == null) return CaskDetection.none;
    return _info(brew, named, appPath);
  }

  /// `find <Caskroom> -maxdepth 3 -name "$app_bundle_name"`, reduced to the
  /// distinct cask tokens those matches sit under.
  Set<String> _caskroomTokensHolding(String bundleName) {
    final tokens = <String>{};
    for (final room in caskroomRoots) {
      for (final token in _listNames(room)) {
        final tokenDir = '$room/$token';
        for (final version in _listNames(tokenDir)) {
          if (version == bundleName) {
            final t = caskTokenFromCaskroomPath('$tokenDir/$version');
            if (t != null) tokens.add(t);
          }
          for (final entry in _listNames('$tokenDir/$version')) {
            if (entry != bundleName) continue;
            final t = caskTokenFromCaskroomPath('$tokenDir/$version/$entry');
            if (t != null) tokens.add(t);
          }
        }
      }
    }
    return tokens;
  }

  /// Stage 2's check: the token is installed and its info owns this app.
  Future<CaskDetection> _confirmOwnership(
    String brew,
    String token,
    String appPath,
    Future<ProcessResult> Function() list,
  ) async {
    final listed = await list();
    if (listed.failure?.kind == ProcessFailureKind.timedOut) {
      return CaskDetection.timedOut;
    }
    if (!listed.isSuccess) return CaskDetection.unknown;
    if (!caskListContains(listed.stdout ?? '', token)) {
      return CaskDetection.none;
    }
    return _info(brew, token, appPath);
  }

  Future<CaskDetection> _info(String brew, String token, String appPath) async {
    final info = await _run(_probe, brew, ['info', '--cask', token]);
    if (info.failure?.kind == ProcessFailureKind.timedOut) {
      return CaskDetection.timedOut;
    }
    if (!info.isSuccess) return CaskDetection.unknown;
    return brewInfoOwnsApp(info.stdout ?? '', appPath)
        ? CaskDetection.cask(token)
        : CaskDetection.none;
  }

  /// Ports `is_brew_cask_installed`.
  Future<CaskInstallState> installState(String token) async {
    final brew = _brew;
    if (brew == null || token.isEmpty) return CaskInstallState.unknown;
    final listed = await _run(_probe, brew, ['list', '--cask']);
    if (listed.failure?.kind == ProcessFailureKind.timedOut) {
      return CaskInstallState.timedOut;
    }
    if (!listed.isSuccess) return CaskInstallState.unknown;
    return caskListContains(listed.stdout ?? '', token)
        ? CaskInstallState.installed
        : CaskInstallState.notInstalled;
  }

  /// Ports `brew_uninstall_cask`: `brew uninstall --cask [--zap] <token>`,
  /// then removed only when Homebrew no longer lists the cask *and* the app
  /// bundle is gone from disk. [zap] is false whenever another install
  /// shares the app's bundle id: a zap stanza deletes bundle-id-keyed
  /// preferences and caches the surviving install still uses.
  ///
  /// The timeout grows with the app's size, as Mole's does, because a large
  /// cask's own uninstall scripts can legitimately take minutes. A timeout
  /// is never followed by verification: a half-run cask script is no
  /// evidence either way.
  Future<CaskUninstallResult> uninstall(
    String token, {
    required String appPath,
    required bool zap,
    int? sizeBytes,
  }) async {
    final brew = _brew;
    if (brew == null || token.isEmpty) return CaskUninstallResult.failed;

    final result = await _run(
      _uninstallRunner(_uninstallTimeout(sizeBytes)),
      brew,
      ['uninstall', '--cask', if (zap) '--zap', token],
    );
    if (result.failure?.kind == ProcessFailureKind.timedOut) {
      return CaskUninstallResult.timedOut;
    }

    final state = await installState(token);
    final caskGone = state == CaskInstallState.notInstalled;
    final appGone = _typeOf(appPath) == FileSystemEntityType.notFound;
    return caskGone && appGone
        ? CaskUninstallResult.removed
        : CaskUninstallResult.failed;
  }
}

Duration _uninstallTimeout(int? sizeBytes) {
  final gib = (sizeBytes ?? 0) ~/ (1 << 30);
  if (gib > 15) return const Duration(minutes: 15);
  if (gib > 5) return const Duration(minutes: 10);
  return const Duration(minutes: 5);
}

String? _resolveSymbolicLinks(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

String? _linkTarget(String path) {
  try {
    return Link(path).targetSync();
  } on FileSystemException {
    return null;
  }
}
