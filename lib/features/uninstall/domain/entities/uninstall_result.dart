/// What an uninstall batch did not manage, for the screen to report.
///
/// [failures] are paths that did not go, mapped to why. The two app lists
/// are Mole's end-of-batch review warnings: things macOS keeps after an app
/// is gone that no public command can remove, so the user has to switch
/// them off in System Settings themselves.
class UninstallResult {
  const UninstallResult({
    this.failures = const {},
    this.backgroundItemApps = const [],
    this.systemExtensionApps = const [],
  });

  final Map<String, String> failures;

  /// Display names of removed apps whose background job is still loaded in
  /// launchd.
  final List<String> backgroundItemApps;

  /// Display names of removed apps that still have a system extension
  /// installed.
  final List<String> systemExtensionApps;

  bool get hasWarnings =>
      backgroundItemApps.isNotEmpty || systemExtensionApps.isNotEmpty;
}
