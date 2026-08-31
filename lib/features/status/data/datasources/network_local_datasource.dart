import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/network_status_model.dart';

class NetworkLocalDataSource {
  const NetworkLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  Future<NetworkStatusModel> fetch() async {
    final result = await _processRunner.run('netstat', const ['-ib']);
    if (!result.isSuccess) {
      throw StateError('network: ${result.failure}');
    }
    return NetworkStatusModel.fromNetstat(result.stdout!);
  }
}
