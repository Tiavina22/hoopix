import 'package:hoopix/features/status/domain/entities/cpu_status.dart';
import 'package:hoopix/features/status/domain/entities/cpu_ticks.dart';

class CpuStatusModel extends CpuStatus {
  const CpuStatusModel({
    required super.userPercent,
    required super.systemPercent,
    required super.idlePercent,
    required super.physicalCores,
    required super.logicalCores,
  });

  factory CpuStatusModel.fromUsage(
    CpuUsage usage, {
    required int physicalCores,
    required int logicalCores,
  }) => CpuStatusModel(
    userPercent: usage.userPercent,
    systemPercent: usage.systemPercent,
    idlePercent: usage.idlePercent,
    physicalCores: physicalCores,
    logicalCores: logicalCores,
  );
}
