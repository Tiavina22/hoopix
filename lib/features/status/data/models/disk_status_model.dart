import 'package:hoopix/features/status/domain/entities/disk_status.dart';

class DiskStatusModel extends DiskStatus {
  const DiskStatusModel({
    required super.mountPoint,
    required super.totalBytes,
    required super.usedBytes,
    required super.availableBytes,
  });

  static final _rowPattern = RegExp(
    r'^\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s+\d+\s+\d+\s+\d+%\s+(.+)$',
  );

  /// Parses one data row of `df -k` output, e.g.:
  /// `/dev/disk3s1s1   482797652  12348004  12520600    50%  458734 125206000    0%   /`
  ///
  /// Used space is derived as `total - available`, **not** taken from df's
  /// own "Used" column. On APFS every volume in a container reports the
  /// container's full size but only its own usage, so the raw column says
  /// the startup volume is 3% full while the disk it lives on is nearly out
  /// of space. `total - available` is the number Finder shows and the one a
  /// cleanup tool has to act on.
  ///
  /// `df` reports 1024-byte blocks regardless of locale, so no unit sniffing
  /// is needed. Rows that don't match this exact 9-column shape (e.g. the
  /// `map auto_home` automount row, whose filesystem name splits across two
  /// tokens) are skipped rather than misparsed.
  static DiskStatusModel? tryParseRow(String row) {
    final match = _rowPattern.firstMatch(row.trim());
    if (match == null) return null;

    const blockSize = 1024;
    final totalBytes = int.parse(match.group(1)!) * blockSize;
    final availableBytes = int.parse(match.group(3)!) * blockSize;

    return DiskStatusModel(
      totalBytes: totalBytes,
      usedBytes: (totalBytes - availableBytes).clamp(0, totalBytes),
      availableBytes: availableBytes,
      mountPoint: match.group(4)!.trim(),
    );
  }
}
