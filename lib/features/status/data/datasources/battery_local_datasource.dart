import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/battery_status_model.dart';

class BatteryLocalDataSource {
  const BatteryLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  /// Returns null when the machine has no battery (desktop Macs) or the
  /// probe fails — both are "nothing to show", not an error.
  Future<BatteryStatusModel?> fetch() async {
    final result = await _processRunner.run('pmset', const ['-g', 'batt']);
    if (!result.isSuccess) return null;
    return BatteryStatusModel.tryParse(result.stdout!);
  }
}
