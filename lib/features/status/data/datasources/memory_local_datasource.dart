import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/memory_status_model.dart';

class MemoryLocalDataSource {
  MemoryLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  /// Installed memory never changes while the app runs; read once it
  /// succeeds instead of every tick.
  int? _totalBytes;

  Future<MemoryStatusModel> fetch() async {
    final vmStat = await _processRunner.run('vm_stat', const []);
    if (!vmStat.isSuccess) {
      throw StateError('memory: ${vmStat.failure}');
    }

    _totalBytes ??= await _readTotalBytes();

    return MemoryStatusModel.fromVmStat(
      vmStat.stdout!,
      totalBytes: _totalBytes ?? 0,
    );
  }

  Future<int?> _readTotalBytes() async {
    final memSize = await _processRunner.run('sysctl', ['-n', 'hw.memsize']);
    if (!memSize.isSuccess) return null;
    final total = int.tryParse(memSize.stdout!.trim());
    return total == null || total <= 0 ? null : total;
  }
}
