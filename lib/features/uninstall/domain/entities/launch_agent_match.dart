import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/features/uninstall/domain/entities/generic_app_name.dart';

/// Ports the bundle-id half of `find_app_files`' user LaunchAgents scan
/// (`lib/core/app_protection.sh`) and `_uninstall_unload_launch_plists`'
/// own bundle-id filter (`lib/uninstall/batch.sh`): `find -maxdepth 1
/// \( -name "$bundle_id.plist" -o -name "$bundle_id.*.plist" \)`. The
/// match is anchored at a literal `.` boundary, so `com.example.app` never
/// claims `com.example.application.plist`.
bool launchAgentNameMatchesBundleId(String name, String bundleId) {
  if (!isReverseDnsBundleId(bundleId)) return false;
  return name.startsWith('$bundleId.') && name.endsWith('.plist');
}

/// Ports `find_app_files`' "Launch Agents by name" scan: `find -maxdepth 1
/// -name "*$app_name*.plist"`, gated exactly as Mole gates it — a display
/// name of at least 5 characters, never one of the generic words that
/// collide with unrelated agents, and never Apple's own `com.apple.*`
/// agents. Short names (Zoom, Arc) still reach their agents through
/// [launchAgentNameMatchesBundleId].
///
/// [isGenericAppName] compares case-insensitively where Mole's `=~` is
/// case-sensitive, so this refuses a superset of what Mole refuses —
/// narrower, never broader.
bool launchAgentNameMatchesAppName(String name, String appName) {
  if (appName.length < 5 || isGenericAppName(appName)) return false;
  if (!name.endsWith('.plist') || name.startsWith('com.apple.')) return false;
  return name.substring(0, name.length - '.plist'.length).contains(appName);
}
