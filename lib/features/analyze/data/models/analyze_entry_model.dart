import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';

class AnalyzeEntryModel extends AnalyzeEntry {
  const AnalyzeEntryModel({
    required super.path,
    required super.name,
    required super.isDirectory,
    super.sizeBytes,
  });

  /// `du` prints one entry per line as `<blocks>\t<path>`. The path is
  /// captured greedily so directory names containing spaces survive, the
  /// same way [DiskStatusModel.tryParseRow] handles mount points.
  static final _linePattern = RegExp(r'^(\d+)\s+(.+)$');

  /// Parses one `du -s -k` line into its byte total. Returns null for
  /// anything that isn't a size line (blank lines, stderr text that leaked
  /// into stdout), so a malformed line is skipped rather than misread.
  ///
  /// `-k` reports 1024-byte blocks regardless of locale, matching the
  /// `blockSize` convention `DiskStatusModel` already uses for `df -k`.
  static int? tryParseSizeBytes(String line) {
    final match = _linePattern.firstMatch(line.trim());
    if (match == null) return null;

    const blockSize = 1024;
    final blocks = int.tryParse(match.group(1)!);
    if (blocks == null) return null;
    return blocks * blockSize;
  }
}
