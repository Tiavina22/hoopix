import 'package:hoopix/features/status/domain/entities/cpu_status.dart';

class CpuStatusModel extends CpuStatus {
  const CpuStatusModel({
    required super.userPercent,
    required super.systemPercent,
    required super.idlePercent,
    required super.physicalCores,
    required super.logicalCores,
  });

  /// Parses the summary line `top -l 1 -n 0 -s 0` prints, e.g.:
  /// `CPU usage: 14.38% user, 25.66% sys, 59.95% idle `
  factory CpuStatusModel.fromTopOutput(
    String topOutput, {
    required int physicalCores,
    required int logicalCores,
  }) {
    final match = RegExp(
      r'CPU usage:\s*([\d.]+)%\s*user,\s*([\d.]+)%\s*sys,\s*([\d.]+)%\s*idle',
    ).firstMatch(topOutput);

    if (match == null) {
      throw const FormatException('unrecognized `top` CPU usage line');
    }

    return CpuStatusModel(
      userPercent: double.parse(match.group(1)!),
      systemPercent: double.parse(match.group(2)!),
      idlePercent: double.parse(match.group(3)!),
      physicalCores: physicalCores,
      logicalCores: logicalCores,
    );
  }
}
