import 'package:flutter/services.dart';
import 'package:hoopix/features/status/domain/entities/cpu_ticks.dart';

/// Each core's cumulative CPU tick counters, from `host_processor_info` —
/// see `macos/Runner/CpuTicksChannel.swift`. No command-line tool prints
/// them, and a usage percentage is only honest when measured over a window
/// between two reads.
class CpuTicksChannel {
  const CpuTicksChannel([this.channel = const MethodChannel(_channelName)]);

  static const _channelName = 'fit.hoopix/cpu_ticks';

  final MethodChannel channel;

  /// The current counters, or null when the native side cannot answer
  /// (no channel registered, or the call itself failed).
  Future<CpuTicksReading?> read() async {
    try {
      final result = await channel.invokeMapMethod<String, Object?>('read');
      final rate = result?['ticksPerSecond'];
      final cores = result?['cores'];
      if (rate is! int || cores is! List) return null;
      return CpuTicksReading(
        ticksPerSecond: rate,
        cores: [
          for (final core in cores)
            if (core case [
              final int user,
              final int system,
              final int idle,
              final int nice,
            ])
              CoreTicks(user: user, system: system, idle: idle, nice: nice)
            else
              throw const FormatException('malformed core ticks'),
        ],
      );
    } on Object {
      return null;
    }
  }
}
