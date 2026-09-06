import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/entities/uninstall_leftover_paths.dart'
    show stripVersionSuffix;

/// Ports `uninstall_normalize_bundle_id`: bundle ids collide
/// case-insensitively on default (case-insensitive) APFS, so every
/// comparison in this file goes through this first.
String normalizeBundleId(String bundleId) => bundleId.toLowerCase();

/// Ports `uninstall_bundle_id_has_surviving_sibling` (`lib/uninstall/batch.sh`):
/// a preview-time hint, over the already-discovered inventory, that
/// another install of the same bundle id exists and is not itself part of
/// this removal batch. Deliberately not authoritative — Mole's own
/// comment is explicit that "a preview-time inventory cannot authorize
/// bundle-id teardown", since an app can be mounted, installed, or copied
/// into place while the confirmation screen is open. The live re-scan
/// immediately before deletion is the actual gate; this only decides what
/// to show the user and how to narrow leftover discovery for the preview.
bool bundleIdHasSurvivingSibling({
  required String bundleId,
  required String appPath,
  required List<InstalledApp> allApps,
  required Set<String> selectedPaths,
}) {
  if (bundleId.isEmpty || bundleId == 'unknown') return false;
  final normalized = normalizeBundleId(bundleId);

  for (final other in allApps) {
    if (normalizeBundleId(other.bundleId) != normalized) continue;
    if (other.path == appPath) continue;
    if (selectedPaths.contains(other.path)) continue;
    return true;
  }
  return false;
}

/// Ports `uninstall_surviving_sibling_names`: every identifier a surviving
/// sibling could be shown under — its `.app`-stripped basename, and that
/// basename's own version-suffix-stripped form when the two differ — all
/// lowercased for the case-insensitive name-collision check
/// [siblingGuardLevelFor] uses to decide between `guard` and `guard_login`.
Set<String> survivingSiblingNames({
  required String bundleId,
  required String appPath,
  required List<InstalledApp> allApps,
  required Set<String> selectedPaths,
}) {
  if (bundleId.isEmpty || bundleId == 'unknown') return const {};
  final normalized = normalizeBundleId(bundleId);

  final names = <String>{};
  for (final other in allApps) {
    if (normalizeBundleId(other.bundleId) != normalized) continue;
    if (other.path == appPath) continue;
    if (selectedPaths.contains(other.path)) continue;

    final lastSlash = other.path.lastIndexOf('/');
    var base = lastSlash == -1
        ? other.path
        : other.path.substring(lastSlash + 1);
    if (base.endsWith('.app')) base = base.substring(0, base.length - 4);

    names.add(base.toLowerCase());
    final stripped = stripVersionSuffix(base);
    if (stripped != base) names.add(stripped.toLowerCase());
  }
  return names;
}

/// How far a candidate's own teardown must be narrowed because another
/// live install shares its bundle id.
enum SiblingGuardLevel {
  /// No surviving sibling: normal full teardown.
  none,

  /// A surviving sibling exists, but its own name(s) do not collide with
  /// this app's display name — name-derived leftovers for this specific
  /// display name are still safe to discover, but every bundle-id-keyed
  /// pattern and the toolchain heuristics are suppressed.
  guard,

  /// A surviving sibling exists AND collides by name (or a live sibling
  /// scan could not prove one absent at all) — no name-derived discovery
  /// either; only the app bundle itself is ever touched, and login-item
  /// removal is suppressed.
  guardLogin,
}

/// Ports the `_batch_scan_app_details` decision between `sibling_guard`
/// values `"none"`, `"guard"`, and `"guard_login"`: `guardLogin` when the
/// surviving sibling's own name collides with [displayName]
/// (case-insensitively), `guard` otherwise.
SiblingGuardLevel siblingGuardLevelFor({
  required String bundleId,
  required String appPath,
  required String displayName,
  required List<InstalledApp> allApps,
  required Set<String> selectedPaths,
}) {
  if (!bundleIdHasSurvivingSibling(
    bundleId: bundleId,
    appPath: appPath,
    allApps: allApps,
    selectedPaths: selectedPaths,
  )) {
    return SiblingGuardLevel.none;
  }

  final siblingNames = survivingSiblingNames(
    bundleId: bundleId,
    appPath: appPath,
    allApps: allApps,
    selectedPaths: selectedPaths,
  );
  return siblingNames.contains(displayName.toLowerCase())
      ? SiblingGuardLevel.guardLogin
      : SiblingGuardLevel.guard;
}
