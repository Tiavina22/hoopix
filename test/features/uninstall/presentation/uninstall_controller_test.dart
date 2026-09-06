import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';
import 'package:hoopix/features/uninstall/domain/usecases/watch_uninstall_inventory.dart';
import 'package:hoopix/features/uninstall/presentation/state/uninstall_controller.dart';

const _app = InstalledApp(
  path: '/Applications/Example.app',
  bundleId: 'com.example.App',
  displayName: 'Example',
);

class _FakeUninstallInventoryRepository
    implements UninstallInventoryRepository {
  _FakeUninstallInventoryRepository(this.emissions);

  final List<List<InstalledApp>> emissions;

  @override
  Stream<List<InstalledApp>> watchInventory() => Stream.fromIterable(emissions);
}

class _FailingUninstallInventoryRepository
    implements UninstallInventoryRepository {
  @override
  Stream<List<InstalledApp>> watchInventory() =>
      Stream<List<InstalledApp>>.error(StateError('scan failed'));
}

void main() {
  test('reflects each emission from the inventory stream', () async {
    final repo = _FakeUninstallInventoryRepository([
      [_app],
      [_app.withSize(2048)],
    ]);
    final controller = UninstallController(WatchUninstallInventory(repo));

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.apps, hasLength(1));
    expect(controller.apps!.single.sizeBytes, 2048);
    expect(controller.isScanning, isFalse);
    expect(controller.error, isNull);
  });

  test('start() resets a previous error before the new scan lands', () async {
    final failing = _FailingUninstallInventoryRepository();
    final controller = UninstallController(WatchUninstallInventory(failing));

    controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(controller.error, isNotNull);
    expect(controller.isScanning, isFalse);

    final repo = _FakeUninstallInventoryRepository([
      [_app],
    ]);
    final recovered = UninstallController(WatchUninstallInventory(repo));
    recovered.start();
    await Future<void>.delayed(Duration.zero);

    expect(recovered.error, isNull);
    expect(recovered.apps, hasLength(1));
  });

  test('an empty inventory reports done scanning with no apps', () async {
    final repo = _FakeUninstallInventoryRepository([[]]);
    final controller = UninstallController(WatchUninstallInventory(repo));

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.apps, isEmpty);
    expect(controller.isScanning, isFalse);
  });
}
