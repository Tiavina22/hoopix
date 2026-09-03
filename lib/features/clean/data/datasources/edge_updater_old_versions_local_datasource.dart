import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Orders two dotted version strings the way `sort -V` does for the
/// numeric-component versions Edge's updater actually writes
/// (`131.0.2903.86`): component by component, numerically where both sides
/// parse as numbers, lexically otherwise, with a missing component sorting
/// before a present one so `1.2` precedes `1.2.3`.
int compareVersionStrings(String a, String b) {
  final aParts = a.split('.');
  final bParts = b.split('.');
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;

  for (var i = 0; i < length; i++) {
    final aPart = i < aParts.length ? aParts[i] : '';
    final bPart = i < bParts.length ? bParts[i] : '';
    final aNumber = int.tryParse(aPart);
    final bNumber = int.tryParse(bPart);
    final comparison = (aNumber != null && bNumber != null)
        ? aNumber.compareTo(bNumber)
        : aPart.compareTo(bPart);
    if (comparison != 0) return comparison < 0 ? -1 : 1;
  }
  return 0;
}

/// Ports `clean_edge_updater_old_versions` (`lib/clean/user.sh`, issue
/// #1216): the staged update payloads Microsoft's EdgeUpdater leaves under
/// `~/Library/Application Support/Microsoft/EdgeUpdater/apps/msedge-stable`
/// after Edge has already updated itself. Shares
/// [CleanSectionsLocalDataSource.browsers]'s section name.
///
/// Deliberately *not* folded into [ChromiumOldVersionsLocalDataSource],
/// exactly as Mole keeps it out of its own shared Chromium helper: there is
/// no `Current` symlink here, the keep-rule is version-based rather than
/// mtime-based, and it never escalates to a privileged removal.
///
/// With the installed Edge's version readable, anything strictly older is a
/// leftover and anything equal or newer is a pending update, so only
/// strictly-older payloads go. Without it, the rule falls back to Mole's
/// original conservative one: keep the highest version, and only when there
/// are at least two — a lone directory is never removed on a guess.
///
/// Every candidate carries an Edge process recheck, matching Mole's own
/// per-directory reprobe before each removal.
class EdgeUpdaterOldVersionsLocalDataSource {
  EdgeUpdaterOldVersionsLocalDataSource({
    required this.home,
    ProcessGuard? guard,
    ProcessRunner? probe,
    List<String>? applicationRoots,
    Directory Function(String path)? directory,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _applicationRoots =
           applicationRoots ?? ['/Applications', '$home/Applications'],
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessGuard _guard;
  final ProcessRunner _probe;
  final List<String> _applicationRoots;
  final Directory Function(String path) _directory;

  static const _recheck = ProcessRecheck(exactNames: ['Microsoft Edge']);

  Future<CleanSectionTargets> enumerate() async {
    final updaterDir =
        '$home/Library/Application Support/Microsoft/EdgeUpdater'
        '/apps/msedge-stable';
    final versionDirs = _realDirectoriesOf(updaterDir);
    if (versionDirs.isEmpty) return _empty();

    final cleanable = _cleanableVersions(
      versionDirs,
      await _installedEdgeVersion(),
    );
    if (cleanable.isEmpty) return _empty();

    if (await _guard.check(exactNames: _recheck.exactNames) !=
        ProcessLiveness.notRunning) {
      return _empty();
    }

    return CleanSectionTargets(
      CleanSectionsLocalDataSource.browsers,
      cleanable,
      recheckProcessGuards: {for (final dir in cleanable) dir: _recheck},
    );
  }

  List<String> _cleanableVersions(
    List<String> versionDirs,
    String? installedVersion,
  ) {
    if (installedVersion != null) {
      return [
        for (final dir in versionDirs)
          if (compareVersionStrings(dir.split('/').last, installedVersion) < 0)
            dir,
      ];
    }

    // Without a known installed version, a single staged payload could be
    // the live one — Mole refuses to guess below two directories.
    if (versionDirs.length < 2) return const [];
    final latest = [for (final dir in versionDirs) dir.split('/').last]
      ..sort(compareVersionStrings);
    return [
      for (final dir in versionDirs)
        if (dir.split('/').last != latest.last) dir,
    ];
  }

  /// The installed Edge's `CFBundleShortVersionString`, from the first
  /// application root that has one, or null when neither does.
  Future<String?> _installedEdgeVersion() async {
    for (final root in _applicationRoots) {
      final plist = '$root/Microsoft Edge.app/Contents/Info.plist';
      if (FileSystemEntity.typeSync(plist, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final result = await _probe.run('plutil', [
        '-extract',
        'CFBundleShortVersionString',
        'raw',
        plist,
      ]);
      if (!result.isSuccess) continue;
      final version = result.stdout?.trim();
      if (version != null && version.isNotEmpty) return version;
    }
    return null;
  }

  CleanSectionTargets _empty() =>
      const CleanSectionTargets(CleanSectionsLocalDataSource.browsers, []);

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
