import Cocoa
import FlutterMacOS

/// Runs one of a fixed set of named system-maintenance operations through
/// the standard macOS administrator-privileges prompt — the GUI
/// counterpart of Mole's own upfront `ensure_sudo_session`, which every
/// `sudo`-gated optimize task then reuses via `sudo`'s own short-lived
/// timestamp cache. Hoopix has no persistent privileged helper, so this
/// asks per call through `do shell script ... with administrator
/// privileges`; macOS's own Authorization Services cache the grant for a
/// few minutes, so a maintenance run that triggers several of these in
/// quick succession typically only prompts once in practice, the same
/// user experience `sudo`'s timestamp cache gives Mole's CLI.
///
/// The operation table below is the entire safety boundary: Dart only ever
/// names which fixed operation to run, never assembles the shell text
/// itself, so this can never become a general "run this as root" backdoor
/// even if the Dart side is wrong. The one caller-supplied value ever
/// interpolated — the invoking user's own uid, for
/// `reset_user_permissions` — is validated as a plain decimal number
/// first. Mirrors `PrivilegedDeleteChannel`'s shape and reasoning, for
/// commands instead of path deletions.
final class PrivilegedCommandChannel {
  static let channelName = "fit.hoopix/privileged_command"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      Self.handle(call, result: result)
    }
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "run" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard
      let callArguments = call.arguments as? [String: Any],
      let operation = callArguments["operation"] as? String
    else {
      result(
        FlutterError(
          code: "bad_arguments",
          message: "run expects an `operation` string",
          details: nil))
      return
    }
    let operationArguments = callArguments["arguments"] as? [String: String] ?? [:]

    guard let shellScript = shellScript(for: operation, arguments: operationArguments) else {
      result(
        FlutterError(
          code: "unknown_operation",
          message: "\(operation) is not a known privileged operation",
          details: nil))
      return
    }

    let source =
      "do shell script \(appleScriptStringLiteral(for: shellScript)) with administrator privileges"
    guard let script = NSAppleScript(source: source) else {
      result(
        FlutterError(
          code: "script_error", message: "could not construct the elevation script",
          details: nil))
      return
    }

    var errorInfo: NSDictionary?
    script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message =
        (errorInfo[NSAppleScript.errorMessage] as? String)
        ?? "administrator privileges were not granted"
      result(FlutterError(code: "elevation_failed", message: message, details: nil))
      return
    }

    result(nil)
  }

  /// Every operation hoopix's Optimize tasks may request, and the exact,
  /// fixed shell text each one runs — grown one verified entry at a time,
  /// each a literal command Mole's own optimize tasks run under `sudo`
  /// (`lib/optimize/tasks.sh`), never assembled from caller-supplied text.
  private static func shellScript(for operation: String, arguments: [String: String]) -> String? {
    switch operation {
    case "flush_dns":
      // opt_system_maintenance / opt_network_optimization.
      return "dscacheutil -flushcache && killall -HUP mDNSResponder"
    case "flush_route":
      // opt_network_stack_optimize.
      return "route -n flush"
    case "flush_arp":
      // opt_network_stack_optimize.
      return "arp -a -d"
    case "reset_user_permissions":
      // opt_disk_permissions_repair.
      guard let uid = arguments["uid"], isValidUid(uid) else { return nil }
      return "diskutil resetUserPermissions / \(uid)"
    case "rebuild_spotlight_index":
      // opt_spotlight_index_optimize.
      return "mdutil -E /"
    case "run_periodic_maintenance":
      // opt_periodic_maintenance.
      return "periodic daily weekly monthly"
    default:
      return nil
    }
  }

  private static func isValidUid(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber }
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
