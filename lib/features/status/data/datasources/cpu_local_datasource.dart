import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/cpu_ticks_channel.dart';
import 'package:hoopix/features/status/data/models/cpu_status_model.dart';
import 'package:hoopix/features/status/domain/entities/cpu_ticks.dart';

/// Measures CPU load over a short window between two tick reads, the way
/// Mole's full refresh does (`sampleCPUPercents`, `cmd/status/metrics_cpu.go`),
/// and reads the core counts from `sysctl` once.
///
/// Not `top -l 1`: its single sample is not measured over any window, so
/// it reads close to the same figure every time whatever the machine is
/// doing.
class CpuLocalDataSource {
  CpuLocalDataSource(
    this._processRunner, {
    CpuTicksChannel ticks = const CpuTicksChannel(),
    Duration window = const Duration(milliseconds: 100),
  }) : _ticks = ticks,
       _window = window;

  final ProcessRunner _processRunner;
  final CpuTicksChannel _ticks;
  final Duration _window;

  /// Core counts never change while the app runs; read once they succeed.
  int? _physicalCores;
  int? _logicalCores;

  Future<CpuStatusModel> fetch() async {
    final before = await _ticks.read();
    if (before == null) throw StateError('cpu: tick counters unavailable');
    final stopwatch = Stopwatch()..start();
    await Future<void>.delayed(_window);
    final after = await _ticks.read();
    final elapsed = stopwatch.elapsed;
    if (after == null) throw StateError('cpu: tick counters unavailable');

    final usage = cpuUsageBetween(before, after, elapsed: elapsed);
    if (usage == null) throw StateError('cpu: tick counters did not match');

    return CpuStatusModel.fromUsage(
      usage,
      physicalCores:
          (_physicalCores ??= await _sysctlCount('hw.physicalcpu')) ?? 0,
      logicalCores: (_logicalCores ??= await _sysctlCount('hw.ncpu')) ?? 0,
    );
  }

  /// Null when unreadable, so the next fetch tries again instead of
  /// caching a zero.
  Future<int?> _sysctlCount(String key) async {
    final result = await _processRunner.run('sysctl', ['-n', key]);
    if (!result.isSuccess) return null;
    final count = int.tryParse(result.stdout!.trim());
    return count == null || count <= 0 ? null : count;
  }
}
