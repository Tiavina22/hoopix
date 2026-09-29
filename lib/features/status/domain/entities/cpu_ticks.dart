/// One core's cumulative CPU tick counters, as `host_processor_info`
/// reports them. They only mean something as the difference between two
/// reads.
class CoreTicks {
  const CoreTicks({
    required this.user,
    required this.system,
    required this.idle,
    required this.nice,
  });

  final int user;
  final int system;
  final int idle;
  final int nice;
}

/// Every core's counters at one instant, plus the tick rate that turns
/// them into seconds (`sysconf(_SC_CLK_TCK)`).
class CpuTicksReading {
  const CpuTicksReading({required this.ticksPerSecond, required this.cores});

  final int ticksPerSecond;
  final List<CoreTicks> cores;
}

/// CPU usage over one window, as percentages of it.
class CpuUsage {
  const CpuUsage({required this.userPercent, required this.systemPercent});

  /// User time, including niced processes.
  final double userPercent;
  final double systemPercent;

  double get busyPercent => (userPercent + systemPercent).clamp(0, 100);
  double get idlePercent => 100 - busyPercent;
}

/// Usage between [before] and [after], [elapsed] apart on the wall clock —
/// port of `perCoreUsageFromTimes` (`cmd/status/metrics_cpu.go`).
///
/// Each core's window is floored at [elapsed]: a parked Apple Silicon core
/// stops accumulating idle ticks, so its raw delta covers only the sliver
/// of the window it was awake for, and busy/(busy+idle) would read a mostly
/// sleeping efficiency core as 90–100% (Mole #1237). Counting the missing
/// ticks as idle yields the fraction of the window the core actually
/// worked. The total is busy time over the summed windows, not a mean of
/// per-core percentages, so a core that barely ran cannot drag it upward.
///
/// Null when the two readings do not describe the same cores, or the
/// window is empty.
CpuUsage? cpuUsageBetween(
  CpuTicksReading before,
  CpuTicksReading after, {
  required Duration elapsed,
}) {
  if (before.cores.isEmpty || before.cores.length != after.cores.length) {
    return null;
  }
  if (after.ticksPerSecond <= 0 || elapsed <= Duration.zero) return null;

  final rate = after.ticksPerSecond.toDouble();
  final elapsedSeconds =
      elapsed.inMicroseconds / Duration.microsecondsPerSecond;

  var userSum = 0.0;
  var systemSum = 0.0;
  var windowSum = 0.0;
  for (var i = 0; i < before.cores.length; i++) {
    final a = before.cores[i];
    final b = after.cores[i];
    final user = (_delta(a.user, b.user) + _delta(a.nice, b.nice)) / rate;
    final system = _delta(a.system, b.system) / rate;
    final idle = _delta(a.idle, b.idle) / rate;
    final total = user + system + idle;
    userSum += user;
    systemSum += system;
    windowSum += total < elapsedSeconds ? elapsedSeconds : total;
  }
  if (windowSum <= 0) return null;

  return CpuUsage(
    userPercent: (userSum / windowSum * 100).clamp(0, 100),
    systemPercent: (systemSum / windowSum * 100).clamp(0, 100),
  );
}

/// The counters are unsigned 32-bit and wrap; a later value below an
/// earlier one has gone around once.
int _delta(int before, int after) =>
    after >= before ? after - before : after + (1 << 32) - before;
