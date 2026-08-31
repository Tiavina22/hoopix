import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/cpu_status_model.dart';

void main() {
  group('CpuStatusModel.fromTopOutput', () {
    test('parses a real `top -l 1 -n 0 -s 0` summary line', () {
      const output = 'CPU usage: 14.38% user, 25.66% sys, 59.95% idle \n';

      final cpu = CpuStatusModel.fromTopOutput(
        output,
        physicalCores: 8,
        logicalCores: 8,
      );

      expect(cpu.userPercent, 14.38);
      expect(cpu.systemPercent, 25.66);
      expect(cpu.idlePercent, 59.95);
      expect(cpu.usedPercent, closeTo(40.04, 0.001));
    });

    test('throws on unrecognized output', () {
      expect(
        () => CpuStatusModel.fromTopOutput(
          'garbage',
          physicalCores: 1,
          logicalCores: 1,
        ),
        throwsFormatException,
      );
    });
  });
}
