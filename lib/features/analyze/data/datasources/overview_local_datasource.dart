import 'dart:io';

import 'package:hoopix/core/platform/disk_usage.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/overview_cache.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

/// How a given overview row is measured. Most are a plain recursive total,
/// two are not.
enum _Measure { directory, homeExcludingLibrary, oldDownloads }

class _Target {
  const _Target(this.entry, this.measure);

  final AnalyzeEntry entry;
  final _Measure measure;
}

/// Downloads are counted only from this age up, so the row answers "what can
/// I clear out?" rather than "how big is my Downloads folder?".
const _oldDownloadsAge = Duration(days: 90);

/// Tool caches worth surfacing, shown only when the path exists. Mirrors the
/// cleanable list in Mole's analyzer. `~/Library/Caches` itself is
/// deliberately absent: the specific caches below are its children, and
/// listing both would double-count the same bytes.
const _toolPaths = <(String, List<String>)>[
  ('System Logs', ['Library', 'Logs']),
  ('Homebrew Cache', ['Library', 'Caches', 'Homebrew']),
  ('Xcode DerivedData', ['Library', 'Developer', 'Xcode', 'DerivedData']),
  ('Xcode Simulators', ['Library', 'Developer', 'CoreSimulator', 'Devices']),
  ('Xcode Archives', ['Library', 'Developer', 'Xcode', 'Archives']),
  (
    'Spotify Cache',
    ['Library', 'Application Support', 'Spotify', 'PersistentCache'],
  ),
  ('JetBrains Cache', ['Library', 'Caches', 'JetBrains']),
  ('Docker Data', ['Library', 'Containers', 'com.docker.docker', 'Data']),
  ('pip Cache', ['Library', 'Caches', 'pip']),
  ('uv Cache', ['.cache', 'uv']),
  ('Gradle Cache', ['.gradle', 'caches']),
  ('CocoaPods Cache', ['Library', 'Caches', 'CocoaPods']),
];

/// The curated entry screen: where space actually goes on a Mac, rather than
/// a raw listing of the home directory. Structural roots first, then the
/// "hidden space" rows that quietly accumulate — the same shape as Mole's
/// analyzer overview.
class OverviewLocalDataSource {
  OverviewLocalDataSource(
    ProcessRunner processRunner, {
    required String? home,
    OverviewCache? cache,
    DiskUsage diskUsage = const DiskUsage(),
  }) : _probe = SizeProbe(processRunner),
       _home = home,
       _diskUsage = diskUsage,
       _cache =
           cache ??
           OverviewCache(
             cacheDirectory: home == null ? null : '$home/Library/Caches/hoopix',
           );

  final SizeProbe _probe;
  final OverviewCache _cache;
  final DiskUsage _diskUsage;

  /// Null when the environment has no HOME, which leaves nothing to show —
  /// resolved by the repository rather than read here, so "no home" is a
  /// state this datasource can actually be handed in a test.
  final String? _home;

  Stream<DirectoryScan> watch() async* {
    final targets = _targets();
    var entries = [for (final target in targets) target.entry];

    if (entries.isEmpty) {
      yield const DirectoryScan(
        path: overviewPath,
        status: DirectoryScanStatus.loaded,
      );
      return;
    }

    // Sizes remembered from the last run show immediately, so reopening
    // Analyze is not a blank column while `du` runs again. They are still
    // re-measured below and corrected as the real numbers land.
    entries = sortedBySize([
      for (final entry in entries) entry.withSize(_cache.sizeOf(entry.path)),
    ]);

    // Every row is named and on screen before a single measurement starts.
    yield DirectoryScan(
      path: overviewPath,
      status: DirectoryScanStatus.scanning,
      entries: entries,
      totalBytes: knownTotal(entries),
    );

    var completed = 0;
    await for (final probe in SizeProbe.pool(targets, _measure)) {
      _cache.store(probe.key.entry.path, probe.sizeBytes);
      entries = sortedBySize(
        withSize(entries, probe.key.entry.path, probe.sizeBytes),
      );
      completed++;
      yield DirectoryScan(
        path: overviewPath,
        status: completed == targets.length
            ? DirectoryScanStatus.loaded
            : DirectoryScanStatus.scanning,
        entries: entries,
        totalBytes: knownTotal(entries),
      );
    }
  }

  List<_Target> _targets() {
    final home = _home;
    if (home == null) return const [];

    final targets = <_Target>[
      _Target(
        AnalyzeEntry(
          path: home,
          name: basename(home),
          isDirectory: true,
          overviewKind: OverviewRowKind.home,
        ),
        _Measure.homeExcludingLibrary,
      ),
    ];

    void addIfExists(
      String path,
      String name,
      OverviewRowKind kind, [
      _Measure measure = _Measure.directory,
    ]) {
      if (!Directory(path).existsSync()) return;
      targets.add(
        _Target(
          AnalyzeEntry(
            path: path,
            name: name,
            isDirectory: true,
            overviewKind: kind,
          ),
          measure,
        ),
      );
    }

    // Split out of Home above so the two rows never count the same bytes.
    addIfExists(
      '$home/Library',
      'User Library',
      OverviewRowKind.userLibrary,
    );
    addIfExists(
      '/Applications',
      'Applications',
      OverviewRowKind.applications,
    );
    addIfExists('/Library', 'System Library', OverviewRowKind.systemLibrary);

    addIfExists(
      '$home/Library/Application Support/MobileSync/Backup',
      'iOS Backups',
      OverviewRowKind.iosBackups,
    );
    addIfExists(
      '$home/Downloads',
      'Old Downloads',
      OverviewRowKind.oldDownloads,
      _Measure.oldDownloads,
    );

    for (final (name, segments) in _toolPaths) {
      addIfExists('$home/${segments.join('/')}', name, OverviewRowKind.tool);
    }

    return targets;
  }

  Future<int?> _measure(_Target target) => switch (target.measure) {
    _Measure.directory => _probe.sizeOf(target.entry.path),
    _Measure.homeExcludingLibrary => _measureHomeExcludingLibrary(
      target.entry.path,
    ),
    _Measure.oldDownloads => _measureOldDownloads(target.entry.path),
  };

  /// Home is measured as its children minus `~/Library`, which has its own
  /// row. Measuring the whole of Home would count that subtree twice.
  Future<int?> _measureHomeExcludingLibrary(String home) async {
    final directories = <String>[];
    final files = <String>[];

    try {
      await for (final entity in Directory(home).list(followLinks: false)) {
        if (entity is Link) continue;
        if (entity.path == '$home/Library') continue;
        if (entity is Directory) {
          directories.add(entity.path);
        } else if (entity is File) {
          files.add(entity.path);
        }
      }
    } on FileSystemException {
      return null;
    }

    final directoryBytes = await _probe.sumOf(directories);
    if (directoryBytes == null && directories.isNotEmpty) return null;
    final fileBytes = await _sumFileSizes(files);
    return (directoryBytes ?? 0) + fileBytes;
  }

  /// On-disk bytes, so loose files add up the same way `du` totals the
  /// directories next to them.
  Future<int> _sumFileSizes(List<String> paths) async {
    final sizes = await _diskUsage.actualSizes(paths);
    return sizes.fold<int>(0, (total, size) => total + (size ?? 0));
  }

  /// Only entries untouched for [_oldDownloadsAge], so the row is a cleanup
  /// signal rather than a folder size.
  Future<int?> _measureOldDownloads(String downloads) async {
    final cutoff = DateTime.now().subtract(_oldDownloadsAge);
    final staleDirectories = <String>[];
    final staleFiles = <String>[];

    try {
      await for (final entity in Directory(downloads).list(followLinks: false)) {
        if (entity is Link) continue;
        final name = basename(entity.path);
        if (name.startsWith('.')) continue;

        final FileStat stat;
        try {
          stat = await entity.stat();
        } on FileSystemException {
          continue;
        }
        if (!stat.modified.isBefore(cutoff)) continue;

        if (entity is Directory) {
          staleDirectories.add(entity.path);
        } else if (entity is File) {
          staleFiles.add(entity.path);
        }
      }
    } on FileSystemException {
      return null;
    }

    final directoryBytes = await _probe.sumOf(staleDirectories);
    final fileBytes = await _sumFileSizes(staleFiles);
    return (directoryBytes ?? 0) + fileBytes;
  }
}
