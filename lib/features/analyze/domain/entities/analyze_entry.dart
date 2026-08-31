/// Rows of the curated overview that carry a meaning beyond their folder
/// name, so the UI can label them properly (and translate the generic ones).
/// Tool-specific rows use [OverviewRowKind.tool] and keep their literal
/// product name — "Homebrew Cache" is not translated.
enum OverviewRowKind {
  home,
  userLibrary,
  applications,
  systemLibrary,
  iosBackups,
  oldDownloads,
  tool,
}

/// One row in Analyze: a file or directory inside the directory being
/// viewed, or one entry of the curated overview.
class AnalyzeEntry {
  const AnalyzeEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.sizeBytes,
    this.overviewKind,
    this.accessed,
  });

  final String path;
  final String name;
  final bool isDirectory;

  /// Last access time, when the native walk reported one. Backs the "unused
  /// for N" hint, the same signal Mole shows beside an entry.
  final DateTime? accessed;

  /// Null while a directory's recursive total is still being computed, or
  /// when it could not be read at all — deliberately distinct from a real
  /// zero, which is a legitimate size for an empty directory.
  final int? sizeBytes;

  /// Set only for overview rows; null for ordinary directory entries.
  final OverviewRowKind? overviewKind;

  bool get hasSize => sizeBytes != null;

  AnalyzeEntry withSize(int? sizeBytes) => AnalyzeEntry(
    path: path,
    name: name,
    isDirectory: isDirectory,
    sizeBytes: sizeBytes,
    overviewKind: overviewKind,
    accessed: accessed,
  );

  /// This entry's share of [totalBytes], for the row's proportion bar.
  double fractionOf(int? totalBytes) {
    final size = sizeBytes;
    if (size == null || totalBytes == null || totalBytes <= 0) return 0;
    return (size / totalBytes).clamp(0.0, 1.0);
  }
}
