import 'package:hoopix/features/status/domain/entities/battery_status.dart';
import 'package:hoopix/features/status/domain/entities/cpu_status.dart';
import 'package:hoopix/features/status/domain/entities/disk_status.dart';
import 'package:hoopix/features/status/domain/entities/host_status.dart';
import 'package:hoopix/features/status/domain/entities/memory_status.dart';
import 'package:hoopix/features/status/domain/entities/network_status.dart';

/// One point-in-time read of system health. Every field but [collectedAt]
/// is nullable/empty because a single collector failing on a given tick
/// must not blank out the rest of the dashboard.
class SystemSnapshot {
  const SystemSnapshot({
    required this.collectedAt,
    this.host,
    this.cpu,
    this.memory,
    this.disks = const [],
    this.battery,
    this.network,
  });

  final DateTime collectedAt;
  final HostStatus? host;
  final CpuStatus? cpu;
  final MemoryStatus? memory;
  final List<DiskStatus> disks;
  final BatteryStatus? battery;
  final NetworkStatus? network;
}
