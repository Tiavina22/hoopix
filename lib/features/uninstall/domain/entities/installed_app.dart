/// One installed application, with what the inventory scan learned about
/// it. This is a read-only snapshot — nothing about it implies the app can
/// be removed yet; teardown (leftover discovery, the shared-bundle-id
/// sibling guard, launch services/login item cleanup) is separate,
/// higher-risk work ported after this inventory.
class InstalledApp {
  const InstalledApp({
    required this.path,
    required this.bundleId,
    required this.displayName,
    this.sizeBytes,
  });

  final String path;

  /// `"unknown"` when `Info.plist` has no readable `CFBundleIdentifier` —
  /// never null, matching `uninstall_resolve_bundle_id`'s own fallback.
  final String bundleId;

  final String displayName;

  /// Null while unmeasured, or when the size could not be read.
  final int? sizeBytes;

  InstalledApp withSize(int? sizeBytes) => InstalledApp(
    path: path,
    bundleId: bundleId,
    displayName: displayName,
    sizeBytes: sizeBytes,
  );
}
