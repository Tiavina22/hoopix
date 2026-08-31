import 'dart:io';

import 'package:hoopix/core/platform/disk_usage.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/size_probe.dart';
import 'package:hoopix/features/analyze/data/models/analyze_entry_model.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

/// Lists a directory and sizes its children, emitting a new [DirectoryScan]
/// every time a size lands.
///
/// Sizes are gathered as one `du -s` per child directory rather than a single
/// `du -d 1` over the parent, because measured on a real home directory the
/// single call takes 95–120s (the serial sum of every child) before printing
/// anything, while individual children mostly return in well under two
/// seconds. Fanning out means the list is usable immediately and only the
/// genuinely heavy directories arrive late.
///
/// Files never go through `du` at all — a plain file's size comes from its
/// own `stat`. That also sidesteps BSD `du`'s `-a`/`-d` being mutually
/// exclusive, which makes "files *and* one-level directory totals"
/// impossible to ask for in a single invocation on macOS.
class DirectoryLocalDataSource {
  DirectoryLocalDataSource(
    ProcessRunner processRunner, {
    DiskUsage diskUsage = const DiskUsage(),
  }) : _probe = SizeProbe(processRunner),
       _diskUsage = diskUsage;

  final SizeProbe _probe;
  final DiskUsage _diskUsage;

  Stream<DirectoryScan> watch(String path) async* {
    final List<AnalyzeEntry> children;
    try {
      children = await _listChildren(path);
    } on FileSystemException catch (error) {
      yield DirectoryScan(
        path: path,
        status: _statusForListFailure(error),
        error: error,
      );
      return;
    } on Object catch (error) {
      yield DirectoryScan(
        path: path,
        status: DirectoryScanStatus.failed,
        error: error,
      );
      return;
    }

    var entries = sortedBySize(children);
    final pendingPaths = [
      for (final entry in entries)
        if (entry.isDirectory) entry.path,
    ];

    if (pendingPaths.isEmpty) {
      yield DirectoryScan(
        path: path,
        status: DirectoryScanStatus.loaded,
        entries: entries,
        totalBytes: knownTotal(entries),
      );
      return;
    }

    // First paint: every row is already there with its name and icon, and
    // files already carry their final size. Only directory sizes are pending.
    yield DirectoryScan(
      path: path,
      status: DirectoryScanStatus.scanning,
      entries: entries,
      totalBytes: knownTotal(entries),
    );

    var completed = 0;
    await for (final probe in SizeProbe.pool(pendingPaths, _probe.sizeOf)) {
      entries = sortedBySize(withSize(entries, probe.key, probe.sizeBytes));
      completed++;
      yield DirectoryScan(
        path: path,
        status: completed == pendingPaths.length
            ? DirectoryScanStatus.loaded
            : DirectoryScanStatus.scanning,
        entries: entries,
        totalBytes: knownTotal(entries),
      );
    }
  }

  Future<List<AnalyzeEntry>> _listChildren(String path) async {
    final directories = <String>[];
    final files = <String>[];

    await for (final entity in Directory(path).list(followLinks: false)) {
      // Symlinks are neither followed nor sized in this version, matching
      // `du -P` and avoiding cycles and double counting.
      if (entity is Link) continue;
      if (entity is Directory) {
        directories.add(entity.path);
      } else if (entity is File) {
        files.add(entity.path);
      }
    }

    // Files are sized by what they occupy on disk, the same measure `du`
    // reports for the directories beside them. One unreadable file is a
    // missing size on its row, not a failed listing.
    final fileSizes = await _diskUsage.actualSizes(files);

    return [
      for (final directory in directories)
        AnalyzeEntryModel(
          path: directory,
          name: basename(directory),
          isDirectory: true,
        ),
      for (final (index, file) in files.indexed)
        AnalyzeEntryModel(
          path: file,
          name: basename(file),
          isDirectory: false,
          sizeBytes: fileSizes[index],
        ),
    ];
  }

  DirectoryScanStatus _statusForListFailure(FileSystemException error) {
    const eperm = 1;
    const eacces = 13;
    final code = error.osError?.errorCode;
    return code == eperm || code == eacces
        ? DirectoryScanStatus.permissionDenied
        : DirectoryScanStatus.failed;
  }
}

List<AnalyzeEntry> withSize(
  List<AnalyzeEntry> entries,
  String path,
  int? sizeBytes,
) => [
  for (final entry in entries)
    if (entry.path == path) entry.withSize(sizeBytes) else entry,
];

/// Descending by size, with sizes still being computed last so rows settle
/// downward into place instead of the whole list reshuffling around them.
List<AnalyzeEntry> sortedBySize(List<AnalyzeEntry> entries) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    final aSize = a.sizeBytes;
    final bSize = b.sizeBytes;
    if (aSize == null && bSize == null) return _byName(a, b);
    if (aSize == null) return 1;
    if (bSize == null) return -1;
    if (aSize != bSize) return bSize.compareTo(aSize);
    return _byName(a, b);
  });
  return sorted;
}

int _byName(AnalyzeEntry a, AnalyzeEntry b) =>
    a.name.toLowerCase().compareTo(b.name.toLowerCase());

int knownTotal(List<AnalyzeEntry> entries) =>
    entries.fold(0, (total, entry) => total + (entry.sizeBytes ?? 0));

/// Last path component. The app has no `package:path` dependency and does
/// this by hand elsewhere too (see `DiskList._displayName`).
String basename(String path) {
  final trimmed = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final separator = trimmed.lastIndexOf('/');
  return separator == -1 ? trimmed : trimmed.substring(separator + 1);
}
