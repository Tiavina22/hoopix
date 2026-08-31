import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/battery_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/cpu_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/disk_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/host_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/memory_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/network_local_datasource.dart';
import 'package:hoopix/features/status/data/repositories/status_repository_impl.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('collect() keeps succeeding fields when other datasources fail', () async {
    // Only memory's underlying commands are configured; cpu/disk/battery/
    // network/host each miss their fake response and fail individually.
    final runner = FakeProcessRunner({
      'vm_stat': ProcessResult.success(
        'Mach Virtual Memory Statistics: (page size of 16384 bytes)\n'
        'Pages free:                                     4295.\n'
        'Pages speculative:                              1762.\n',
      ),
      'sysctl -n hw.memsize': ProcessResult.success('17179869184\n'),
    });

    final repository = StatusRepositoryImpl.withDataSources(
      cpu: CpuLocalDataSource(runner),
      memory: MemoryLocalDataSource(runner),
      disk: DiskLocalDataSource(runner),
      battery: BatteryLocalDataSource(runner),
      network: NetworkLocalDataSource(runner),
      host: HostLocalDataSource(runner),
    );

    final snapshot = await repository.collect();

    expect(snapshot.memory, isNotNull);
    expect(snapshot.memory!.totalBytes, 17179869184);
    expect(snapshot.cpu, isNull);
    expect(snapshot.disks, isEmpty);
    expect(snapshot.battery, isNull);
    expect(snapshot.network, isNull);
  });
}
