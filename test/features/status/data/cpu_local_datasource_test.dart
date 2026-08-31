import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/cpu_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('fetch wires top + sysctl output into a CpuStatusModel', () async {
    final runner = FakeProcessRunner({
      'top -l 1 -n 0 -s 0': ProcessResult.success(
        'CPU usage: 14.38% user, 25.66% sys, 59.95% idle \n',
      ),
      'sysctl -n hw.physicalcpu': ProcessResult.success('8\n'),
      'sysctl -n hw.ncpu': ProcessResult.success('8\n'),
    });

    final cpu = await CpuLocalDataSource(runner).fetch();

    expect(cpu.userPercent, 14.38);
    expect(cpu.physicalCores, 8);
    expect(cpu.logicalCores, 8);
  });

  test('fetch throws when `top` is unavailable', () async {
    final runner = FakeProcessRunner(const {});
    expect(CpuLocalDataSource(runner).fetch, throwsStateError);
  });
}
