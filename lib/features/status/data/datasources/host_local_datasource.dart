import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/host_status_model.dart';

/// Host identity and uptime. Everything it reads is fixed for the life of
/// the app — the boot time, the hostname, the macOS version, the hardware —
/// so each is read once it succeeds and only the uptime is recomputed per
/// tick. `system_profiler SPHardwareDataType` in particular is too slow to
/// run every second; Mole caches it the same way ("expensive and rarely
/// changes", `cmd/status/metrics.go`). A probe that fails is simply tried
/// again on the next tick.
class HostLocalDataSource {
  HostLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  DateTime? _bootTime;
  String? _hostname;
  String? _osVersion;
  ({String? model, String? chip})? _hardware;

  Future<HostStatusModel> fetch() async {
    _bootTime ??= await _read('sysctl', [
      '-n',
      'kern.boottime',
    ], HostStatusModel.bootTimeFrom);
    _osVersion ??= await _read('sw_vers', ['-productVersion'], _trimmed);
    _hostname ??= await _read('hostname', const [], _trimmed);
    _hardware ??= await _read('system_profiler', [
      'SPHardwareDataType',
    ], HostStatusModel.parseHardwareInfo);

    final bootTime = _bootTime;
    return HostStatusModel(
      hostname: _hostname ?? 'unknown',
      osVersion: _osVersion ?? 'unknown',
      uptime: bootTime == null
          ? Duration.zero
          : HostStatusModel.uptimeSince(bootTime, DateTime.now()),
      model: _hardware?.model,
      chip: _hardware?.chip,
    );
  }

  Future<T?> _read<T>(
    String executable,
    List<String> arguments,
    T? Function(String stdout) parse,
  ) async {
    final result = await _processRunner.run(executable, arguments);
    return result.isSuccess ? parse(result.stdout!) : null;
  }

  static String? _trimmed(String stdout) {
    final value = stdout.trim();
    return value.isEmpty ? null : value;
  }
}
