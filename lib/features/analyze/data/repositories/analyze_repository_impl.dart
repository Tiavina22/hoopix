import 'dart:io';

import 'package:hoopix/core/platform/directory_scanner.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_cache.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/large_files_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/local_snapshot_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/overview_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/reveal_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/trash_local_datasource.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';

/// A `du` over a large tree legitimately runs for tens of seconds — measured
/// at ~14s for `~/Library` on a normal machine — so the scan probes get their
/// own generous budget instead of the 2s default that suits the quick
/// `top`/`vm_stat`-style probes.
const _scanTimeout = Duration(seconds: 60);

/// Spotlight answers from its index, so it either replies quickly or the
/// index cannot help — matching the short budget Mole gives the same query.
const _spotlightTimeout = Duration(seconds: 5);

/// `tmutil` reads local metadata rather than touching the network, so it
/// gets a short budget like Spotlight — matching Mole's own probe timeout.
const _snapshotTimeout = Duration(seconds: 3);

/// Where both caches live. Null when the environment has no HOME, which
/// disables caching rather than guessing a location.
String? get _cacheDirectory {
  final home = Platform.environment['HOME'];
  return home == null ? null : '$home/Library/Caches/hoopix';
}

class AnalyzeRepositoryImpl implements AnalyzeRepository {
  AnalyzeRepositoryImpl()
    : _overview = OverviewLocalDataSource(
        const ProcessRunner(timeout: _scanTimeout),
        home: Platform.environment['HOME'],
      ),
      _directory = DirectoryLocalDataSource(
        DirectoryScanner(),
        DirectoryCache(cacheDirectory: _cacheDirectory),
      ),
      _largeFiles = const LargeFilesLocalDataSource(
        ProcessRunner(timeout: _spotlightTimeout),
      ),
      _reveal = const RevealLocalDataSource(ProcessRunner()),
      _trash = const TrashLocalDataSource(),
      _localSnapshot = const LocalSnapshotLocalDataSource(
        ProcessRunner(timeout: _snapshotTimeout),
      );

  /// Test-only seam: build with hand-picked datasources (e.g. wired to a
  /// fake [ProcessRunner]) instead of the default local ones.
  const AnalyzeRepositoryImpl.withDataSources({
    required OverviewLocalDataSource overview,
    required DirectoryLocalDataSource directory,
    required LargeFilesLocalDataSource largeFiles,
    required RevealLocalDataSource reveal,
    required TrashLocalDataSource trash,
    required LocalSnapshotLocalDataSource localSnapshot,
  }) : _overview = overview,
       _directory = directory,
       _largeFiles = largeFiles,
       _reveal = reveal,
       _trash = trash,
       _localSnapshot = localSnapshot;

  final OverviewLocalDataSource _overview;
  final DirectoryLocalDataSource _directory;
  final LargeFilesLocalDataSource _largeFiles;
  final RevealLocalDataSource _reveal;
  final TrashLocalDataSource _trash;
  final LocalSnapshotLocalDataSource _localSnapshot;

  @override
  Future<Map<String, String>> moveToTrash(List<String> paths) =>
      _trash.moveToTrash(paths);

  @override
  Future<List<AnalyzeEntry>> findLargeFiles(String root) =>
      _largeFiles.find(root);

  @override
  Stream<DirectoryScan> watchOverview() => _overview.watch();

  @override
  Stream<DirectoryScan> watchDirectory(String path) => _directory.watch(path);

  @override
  Future<bool> revealInFinder(String path) => _reveal.reveal(path);

  @override
  Future<int?> localSnapshotCount() => _localSnapshot.count();
}
