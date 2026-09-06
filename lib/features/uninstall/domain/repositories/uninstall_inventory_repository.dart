import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';

/// Deliberately read-only: installed apps, their leftover files, and their
/// sizes, for review — there is no approve/delete method here, unlike
/// Clean and Purge's own repositories. Teardown needs the shared-bundle-id
/// sibling guard, launch services/login item cleanup, and brew cask
/// routing landing together as one unit, per the safety review this
/// command's port started from; adding deletion here piecemeal would ship
/// a path that bypasses that guard.
abstract class UninstallInventoryRepository {
  /// Every installed app this scan reaches, with its leftover files
  /// already found, emitted first without sizes measured, then again as
  /// each one's size lands — the same progressive-sizing shape Clean and
  /// Purge's own plans use.
  Stream<List<InstalledApp>> watchInventory();
}
