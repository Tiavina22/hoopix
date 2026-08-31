import 'package:hoopix/core/platform/directory_scanner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_cache.dart';
import 'package:hoopix/features/analyze/data/models/analyze_entry_model.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

/// Past the 30 biggest entries in a directory, a row stops being a cleanup
/// signal — it is noise. Same cap as Mole's interactive scan
/// (`scanPathConcurrent`'s default `maxEntries`). [totalBytes] always
/// reflects every child, capped or not: only the list is trimmed, never the
/// number at the top. [capEntries] disables the trim for the export path,
/// mirroring Mole's separate `scanPathConcurrentAllEntries`.
const maxDisplayedEntries = 30;

/// Lists a directory and sizes its children, emitting a new [DirectoryScan]
/// every time a size lands.
///
/// The walk itself is native. One `du` per child would be simpler, but two
/// separate `du` runs cannot deduplicate a hardlinked file between them, so
/// a file with links under two sibling folders would be counted twice.
/// Mole's analyzer walks the tree for the same reason, holding one
/// `(dev, ino)` set across the whole scan.
///
/// Files carry their final size from the listing itself; only directories
/// are still pending when the first frame is drawn.
class DirectoryLocalDataSource {
  const DirectoryLocalDataSource(this._scanner, this._cache);

  final DirectoryScanner _scanner;
  final DirectoryCache _cache;

  Stream<DirectoryScan> watch(String path, {bool capEntries = true}) async* {
    // A directory visited before paints from what was recorded then, so
    // coming back is immediate. The real walk runs behind it and corrects
    // whatever moved. The cache only ever holds the capped list, so an
    // uncapped caller (export) skips it rather than showing a truncated
    // first paint it did not ask for.
    if (capEntries) {
      final remembered = _cache.load(path, allowStale: true);
      if (remembered != null) {
        yield DirectoryScan(
          path: path,
          status: DirectoryScanStatus.scanning,
          entries: remembered.entries,
          totalBytes: remembered.totalBytes,
          totalEntryCount: remembered.totalEntryCount,
        );
      }
    }

    var entries = <AnalyzeEntry>[];
    var pending = 0;
    var sized = 0;
    var listed = false;

    DirectoryScan frame(DirectoryScanStatus status) {
      final sorted = sortedBySize(entries);
      return DirectoryScan(
        path: path,
        status: status,
        entries: capEntries ? capped(sorted) : sorted,
        // The true total over every child, regardless of how many rows are
        // shown — the number at the top never lies about what the trimmed
        // list leaves out.
        totalBytes: knownTotal(entries),
        totalEntryCount: entries.length,
      );
    }

    await for (final event in _scanner.scan(path)) {
      switch (event) {
        case ScanFailed():
          yield DirectoryScan(
            path: path,
            status: event.isPermissionDenied
                ? DirectoryScanStatus.permissionDenied
                : DirectoryScanStatus.failed,
            error: event.reason,
          );
          return;

        case ScanEntry():
          entries.add(
            AnalyzeEntryModel(
              path: event.path,
              name: basename(event.path),
              isDirectory: event.isDirectory,
              sizeBytes: event.sizeBytes,
              accessed: event.accessed,
            ),
          );

        case ScanListed():
          // First paint: every row is present and named, files already
          // final, directories still measuring.
          listed = true;
          pending = event.pending;
          yield frame(
            pending == 0
                ? DirectoryScanStatus.loaded
                : DirectoryScanStatus.scanning,
          );

        case ScanSize():
          sized++;
          entries = withSize(entries, event.path, event.sizeBytes);
          yield frame(
            listed && sized >= pending
                ? DirectoryScanStatus.loaded
                : DirectoryScanStatus.scanning,
          );

        case ScanComplete():
          final complete = frame(DirectoryScanStatus.loaded);
          if (capEntries) {
            _cache.store(path, complete, deduped: event.deduped);
          }
          yield complete;
      }
    }
  }
}

/// The 30 biggest entries of an already-sorted list, or all of it when it
/// does not reach the cap.
List<AnalyzeEntry> capped(List<AnalyzeEntry> sorted) =>
    sorted.length > maxDisplayedEntries
        ? sorted.sublist(0, maxDisplayedEntries)
        : sorted;

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
