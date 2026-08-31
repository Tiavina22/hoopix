import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/memory_status_model.dart';

class MemoryLocalDataSource {
  const MemoryLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  Future<MemoryStatusModel> fetch() async {
    final vmStat = await _processRunner.run('vm_stat', const []);
    if (!vmStat.isSuccess) {
      throw StateError('memory: ${vmStat.failure}');
    }

    final memSize = await _processRunner.run('sysctl', ['-n', 'hw.memsize']);
    final totalBytes = memSize.isSuccess
        ? int.tryParse(memSize.stdout!.trim()) ?? 0
        : 0;

    return MemoryStatusModel.fromVmStat(vmStat.stdout!, totalBytes: totalBytes);
  }
}
