/// One installed application, with what the inventory scan learned about
/// it. This is a read-only snapshot — nothing about it implies the app can
/// be removed yet; teardown (the shared-bundle-id sibling guard, launch
/// services/login item cleanup, brew cask routing) is separate,
/// higher-risk work ported after this inventory.
class InstalledApp {
  const InstalledApp({
    required this.path,
    required this.bundleId,
    required this.displayName,
    this.sizeBytes,
    this.leftoverPaths = const [],
  });

  final String path;

  /// `"unknown"` when `Info.plist` has no readable `CFBundleIdentifier` —
  /// never null, matching `uninstall_resolve_bundle_id`'s own fallback.
  final String bundleId;

  final String displayName;

  /// Null while unmeasured, or when the size could not be read.
  final int? sizeBytes;

  /// Existing leftover files/directories `find_app_files`'s ported subset
  /// found for this app — see `UninstallLeftoverDiscovery`. Shown for
  /// review; nothing here has been deleted or is being offered for
  /// deletion yet.
  final List<String> leftoverPaths;

  InstalledApp withSize(int? sizeBytes) => InstalledApp(
    path: path,
    bundleId: bundleId,
    displayName: displayName,
    sizeBytes: sizeBytes,
    leftoverPaths: leftoverPaths,
  );

  InstalledApp withLeftoverPaths(List<String> leftoverPaths) => InstalledApp(
    path: path,
    bundleId: bundleId,
    displayName: displayName,
    sizeBytes: sizeBytes,
    leftoverPaths: leftoverPaths,
  );
}
