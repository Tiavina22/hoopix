/// `du` prints one entry per line as `<blocks>\t<path>`.
final _linePattern = RegExp(r'^(\d+)\s+(.+)$');

/// Parses one `du -s -k` line into its byte total, or null for anything that
/// is not a size line — a blank line, or stderr text that leaked into
/// stdout, so a malformed line is skipped rather than misread as a size.
///
/// `-k` reports 1024-byte blocks regardless of locale.
int? parseDuSizeBytes(String line) {
  final match = _linePattern.firstMatch(line.trim());
  if (match == null) return null;

  const blockSize = 1024;
  final blocks = int.tryParse(match.group(1)!);
  return blocks == null ? null : blocks * blockSize;
}
