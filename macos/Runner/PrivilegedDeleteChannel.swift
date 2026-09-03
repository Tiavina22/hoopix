import Cocoa
import FlutterMacOS

/// Deletes specific root-owned system paths through the standard macOS
/// administrator-privileges prompt — the GUI counterpart of Mole's
/// per-run `sudo`. Hoopix has no persistent privileged helper (Mole has no
/// background agent either, by design), so this asks once, per approved
/// batch, through `do shell script ... with administrator privileges`,
/// which shows the system's own password dialog and runs with no
/// installed component left behind.
///
/// Every path is checked against an explicit allowlist of known system
/// cache roots before anything runs: this channel must never become a
/// general "run this as root" backdoor, even if the Dart side is wrong.
/// Mirrors `TrashChannel`'s shape — one failure map, one path never stops
/// the rest — but the roots it may touch are its own, narrower list, not
/// `TrashChannel`'s protected-path denylist.
final class PrivilegedDeleteChannel {
  static let channelName = "fit.hoopix/privileged_delete"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      Self.handle(call, result: result)
    }
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "deletePaths" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard
      let arguments = call.arguments as? [String: Any],
      let paths = arguments["paths"] as? [String]
    else {
      result(
        FlutterError(
          code: "bad_arguments",
          message: "deletePaths expects a `paths` list of strings",
          details: nil))
      return
    }

    var failures: [String: Any] = [:]
    var allowed: [String] = []
    for path in paths {
      if let reason = refusalReason(for: path) {
        failures[path] = reason
      } else {
        allowed.append(path)
      }
    }

    if !allowed.isEmpty {
      let recursive = allowed.filter { !isWithinSweepRoots($0) }
      let filesOnly = allowed.filter { isWithinSweepRoots($0) }
      let (succeeded, batchFailureReason) = runPrivilegedRemoval(
        recursive: recursive, filesOnly: filesOnly)
      for path in allowed where !succeeded.contains(path) {
        failures[path] = batchFailureReason ?? "removal did not confirm success"
      }
    }

    result(failures)
  }

  /// Only these exact roots may ever be targeted — every one is a literal
  /// path Mole's own `clean_deep_system` (`lib/clean/system.sh`) removes
  /// through `safe_sudo_remove`/`safe_sudo_find_delete`, never anything the
  /// caller chose freely. Grown one verified entry at a time, the same way
  /// the Dart-side sections are.
  private static let allowedRoots = [
    "/Library/Caches/com.apple.iconservices.store"
  ]

  private static func refusalReason(for path: String) -> String? {
    if let invalid = validate(path) { return invalid }
    guard isAllowedTarget(path) else {
      return "path is outside the allowed system-cleanup roots"
    }
    return nil
  }

  /// Roots whose *individual files* Mole's own `safe_sudo_find_delete`
  /// sweeps by age and name (`clean_deep_system`, `lib/clean/system.sh`).
  /// Unlike `allowedRoots`, a path here is never removed recursively: it is
  /// deleted with `rm -f`, so a directory handed here fails instead of
  /// taking a tree with it. Depth is capped at the same 5 levels the scan
  /// contract allows, so no deeply nested path can be reached through one.
  ///
  /// Every root here is root-owned and not writable by the invoking user.
  /// `/Library/Caches` is deliberately absent even though Mole sweeps it:
  /// it is `drwxrwxrwt`, so a privileged path-based delete would cross an
  /// ancestor the user can write, which is exactly what Mole's own
  /// `_mole_privileged_path_has_mutable_ancestor` refuses — it downgrades
  /// those to an unprivileged removal, and so does hoopix, by routing them
  /// to the Trash instead of here.
  private static let allowedSweepRoots = [
    "/Library/Logs/DiagnosticReports",
    "/Library/Logs/Adobe",
    "/Library/Logs/CreativeCloud",
    "/private/var/log",
  ]

  private static let maximumSweepDepth = 5

  private static func isAllowedTarget(_ path: String) -> Bool {
    let clean = (path as NSString).standardizingPath
    if allowedRoots.contains(where: { clean == $0 || clean.hasPrefix($0 + "/") }) {
      return true
    }
    if isMacOSInstallerApp(clean) { return true }
    return isWithinSweepRoots(clean)
  }

  /// A path strictly below one of `allowedSweepRoots`, at most
  /// `maximumSweepDepth` components down. The root itself never qualifies.
  private static func isWithinSweepRoots(_ path: String) -> Bool {
    let clean = (path as NSString).standardizingPath
    guard
      let root = allowedSweepRoots.first(where: { clean.hasPrefix($0 + "/") })
    else { return false }
    let relative = clean.dropFirst(root.count + 1)
    let depth = relative.split(separator: "/").count
    return depth >= 1 && depth <= maximumSweepDepth
  }

  /// A stale macOS installer app Software Update itself stages under
  /// `/Applications` (e.g. "Install macOS Sequoia.app") — named after the
  /// release, so no exact path works the way `allowedRoots` does. Matched
  /// on the exact basename shape only: one path component directly under
  /// `/Applications`, never a subpath inside the bundle, and [clean] is
  /// already standardized so `..` cannot forge this prefix.
  private static func isMacOSInstallerApp(_ clean: String) -> Bool {
    let prefix = "/Applications/Install macOS "
    guard clean.hasPrefix(prefix), clean.hasSuffix(".app") else { return false }
    return !clean.dropFirst(prefix.count).contains("/")
  }

  /// Rejects what should never be handed to a privileged delete: relative
  /// paths, null bytes, and `..` components that would resolve somewhere
  /// else entirely.
  private static func validate(_ path: String) -> String? {
    if path.isEmpty { return "path is empty" }
    if !path.hasPrefix("/") { return "path must be absolute" }
    if path.contains("\0") { return "path contains null bytes" }
    if path.split(separator: "/").contains("..") {
      return "path contains traversal components"
    }
    return nil
  }

  /// Runs the removals inside a single administrator-privileges prompt, so
  /// approving several System items only asks once. [recursive] paths are
  /// whole trees (`rm -rf`); [filesOnly] paths come from an age sweep and
  /// are removed with `rm -f`, which fails on a directory rather than
  /// taking one with it. Each removed path is echoed back on stdout so
  /// success can still be attributed per path. Returns the paths that were
  /// actually removed, and — when the prompt was cancelled or the script
  /// itself could not run — a message to attach to every path that did not
  /// succeed.
  private static func runPrivilegedRemoval(
    recursive: [String], filesOnly: [String]
  ) -> (Set<String>, String?) {
    var parts: [String] = []
    if !recursive.isEmpty {
      let quoted = recursive.map(posixShellQuoted).joined(separator: " ")
      parts.append("for p in \(quoted); do rm -rf -- \"$p\" && echo \"$p\"; done")
    }
    if !filesOnly.isEmpty {
      let quoted = filesOnly.map(posixShellQuoted).joined(separator: " ")
      parts.append("for p in \(quoted); do rm -f -- \"$p\" && echo \"$p\"; done")
    }
    let shellScript = parts.joined(separator: "; ")
    let source =
      "do shell script \(appleScriptStringLiteral(for: shellScript)) with administrator privileges"

    guard let script = NSAppleScript(source: source) else {
      return ([], "could not construct the elevation script")
    }
    var errorInfo: NSDictionary?
    let output = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message =
        (errorInfo[NSAppleScript.errorMessage] as? String)
        ?? "administrator privileges were not granted"
      return ([], message)
    }
    let succeeded = Set(
      (output.stringValue ?? "")
        .split(separator: "\n")
        .map(String.init))
    return (succeeded, nil)
  }

  /// Standard POSIX single-quote escaping: wrap in `'...'`, and for every
  /// literal `'` inside, close the quote, insert an escaped quote, reopen
  /// it. [value] here is only ever one of the allowlisted roots above.
  private static func posixShellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// Escapes [value] as a single AppleScript string literal (`\` and `"`
  /// are the only characters AppleScript's own string syntax treats
  /// specially).
  private static func appleScriptStringLiteral(for value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
