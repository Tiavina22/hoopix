import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/cpu_status_model.dart';

/// Reads CPU load from `top -l 1 -n 0 -s 0` and core counts from `sysctl`.
class CpuLocalDataSource {
  const CpuLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  Future<CpuStatusModel> fetch() async {
    final topResult = await _processRunner.run('top', [
      '-l',
      '1',
      '-n',
      '0',
      '-s',
      '0',
    ]);
    if (!topResult.isSuccess) {
      throw StateError('cpu: ${topResult.failure}');
    }

    return CpuStatusModel.fromTopOutput(
      topResult.stdout!,
      physicalCores: await _sysctlInt('hw.physicalcpu'),
      logicalCores: await _sysctlInt('hw.ncpu'),
    );
  }

  Future<int> _sysctlInt(String key) async {
    final result = await _processRunner.run('sysctl', ['-n', key]);
    if (!result.isSuccess) return 0;
    return int.tryParse(result.stdout!.trim()) ?? 0;
  }
}
