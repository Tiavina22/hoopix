import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';

class FindRunningApps {
  const FindRunningApps(this._repository);

  final UninstallInventoryRepository _repository;

  Future<List<String>> call(List<InstalledApp> apps) =>
      _repository.runningApps(apps);
}
