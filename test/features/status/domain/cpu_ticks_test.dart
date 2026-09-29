import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/domain/entities/cpu_ticks.dart';

CpuTicksReading reading(List<List<int>> cores, {int ticksPerSecond = 100}) =>
    CpuTicksReading(
      ticksPerSecond: ticksPerSecond,
      cores: [
        for (final [user, system, idle, nice] in cores)
          CoreTicks(user: user, system: system, idle: idle, nice: nice),
      ],
    );

void main() {
  test('usage is busy time over the window, nice counted as user', () {
    // One core, one second: 30 user + 10 nice + 20 system + 40 idle ticks.
    final usage = cpuUsageBetween(
      reading([
        [0, 0, 0, 0],
      ]),
      reading([
        [30, 20, 40, 10],
      ]),
      elapsed: const Duration(seconds: 1),
    )!;

    expect(usage.userPercent, closeTo(40, 1e-9));
    expect(usage.systemPercent, closeTo(20, 1e-9));
    expect(usage.busyPercent, closeTo(60, 1e-9));
    expect(usage.idlePercent, closeTo(40, 1e-9));
  });

  test('a parked core is not read as busy (Mole #1237)', () {
    // Core 0 ran the whole second at 50%. Core 1 was parked: it woke for
    // 20ms, all of it busy, and accumulated no idle ticks while asleep.
    // busy/(busy+idle) would call that core 100%; flooring its window at
    // the wall clock counts the parked time as idle.
    final usage = cpuUsageBetween(
      reading([
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]),
      reading([
        [50, 0, 50, 0],
        [2, 0, 0, 0],
      ]),
      elapsed: const Duration(seconds: 1),
    )!;

    expect(usage.busyPercent, closeTo(26, 1e-9));
  });

  test('a counter that wrapped around 32 bits still gives its delta', () {
    const nearTop = (1 << 32) - 10;
    final usage = cpuUsageBetween(
      reading([
        [nearTop, 0, 0, 0],
      ]),
      reading([
        [40, 0, 50, 0],
      ]),
      elapsed: const Duration(seconds: 1),
    )!;

    expect(usage.userPercent, closeTo(50, 1e-9));
  });

  test('readings that do not describe the same cores give no usage', () {
    expect(
      cpuUsageBetween(
        reading([
          [0, 0, 0, 0],
        ]),
        reading([
          [1, 0, 1, 0],
          [1, 0, 1, 0],
        ]),
        elapsed: const Duration(seconds: 1),
      ),
      isNull,
    );
    expect(
      cpuUsageBetween(
        reading(const []),
        reading(const []),
        elapsed: const Duration(seconds: 1),
      ),
      isNull,
    );
  });

  test('an empty window gives no usage', () {
    expect(
      cpuUsageBetween(
        reading([
          [0, 0, 0, 0],
        ]),
        reading([
          [1, 0, 1, 0],
        ]),
        elapsed: Duration.zero,
      ),
      isNull,
    );
  });
}
