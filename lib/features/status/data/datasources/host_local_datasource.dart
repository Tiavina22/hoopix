import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/host_status_model.dart';

class HostLocalDataSource {
  const HostLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  Future<HostStatusModel> fetch() async {
    final boottime = await _processRunner.run('sysctl', ['-n', 'kern.boottime']);
    final version = await _processRunner.run('sw_vers', ['-productVersion']);
    final host = await _processRunner.run('hostname', const []);

    final uptime = boottime.isSuccess
        ? HostStatusModel.uptimeFromBoottime(boottime.stdout!, DateTime.now())
        : Duration.zero;

    return HostStatusModel(
      hostname: host.isSuccess ? host.stdout!.trim() : 'unknown',
      osVersion: version.isSuccess ? version.stdout!.trim() : 'unknown',
      uptime: uptime,
    );
  }
}
