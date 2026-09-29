import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/cpu_status_model.dart';
import 'package:hoopix/features/status/domain/entities/cpu_ticks.dart';

void main() {
  test('CpuStatusModel.fromUsage carries the measured split', () {
    final cpu = CpuStatusModel.fromUsage(
      const CpuUsage(userPercent: 14.38, systemPercent: 25.66),
      physicalCores: 8,
      logicalCores: 8,
    );

    expect(cpu.userPercent, 14.38);
    expect(cpu.systemPercent, 25.66);
    expect(cpu.idlePercent, closeTo(59.96, 0.001));
    expect(cpu.usedPercent, closeTo(40.04, 0.001));
  });
}
