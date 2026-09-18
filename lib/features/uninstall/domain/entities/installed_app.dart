/// One installed application, with what the inventory scan learned about
/// it. A snapshot for review: removal never trusts it, and re-reads the
/// sibling guard, leftovers, and Homebrew ownership fresh before acting.
class InstalledApp {
  const InstalledApp({
    required this.path,
    required this.bundleId,
    required this.displayName,
    this.sizeBytes,
    this.leftoverPaths = const [],
    this.caskName,
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
  /// review.
  final List<String> leftoverPaths;

  /// The Homebrew cask token that manages this app, when the preview scan
  /// found one — Mole's `[Brew]` tag. Such an app is uninstalled through
  /// Homebrew rather than moved to the Trash.
  final String? caskName;

  InstalledApp withSize(int? sizeBytes) => InstalledApp(
    path: path,
    bundleId: bundleId,
    displayName: displayName,
    sizeBytes: sizeBytes,
    leftoverPaths: leftoverPaths,
    caskName: caskName,
  );

  InstalledApp withLeftoverPaths(List<String> leftoverPaths) =>
      _copy(leftoverPaths: leftoverPaths);

  InstalledApp withCaskName(String? caskName) =>
      _copy(caskName: caskName, clearCask: caskName == null);

  InstalledApp _copy({
    List<String>? leftoverPaths,
    String? caskName,
    bool clearCask = false,
  }) => InstalledApp(
    path: path,
    bundleId: bundleId,
    displayName: displayName,
    sizeBytes: sizeBytes,
    leftoverPaths: leftoverPaths ?? this.leftoverPaths,
    caskName: clearCask ? null : caskName ?? this.caskName,
  );
}
