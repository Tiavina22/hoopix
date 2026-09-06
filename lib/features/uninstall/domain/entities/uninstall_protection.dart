import 'package:hoopix/features/clean/domain/entities/protected_bundles.dart';
import 'package:hoopix/features/clean/domain/entities/shell_glob.dart';

/// Apple's own pro/creative apps that would otherwise match
/// [systemCriticalBundles] by vendor prefix but are ordinary user-installed
/// applications a person can genuinely want gone — Xcode, Final Cut Pro,
/// Logic Pro, and the rest of `APPLE_UNINSTALLABLE_APPS`
/// (`lib/core/app_protection_data.sh`). Checked before the critical list,
/// so this list is an override, not an addition.
const appleUninstallableApps = [
  'com.apple.dt.*', // Xcode, Instruments, FileMerge
  'com.apple.FinalCut*', // Final Cut Pro
  'com.apple.Motion',
  'com.apple.Compressor',
  'com.apple.logic*', // Logic Pro
  'com.apple.garageband*', // GarageBand
  'com.apple.iMovie',
  'com.apple.iWork.*', // Pages, Numbers, Keynote
  'com.apple.MainStage*',
  'com.apple.server.*', // macOS Server
  'com.apple.Playgrounds', // Swift Playgrounds
];

/// Ports `should_protect_from_uninstall` (`lib/core/app_protection.sh`):
/// the first gate an app must clear before it is even shown as
/// uninstallable, run unconditionally regardless of any later
/// confirmation. A bundle id matching [systemCriticalBundles] is refused
/// unless it also matches [appleUninstallableApps], which takes priority.
bool shouldProtectFromUninstall(String bundleId) {
  if (appleUninstallableApps.any(
    (pattern) => matchesShellGlob(bundleId, pattern),
  )) {
    return false;
  }
  return systemCriticalBundles.any(
    (pattern) => matchesShellGlob(bundleId, pattern),
  );
}
