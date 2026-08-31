/// A single mounted volume's usage.
class DiskStatus {
  const DiskStatus({
    required this.mountPoint,
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
  });

  final String mountPoint;
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;

  double get usedPercent => totalBytes == 0 ? 0 : (usedBytes / totalBytes) * 100;
}
