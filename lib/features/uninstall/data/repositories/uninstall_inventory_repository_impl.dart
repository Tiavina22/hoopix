import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_app_discovery.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';

/// Sizing an app bundle is the same `du` work every other feature's own
/// size passes do.
const _sizeTimeout = Duration(seconds: 60);

class UninstallInventoryRepositoryImpl implements UninstallInventoryRepository {
  UninstallInventoryRepositoryImpl({
    required this.home,
    UninstallAppDiscovery? appDiscovery,
    UninstallLeftoverDiscovery? leftoverDiscovery,
    SizeProbe? sizeProbe,
  }) : _appDiscovery = appDiscovery ?? UninstallAppDiscovery(home: home),
       _leftoverDiscovery = leftoverDiscovery ?? UninstallLeftoverDiscovery(),
       _sizeProbe =
           sizeProbe ?? const SizeProbe(ProcessRunner(timeout: _sizeTimeout));

  final String home;
  final UninstallAppDiscovery _appDiscovery;
  final UninstallLeftoverDiscovery _leftoverDiscovery;
  final SizeProbe _sizeProbe;

  @override
  Stream<List<InstalledApp>> watchInventory() async* {
    final discovered = await _appDiscovery.discover();

    final withLeftovers = [
      for (final app in discovered)
        app.withLeftoverPaths(
          _leftoverDiscovery.discover(
            home: home,
            bundleId: app.bundleId,
            appName: app.displayName,
          ),
        ),
    ];

    yield withLeftovers;
    if (withLeftovers.isEmpty) return;

    var sizes = {for (final app in withLeftovers) app.path: app.sizeBytes};
    await for (final probe in SizeProbe.pool([
      for (final app in withLeftovers) app.path,
    ], _sizeProbe.sizeOf)) {
      sizes = {...sizes, probe.key: probe.sizeBytes};
      yield [for (final app in withLeftovers) app.withSize(sizes[app.path])];
    }
  }
}
