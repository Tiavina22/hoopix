import 'package:hoopix/features/status/domain/entities/host_status.dart';

class HostStatusModel extends HostStatus {
  const HostStatusModel({
    required super.hostname,
    required super.osVersion,
    required super.uptime,
    super.model,
    super.chip,
  });

  /// Computes uptime from `sysctl -n kern.boottime` output, e.g.
  /// `{ sec = 1788154582, usec = 481281 } Mon Aug 31 08:36:22 2026`.
  /// Reading the epoch avoids parsing `uptime`'s locale-dependent free text.
  static Duration uptimeFromBoottime(String boottimeOutput, DateTime now) {
    final match = RegExp(r'sec\s*=\s*(\d+)').firstMatch(boottimeOutput);
    if (match == null) return Duration.zero;
    final bootTime = DateTime.fromMillisecondsSinceEpoch(
      int.parse(match.group(1)!) * 1000,
    );
    final uptime = now.difference(bootTime);
    return uptime.isNegative ? Duration.zero : uptime;
  }

  /// Parses `system_profiler SPHardwareDataType` output for the model name
  /// and chip, port of `collectHardware` (`cmd/status/metrics_hardware.go`).
  /// A line is only read when it has exactly one colon, matching Mole's own
  /// `strings.Split(line, ":")` + `len(parts) == 2` guard — a value that
  /// itself contained a colon would be skipped there too, not just here.
  /// `Processor Name:` is read only as a fallback for Intel Macs, which
  /// have no `Chip:` line at all.
  static ({String? model, String? chip}) parseHardwareInfo(String output) {
    String? model;
    String? chip;
    for (final line in output.split('\n')) {
      final lower = line.trim().toLowerCase();
      final parts = line.split(':');
      if (parts.length != 2) continue;
      final value = parts[1].trim();
      if (value.isEmpty) continue;

      if (lower.contains('model name:')) model = value;
      if (lower.contains('chip:')) chip = value;
      if (lower.contains('processor name:') && (chip == null)) chip = value;
    }
    return (model: model, chip: chip);
  }
}
