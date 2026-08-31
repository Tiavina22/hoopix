import 'package:hoopix/features/status/domain/entities/memory_status.dart';

class MemoryStatusModel extends MemoryStatus {
  const MemoryStatusModel({
    required super.totalBytes,
    required super.usedBytes,
    required super.freeBytes,
  });

  /// Parses `vm_stat` output against total physical memory from
  /// `sysctl -n hw.memsize`.
  ///
  /// "Used" follows Activity Monitor's definition — active + wired +
  /// compressed. Inactive and file-backed pages are deliberately *not*
  /// counted: macOS keeps them populated as cache and reclaims them on
  /// demand, so treating them as used reports ~99% on a healthy machine and
  /// makes the number meaningless.
  ///
  /// The page size comes from vm_stat's own header (16 KB on Apple silicon,
  /// 4 KB on Intel) rather than being assumed.
  factory MemoryStatusModel.fromVmStat(
    String vmStatOutput, {
    required int totalBytes,
  }) {
    final pageSizeMatch = RegExp(
      r'page size of (\d+) bytes',
    ).firstMatch(vmStatOutput);
    final pageSize = pageSizeMatch != null
        ? int.parse(pageSizeMatch.group(1)!)
        : 4096;

    int pages(String label) {
      final match = RegExp('$label:\\s*(\\d+)\\.').firstMatch(vmStatOutput);
      return match != null ? int.parse(match.group(1)!) : 0;
    }

    final usedPages =
        pages('Pages active') +
        pages('Pages wired down') +
        pages('Pages occupied by compressor');

    final usedBytes = (usedPages * pageSize).clamp(0, totalBytes);

    return MemoryStatusModel(
      totalBytes: totalBytes,
      usedBytes: usedBytes,
      freeBytes: totalBytes - usedBytes,
    );
  }
}
