import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';

class ApproveUninstall {
  const ApproveUninstall(this._repository);

  final UninstallInventoryRepository _repository;

  Future<Map<String, String>> call(List<InstalledApp> approved) =>
      _repository.approve(approved);
}
