import 'package:hoopix/features/status/domain/entities/host_status.dart';

class HostStatusModel extends HostStatus {
  const HostStatusModel({
    required super.hostname,
    required super.osVersion,
    required super.uptime,
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
}
