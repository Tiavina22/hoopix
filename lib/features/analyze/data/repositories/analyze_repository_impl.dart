import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/large_files_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/overview_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/reveal_local_datasource.dart';
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

class AnalyzeRepositoryImpl implements AnalyzeRepository {
  AnalyzeRepositoryImpl()
    : _overview = OverviewLocalDataSource(
        const ProcessRunner(timeout: _scanTimeout),
        home: Platform.environment['HOME'],
      ),
      _directory = DirectoryLocalDataSource(
        const ProcessRunner(timeout: _scanTimeout),
      ),
      _largeFiles = const LargeFilesLocalDataSource(
        ProcessRunner(timeout: _spotlightTimeout),
      ),
      _reveal = const RevealLocalDataSource(ProcessRunner());

  /// Test-only seam: build with hand-picked datasources (e.g. wired to a
  /// fake [ProcessRunner]) instead of the default local ones.
  const AnalyzeRepositoryImpl.withDataSources({
    required OverviewLocalDataSource overview,
    required DirectoryLocalDataSource directory,
    required LargeFilesLocalDataSource largeFiles,
    required RevealLocalDataSource reveal,
  }) : _overview = overview,
       _directory = directory,
       _largeFiles = largeFiles,
       _reveal = reveal;

  final OverviewLocalDataSource _overview;
  final DirectoryLocalDataSource _directory;
  final LargeFilesLocalDataSource _largeFiles;
  final RevealLocalDataSource _reveal;

  @override
  Future<List<AnalyzeEntry>> findLargeFiles(String root) =>
      _largeFiles.find(root);

  @override
  Stream<DirectoryScan> watchOverview() => _overview.watch();

  @override
  Stream<DirectoryScan> watchDirectory(String path) => _directory.watch(path);

  @override
  Future<bool> revealInFinder(String path) => _reveal.reveal(path);
}
