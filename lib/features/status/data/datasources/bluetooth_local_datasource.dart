import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/bluetooth_device_model.dart';

class BluetoothLocalDataSource {
  const BluetoothLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  /// Every paired accessory `system_profiler` currently reports, connected
  /// or not. Returns an empty list when the probe fails or nothing is
  /// paired — both are "nothing to show", not an error.
  Future<List<BluetoothDeviceModel>> fetch() async {
    final result = await _processRunner.run('system_profiler', [
      'SPBluetoothDataType',
    ]);
    if (!result.isSuccess) return const [];
    return BluetoothDeviceModel.parse(result.stdout!);
  }
}
