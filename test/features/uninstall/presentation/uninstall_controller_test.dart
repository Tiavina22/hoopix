import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';
import 'package:hoopix/features/uninstall/domain/usecases/approve_uninstall.dart';
import 'package:hoopix/features/uninstall/domain/usecases/watch_uninstall_inventory.dart';
import 'package:hoopix/features/uninstall/presentation/state/uninstall_controller.dart';

const _app = InstalledApp(
  path: '/Applications/Example.app',
  bundleId: 'com.example.App',
  displayName: 'Example',
);

const _otherApp = InstalledApp(
  path: '/Applications/Other.app',
  bundleId: 'com.example.Other',
  displayName: 'Other',
);

class _FakeUninstallInventoryRepository
    implements UninstallInventoryRepository {
  _FakeUninstallInventoryRepository(this.emissions, {this.approveResult});

  final List<List<InstalledApp>> emissions;
  final Map<String, String>? approveResult;
  List<InstalledApp>? approvedCall;

  @override
  Stream<List<InstalledApp>> watchInventory() => Stream.fromIterable(emissions);

  @override
  Future<Map<String, String>> approve(List<InstalledApp> approved) async {
    approvedCall = approved;
    return approveResult ?? const {};
  }
}

class _FailingUninstallInventoryRepository
    implements UninstallInventoryRepository {
  @override
  Stream<List<InstalledApp>> watchInventory() =>
      Stream<List<InstalledApp>>.error(StateError('scan failed'));

  @override
  Future<Map<String, String>> approve(List<InstalledApp> approved) async =>
      const {};
}

UninstallController _controllerFor(UninstallInventoryRepository repo) =>
    UninstallController(WatchUninstallInventory(repo), ApproveUninstall(repo));

void main() {
  test('reflects each emission from the inventory stream', () async {
    final repo = _FakeUninstallInventoryRepository([
      [_app],
      [_app.withSize(2048)],
    ]);
    final controller = _controllerFor(repo);

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.apps, hasLength(1));
    expect(controller.apps!.single.sizeBytes, 2048);
    expect(controller.isScanning, isFalse);
    expect(controller.error, isNull);
  });

  test('start() resets a previous error before the new scan lands', () async {
    final failing = _FailingUninstallInventoryRepository();
    final controller = _controllerFor(failing);

    controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(controller.error, isNotNull);
    expect(controller.isScanning, isFalse);

    final repo = _FakeUninstallInventoryRepository([
      [_app],
    ]);
    final recovered = _controllerFor(repo);
    recovered.start();
    await Future<void>.delayed(Duration.zero);

    expect(recovered.error, isNull);
    expect(recovered.apps, hasLength(1));
  });

  test('an empty inventory reports done scanning with no apps', () async {
    final repo = _FakeUninstallInventoryRepository([[]]);
    final controller = _controllerFor(repo);

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.apps, isEmpty);
    expect(controller.isScanning, isFalse);
  });

  test('every app starts selected, and toggle() excludes just one', () async {
    final repo = _FakeUninstallInventoryRepository([
      [_app, _otherApp],
    ]);
    final controller = _controllerFor(repo);

    controller.start();
    await Future<void>.delayed(Duration.zero);

    expect(controller.selectedApps, [_app, _otherApp]);

    controller.toggle(_app.path);
    expect(controller.selectedApps, [_otherApp]);

    controller.toggle(_app.path);
    expect(controller.selectedApps, [_app, _otherApp]);
  });

  test('setAllSelected(false) excludes every app, true clears the exclusion', (
  ) async {
    final repo = _FakeUninstallInventoryRepository([
      [_app, _otherApp],
    ]);
    final controller = _controllerFor(repo);

    controller.start();
    await Future<void>.delayed(Duration.zero);

    controller.setAllSelected(false);
    expect(controller.selectedApps, isEmpty);
    expect(controller.canApprove, isFalse);

    controller.setAllSelected(true);
    expect(controller.selectedApps, [_app, _otherApp]);
  });

  test('approve() sends only the selected apps and re-scans afterward', () async {
    final repo = _FakeUninstallInventoryRepository([
      [_app, _otherApp],
      [_otherApp],
    ]);
    final controller = _controllerFor(repo);

    controller.start();
    await Future<void>.delayed(Duration.zero);
    controller.toggle(_app.path);

    final failures = await controller.approve();

    expect(failures, isEmpty);
    expect(repo.approvedCall, [_otherApp]);
    expect(controller.isRemoving, isFalse);
  });

  test('approve() surfaces the failures the repository reports', () async {
    final repo = _FakeUninstallInventoryRepository(
      [
        [_app],
        [_app],
      ],
      approveResult: {_app.path: 'refused'},
    );
    final controller = _controllerFor(repo);

    controller.start();
    await Future<void>.delayed(Duration.zero);

    final failures = await controller.approve();

    expect(failures, {_app.path: 'refused'});
  });

  test('canApprove is false with nothing selected or while removing', () async {
    final repo = _FakeUninstallInventoryRepository([
      [_app],
    ]);
    final controller = _controllerFor(repo);

    expect(controller.canApprove, isFalse);

    controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(controller.canApprove, isTrue);
  });
}
