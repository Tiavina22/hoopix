import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/battery_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/cpu_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/disk_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/host_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/memory_local_datasource.dart';
import 'package:hoopix/features/status/data/datasources/network_local_datasource.dart';
import 'package:hoopix/features/status/data/models/network_status_model.dart';
import 'package:hoopix/features/status/domain/entities/disk_status.dart';
import 'package:hoopix/features/status/domain/entities/network_status.dart';
import 'package:hoopix/features/status/domain/entities/system_snapshot.dart';
import 'package:hoopix/features/status/domain/repositories/status_repository.dart';

/// Composes the six local datasources into [SystemSnapshot]s on a timer.
/// Each datasource is wrapped in [_guard]: a collector failing on one tick
/// leaves its field null/empty rather than failing the whole snapshot, so a
/// single flaky CLI tool can't blank the live dashboard.
class StatusRepositoryImpl implements StatusRepository {
  StatusRepositoryImpl({ProcessRunner processRunner = const ProcessRunner()})
    : _cpu = CpuLocalDataSource(processRunner),
      _memory = MemoryLocalDataSource(processRunner),
      _disk = DiskLocalDataSource(processRunner),
      _battery = BatteryLocalDataSource(processRunner),
      _network = NetworkLocalDataSource(processRunner),
      _host = HostLocalDataSource(processRunner);

  /// Test-only seam: build with hand-picked datasources (e.g. wired to a
  /// fake [ProcessRunner]) instead of the default local ones.
  StatusRepositoryImpl.withDataSources({
    required CpuLocalDataSource cpu,
    required MemoryLocalDataSource memory,
    required DiskLocalDataSource disk,
    required BatteryLocalDataSource battery,
    required NetworkLocalDataSource network,
    required HostLocalDataSource host,
  }) : _cpu = cpu,
       _memory = memory,
       _disk = disk,
       _battery = battery,
       _network = network,
       _host = host;

  final CpuLocalDataSource _cpu;
  final MemoryLocalDataSource _memory;
  final DiskLocalDataSource _disk;
  final BatteryLocalDataSource _battery;
  final NetworkLocalDataSource _network;
  final HostLocalDataSource _host;

  NetworkStatusModel? _previousNetwork;
  DateTime? _previousNetworkAt;

  @override
  Stream<SystemSnapshot> watchStatus({
    Duration interval = const Duration(seconds: 1),
  }) async* {
    while (true) {
      yield await collect();
      await Future<void>.delayed(interval);
    }
  }

  /// Single-tick collection, exposed for tests that don't want to consume
  /// the infinite [watchStatus] stream.
  Future<SystemSnapshot> collect() async {
    final now = DateTime.now();

    final cpuFuture = _guard(_cpu.fetch);
    final memoryFuture = _guard(_memory.fetch);
    final diskFuture = _guard(_disk.fetch);
    final batteryFuture = _guard(_battery.fetch);
    final networkFuture = _guard(_network.fetch);
    final hostFuture = _guard(_host.fetch);

    final cpu = await cpuFuture;
    final memory = await memoryFuture;
    final disks = await diskFuture ?? const <DiskStatus>[];
    final battery = await batteryFuture;
    final network = _withRate(await networkFuture, now);
    final host = await hostFuture;

    return SystemSnapshot(
      collectedAt: now,
      cpu: cpu,
      memory: memory,
      disks: disks,
      battery: battery,
      network: network,
      host: host,
    );
  }

  NetworkStatus? _withRate(NetworkStatusModel? current, DateTime now) {
    if (current == null) return null;

    final previous = _previousNetwork;
    final previousAt = _previousNetworkAt;
    _previousNetwork = current;
    _previousNetworkAt = now;

    if (previous == null || previousAt == null) return current;

    final elapsedSeconds = now.difference(previousAt).inMilliseconds / 1000;
    if (elapsedSeconds <= 0) return current;

    return NetworkStatusModel(
      bytesReceived: current.bytesReceived,
      bytesSent: current.bytesSent,
      receiveRateBytesPerSecond:
          ((current.bytesReceived - previous.bytesReceived) / elapsedSeconds)
              .clamp(0, double.infinity),
      sendRateBytesPerSecond:
          ((current.bytesSent - previous.bytesSent) / elapsedSeconds)
              .clamp(0, double.infinity),
    );
  }

  Future<T?> _guard<T>(Future<T> Function() fetch) async {
    try {
      return await fetch();
    } on Object {
      return null;
    }
  }
}
