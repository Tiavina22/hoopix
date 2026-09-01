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
      let (succeeded, batchFailureReason) = runPrivilegedRemoval(of: allowed)
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
    guard isWithinAllowedRoots(path) else {
      return "path is outside the allowed system-cleanup roots"
    }
    return nil
  }

  private static func isWithinAllowedRoots(_ path: String) -> Bool {
    let clean = (path as NSString).standardizingPath
    return allowedRoots.contains { clean == $0 || clean.hasPrefix($0 + "/") }
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

  /// Runs one `rm -rf` per path inside a single administrator-privileges
  /// prompt, so approving several System items only asks once. Each
  /// removed path is echoed back on stdout so success can still be
  /// attributed per path. Returns the paths that were actually removed,
  /// and — when the prompt was cancelled or the script itself could not
  /// run — a message to attach to every path that did not succeed.
  private static func runPrivilegedRemoval(of paths: [String]) -> (Set<String>, String?) {
    let quotedList = paths.map(posixShellQuoted).joined(separator: " ")
    let shellScript =
      "for p in \(quotedList); do rm -rf -- \"$p\" && echo \"$p\"; done"
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
