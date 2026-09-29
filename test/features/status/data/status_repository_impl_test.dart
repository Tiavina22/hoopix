import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/battery_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/bluetooth_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/cpu_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/disk_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/host_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/memory_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/network_local_datasource.dart';
import 'package:hoopix/features/status/data/models/cpu_status_model.dart';
import 'package:hoopix/features/status/data/repositories/status_repository_impl.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test(
    'collect() keeps succeeding fields when other datasources fail',
    () async {
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
        bluetooth: BluetoothLocalDataSource(runner),
      );

      final snapshot = await repository.collect();

      expect(snapshot.memory, isNotNull);
      expect(snapshot.memory!.totalBytes, 17179869184);
      expect(snapshot.cpu, isNull);
      expect(snapshot.disks, isEmpty);
      expect(snapshot.battery, isNull);
      expect(snapshot.network, isNull);
    },
  );

  group('Bluetooth', () {
    const profiler = 'system_profiler SPBluetoothDataType';
    const paired =
        'Bluetooth:\n\n      Bluetooth Controller:\n'
        '      Connected:\n          Magic Mouse:\n'
        '              Address: AA:BB:CC:DD:EE:FF\n';

    Future<int> probesAcross(
      List<Duration> ticks, {
      required ProcessResult answer,
    }) async {
      final calls = <String>[];
      final runner = _Recording(calls, {profiler: answer});
      var now = DateTime(2026, 9, 29, 12);
      final repository = StatusRepositoryImpl.withDataSources(
        cpu: CpuLocalDataSource(runner),
        memory: MemoryLocalDataSource(runner),
        disk: DiskLocalDataSource(runner),
        battery: BatteryLocalDataSource(runner),
        network: NetworkLocalDataSource(runner),
        host: HostLocalDataSource(runner),
        bluetooth: BluetoothLocalDataSource(runner),
        now: () => now,
      );
      for (final tick in ticks) {
        now = now.add(tick);
        await repository.collect();
      }
      return calls.where((call) => call == profiler).length;
    }

    test('reuses paired devices for 30 seconds', () async {
      final probes = await probesAcross(const [
        Duration.zero,
        Duration(seconds: 1),
        Duration(seconds: 28),
        Duration(seconds: 1),
      ], answer: ProcessResult.success(paired));

      // Asked at 0s, reused at 1s and 29s, asked again at 30s.
      expect(probes, 2);
    });

    test('an empty answer is asked again on the next tick', () async {
      final probes = await probesAcross(const [
        Duration.zero,
        Duration(seconds: 1),
      ], answer: ProcessResult.success(''));

      expect(probes, 2);
    });
  });

  test('CPU is sampled before any other probe starts', () async {
    final calls = <String>[];
    final runner = _Recording(calls, const {});
    final repository = StatusRepositoryImpl.withDataSources(
      cpu: _OrderedCpu(calls, runner),
      memory: MemoryLocalDataSource(runner),
      disk: DiskLocalDataSource(runner),
      battery: BatteryLocalDataSource(runner),
      network: NetworkLocalDataSource(runner),
      host: HostLocalDataSource(runner),
      bluetooth: BluetoothLocalDataSource(runner),
    );

    await repository.collect();

    expect(calls.first, 'cpu start');
    expect(calls[1], 'cpu end');
    expect(calls.length, greaterThan(2));
  });
}

class _Recording extends FakeProcessRunner {
  _Recording(this.calls, super.responses);

  final List<String> calls;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls.add([executable, ...arguments].join(' '));
    return super.run(executable, arguments);
  }
}

/// Records when its sampling window opens and closes.
class _OrderedCpu extends CpuLocalDataSource {
  _OrderedCpu(this.calls, super.runner);

  final List<String> calls;

  @override
  Future<CpuStatusModel> fetch() async {
    calls.add('cpu start');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    calls.add('cpu end');
    throw StateError('cpu: not measured in this test');
  }
}
