import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';

/// Installed apps, their leftover files, and their sizes, for review, plus
/// the app-bundle-and-known-leftovers removal [approve] performs.
///
/// [approve] never trusts the inventory that produced [approved]: it
/// re-scans for a live same-bundle-id sibling and re-discovers leftovers
/// immediately before deleting anything, the same "never trust the preview
/// window" contract Clean and Purge's own repositories already keep.
///
/// Launch services/login item teardown and brew cask routing are not part
/// of this contract yet — each is its own separate, higher-risk port.
abstract class UninstallInventoryRepository {
  /// Every installed app this scan reaches, with its leftover files
  /// already found, emitted first without sizes measured, then again as
  /// each one's size lands — the same progressive-sizing shape Clean and
  /// Purge's own plans use.
  Stream<List<InstalledApp>> watchInventory();

  /// Removes each of [approved] — its app bundle and its exact known
  /// leftover files — to the Trash. Returns the paths that did not go,
  /// mapped to why; an empty map means everything moved.
  Future<Map<String, String>> approve(List<InstalledApp> approved);
}
