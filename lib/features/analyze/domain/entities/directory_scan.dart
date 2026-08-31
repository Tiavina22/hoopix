import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';

/// Sentinel [DirectoryScan.path] for the curated overview, which is a set of
/// hand-picked roots rather than one directory. The empty string can never
/// collide with a real path.
const overviewPath = '';

enum DirectoryScanStatus {
  /// Entries are listed, but some directory sizes are still being computed.
  scanning,
  loaded,

  /// The directory itself could not be read — nothing to show at all. This
  /// is not the same as a directory whose *descendants* are partly
  /// unreadable, which still lists fine with some sizes missing.
  permissionDenied,
  failed,
}

/// One snapshot of a directory listing. The datasource emits a new one every
/// time a directory's size lands, so the screen fills in progressively
/// instead of blocking on the slowest child.
class DirectoryScan {
  const DirectoryScan({
    required this.path,
    required this.status,
    this.entries = const [],
    this.totalBytes,
    this.error,
  });

  final String path;
  final DirectoryScanStatus status;

  /// Sorted by size descending; entries whose size is not known yet sort
  /// last so the list doesn't reshuffle around them.
  final List<AnalyzeEntry> entries;

  /// Sum of the sizes known so far — the denominator for row proportions.
  final int? totalBytes;
  final Object? error;

  bool get isScanning => status == DirectoryScanStatus.scanning;
  bool get isEmpty =>
      entries.isEmpty && status != DirectoryScanStatus.permissionDenied;
}
