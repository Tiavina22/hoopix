import 'package:hoopix/core/process/bundle_install_resolver.dart';

/// Ports `mole_name_starts_with_bundle_id_boundary` (`lib/core/base.sh`):
/// whether [name]'s own basename is exactly [bundleId], or extends it at a
/// literal `.` boundary (`bundleId.suffix`) — never a raw substring match.
/// This dot-anchored check is the mechanism behind CLAUDE.md's own
/// "exact bundle ID... evidence required; vendor prefixes and common-name
/// globs are not" rule for uninstall leftover matching.
bool nameStartsWithBundleIdBoundary(String name, String bundleId) {
  if (!isReverseDnsBundleId(bundleId)) return false;
  final basename = name.split('/').last;
  return basename == bundleId || basename.startsWith('$bundleId.');
}

/// Ports `mole_name_has_bundle_id_boundary`: like
/// [nameStartsWithBundleIdBoundary], but also accepts [bundleId] appearing
/// as a dot-anchored *suffix* segment (`prefix.bundleId` or
/// `prefix.bundleId.suffix`) — used for paths like Group Containers, whose
/// on-disk name can carry a team-id prefix ahead of the app's own bundle id.
bool nameHasBundleIdBoundary(String name, String bundleId) {
  if (nameStartsWithBundleIdBoundary(name, bundleId)) return true;
  if (!isReverseDnsBundleId(bundleId)) return false;
  final basename = name.split('/').last;
  return basename.endsWith('.$bundleId') || basename.contains('.$bundleId.');
}
