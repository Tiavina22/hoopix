/// A single physical-memory usage sample.
class MemoryStatus {
  const MemoryStatus({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
  });

  final int totalBytes;
  final int usedBytes;
  final int freeBytes;

  double get usedPercent => totalBytes == 0 ? 0 : (usedBytes / totalBytes) * 100;
}
