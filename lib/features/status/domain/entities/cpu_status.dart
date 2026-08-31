/// A single CPU load sample.
class CpuStatus {
  const CpuStatus({
    required this.userPercent,
    required this.systemPercent,
    required this.idlePercent,
    required this.physicalCores,
    required this.logicalCores,
  });

  final double userPercent;
  final double systemPercent;
  final double idlePercent;
  final int physicalCores;
  final int logicalCores;

  double get usedPercent => (userPercent + systemPercent).clamp(0, 100);
}
