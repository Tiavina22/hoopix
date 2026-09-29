import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/cpu_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/cpu_ticks_channel.dart';
import 'package:hoopix/features/status/domain/entities/cpu_ticks.dart';

import '../../../support/fake_process_runner.dart';

/// Hands out [readings] in order, one per call.
class _FakeTicks extends CpuTicksChannel {
  _FakeTicks(this.readings);

  final List<CpuTicksReading?> readings;
  var calls = 0;

  @override
  Future<CpuTicksReading?> read() async => readings[calls++];
}

CpuTicksReading _single(int user, int idle) => CpuTicksReading(
  ticksPerSecond: 100,
  cores: [CoreTicks(user: user, system: 0, idle: idle, nice: 0)],
);

class _Recording extends FakeProcessRunner {
  _Recording(super.responses);

  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls.add([executable, ...arguments].join(' '));
    return super.run(executable, arguments);
  }
}

void main() {
  final counts = {
    'sysctl -n hw.physicalcpu': ProcessResult.success('8\n'),
    'sysctl -n hw.ncpu': ProcessResult.success('10\n'),
  };

  test('measures usage between two tick reads a window apart', () async {
    final ticks = _FakeTicks([_single(0, 0), _single(75, 25)]);

    final cpu = await CpuLocalDataSource(
      FakeProcessRunner(counts),
      ticks: ticks,
      window: Duration.zero,
    ).fetch();

    expect(ticks.calls, 2);
    expect(cpu.userPercent, closeTo(75, 1e-9));
    expect(cpu.usedPercent, closeTo(75, 1e-9));
    expect(cpu.physicalCores, 8);
    expect(cpu.logicalCores, 10);
  });

  test('reads the core counts once, not every tick', () async {
    final runner = _Recording(counts);
    final source = CpuLocalDataSource(
      runner,
      ticks: _FakeTicks([
        _single(0, 0),
        _single(10, 90),
        _single(10, 90),
        _single(20, 180),
      ]),
      window: Duration.zero,
    );

    await source.fetch();
    await source.fetch();

    expect(runner.calls, ['sysctl -n hw.physicalcpu', 'sysctl -n hw.ncpu']);
  });

  test('throws when the tick counters cannot be read', () async {
    final source = CpuLocalDataSource(
      FakeProcessRunner(counts),
      ticks: _FakeTicks([null]),
      window: Duration.zero,
    );

    expect(source.fetch, throwsStateError);
  });
}
