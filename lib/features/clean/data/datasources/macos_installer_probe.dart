import 'package:hoopix/core/process/process_runner.dart';

/// The handful of read-only system probes `macos_installer_candidate_still_eligible`
/// (`lib/clean/system.sh`) runs to decide whether a stale
/// `/Applications/Install macOS *.app` is safe to remove. Shared between
/// [MacosInstallerLocalDataSource] (the scan-time check) and
/// `CleanRepositoryImpl` (the approval-time recheck), so the parsing lives
/// in exactly one place. Every probe here is a plain read — `stat`,
/// `sw_vers`, `plutil`, `PlistBuddy` — the only step that needs elevated
/// privileges is the deletion itself, which this class never performs.
class MacosInstallerProbe {
  const MacosInstallerProbe({ProcessRunner? probe})
    : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5));

  final ProcessRunner _probe;

  /// `dev:inode:mtime` for [path], Mole's own cheap proof that a file at a
  /// given path is still the exact file it was last time this ran — a
  /// rename, replace, or relaunch changes at least one of the three. Null
  /// when [path] cannot be stat'd at all.
  Future<String?> identity(String path) async {
    final result = await _probe.run('stat', ['-f%d:%i:%m', path]);
    if (!result.isSuccess) return null;
    final output = result.stdout?.trim();
    return (output == null || output.isEmpty) ? null : output;
  }

  /// The `mtime` component of an [identity] string, in whole seconds since
  /// the epoch, or null if the string is not in the expected shape.
  int? mtimeOf(String identityString) {
    final mtime = int.tryParse(identityString.split(':').last);
    return mtime;
  }

  /// The running system's major version (`"15"` from `"15.6.1"`), or null
  /// when `sw_vers` could not be read — Mole treats that as "keep every
  /// installer", never as permission to guess.
  Future<int?> currentMajorVersion() async {
    final result = await _probe.run('sw_vers', ['-productVersion']);
    if (!result.isSuccess) return null;
    final major = result.stdout?.trim().split('.').first;
    return major == null ? null : int.tryParse(major);
  }

  /// The major version an installer bundle at [appPath] installs, read
  /// from its own `Info.plist`, or null when the plist or key is missing —
  /// Mole treats that as "not eligible" too, since it cannot rule out this
  /// being the currently-running version.
  Future<int?> installerMajorVersion(String appPath) async {
    final result = await _probe.run('/usr/libexec/PlistBuddy', [
      '-c',
      'Print :DTPlatformVersion',
      '$appPath/Contents/Info.plist',
    ]);
    if (!result.isSuccess) return null;
    final major = result.stdout?.trim().split('.').first;
    return (major == null || major.isEmpty) ? null : int.tryParse(major);
  }

  /// True when Software Update itself cannot confirm there is nothing
  /// pending — the failure mode is "pending", not "not pending": a read
  /// failure, an unparseable result, or a non-empty update list all count.
  /// Only an explicitly empty `RecommendedUpdates` array means clear.
  Future<bool> softwareUpdatePending() async {
    final result = await _probe.run('plutil', [
      '-extract',
      'RecommendedUpdates',
      'json',
      '-o',
      '-',
      '/Library/Preferences/com.apple.SoftwareUpdate.plist',
    ]);
    if (!result.isSuccess) return true;
    final recommended = (result.stdout ?? '').replaceAll(RegExp(r'\s+'), '');
    return recommended != '[]';
  }
}
