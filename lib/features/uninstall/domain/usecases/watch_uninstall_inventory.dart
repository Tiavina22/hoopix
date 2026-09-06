import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';

class WatchUninstallInventory {
  const WatchUninstallInventory(this._repository);

  final UninstallInventoryRepository _repository;

  Stream<List<InstalledApp>> call() => _repository.watchInventory();
}
