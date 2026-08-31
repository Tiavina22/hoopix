import Cocoa
import FlutterMacOS

/// Moves paths to the Trash, and refuses the ones that must never be moved.
///
/// The guard lives here, next to the move, rather than in Dart: the checks
/// need inode identity (`st_dev`/`st_ino`) to see through symlinks and
/// hardlinks, which Dart's `FileStat` does not expose — and a guard on the
/// far side of a channel would leave a gap between the check and the action.
/// The rules mirror Mole's analyzer (`cmd/analyze/delete.go`).
final class TrashChannel {
  static let channelName = "fit.hoopix/trash"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      Self.handle(call, result: result)
    }
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "moveToTrash" else {
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
          message: "moveToTrash expects a `paths` list of strings",
          details: nil))
      return
    }

    // One entry per path: nil when it reached the Trash, otherwise why it
    // did not. A refusal for one path never stops the others.
    var failures: [String: Any] = [:]
    for path in paths {
      if let reason = refusalReason(for: path) {
        failures[path] = reason
        continue
      }
      do {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
      } catch {
        failures[path] = error.localizedDescription
      }
    }
    result(failures)
  }

  /// Why [path] must not be trashed, or nil when it may be.
  private static func refusalReason(for path: String) -> String? {
    if let invalid = validate(path) { return invalid }

    if isProtected(path) { return "protected path cannot be deleted" }

    // Re-checked through the symlink, so a link pointing at a protected tree
    // cannot be used to reach it.
    let resolved = (path as NSString).resolvingSymlinksInPath
    if resolved != path, isProtected(resolved) {
      return "protected path cannot be deleted"
    }

    if !FileManager.default.fileExists(atPath: path) {
      // Checked with lstat semantics so a broken symlink is still trashable.
      var info = stat()
      if lstat(path, &info) != 0 { return "path no longer exists" }
    }
    return nil
  }

  /// Rejects what should never be handed to a delete: relative paths, null
  /// bytes, and `..` components that would resolve somewhere else entirely.
  private static func validate(_ path: String) -> String? {
    if path.isEmpty { return "path is empty" }
    if !path.hasPrefix("/") { return "path must be absolute" }
    if path.contains("\0") { return "path contains null bytes" }
    if path.split(separator: "/").contains("..") {
      return "path contains traversal components"
    }
    return nil
  }

  private static func isProtected(_ path: String) -> Bool {
    let clean = (path as NSString).standardizingPath

    // Checked first because it does not depend on HOME: an unset HOME must
    // not let an EDR agent's cache slip through.
    if isEndpointSecurityCache(clean) { return true }
    if isCritical(clean) { return true }
    return isProtectedHomeState(clean)
  }

  private static let criticalRoots = [
    "/", "/Applications", "/Applications/Finder.app", "/Applications/Safari.app",
    "/Library", "/Library/Apple", "/Library/Application Support", "/Library/Extensions",
    "/Library/Keychains", "/System", "/Users", "/Volumes", "/Network", "/cores",
    "/dev", "/etc", "/home", "/net", "/tmp", "/var", "/private", "/private/etc",
    "/private/tmp", "/private/var", "/private/var/audit", "/private/var/db",
    "/private/var/root", "/private/var/tmp", "/private/var/folders", "/bin",
    "/sbin", "/usr", "/opt", "/opt/homebrew",
  ]

  /// System-owned trees that are never a cleanup surface, even when the
  /// caller started inside one rather than selecting its top-level row.
  private static let protectedTrees = [
    "/System", "/bin", "/sbin", "/usr", "/private/etc", "/private/var/audit",
    "/private/var/db", "/private/var/root", "/Library/Apple", "/Library/Extensions",
    "/Library/Keychains", "/Applications/Finder.app", "/Applications/Safari.app",
    "/dev",
  ]

  private static func isCritical(_ path: String) -> Bool {
    for root in criticalRoots where path == root || isSameFile(path, root) {
      return true
    }

    // A child directly under /Users is another account's home root, not an
    // ordinary directory.
    if isDirectChild(path, of: "/Users") { return true }

    for root in protectedTrees {
      if path.hasPrefix(root + "/") || isWithin(path, root) { return true }
    }
    return false
  }

  /// The user's own home root, plus the container/VM state that an app is
  /// still running out of.
  private static func isProtectedHomeState(_ path: String) -> Bool {
    for home in homeRoots() {
      if path == home || isSameFile(path, home) { return true }

      let dockerDesktop = home + "/Library/Containers/com.docker.docker"
      if path == dockerDesktop || path.hasPrefix(dockerDesktop + "/")
        || isWithin(path, dockerDesktop)
      {
        return true
      }

      let orbstack = home + "/.orbstack"
      if path == orbstack || path.hasPrefix(orbstack + "/") || isWithin(path, orbstack) {
        return true
      }

      let groupContainers = home + "/Library/Group Containers"
      if let entries = try? FileManager.default.contentsOfDirectory(atPath: groupContainers) {
        for entry in entries where entry.lowercased().hasSuffix("dev.orbstack") {
          if isWithin(path, groupContainers + "/" + entry) { return true }
        }
      }
    }
    return false
  }

  private static func homeRoots() -> [String] {
    var roots: [String] = []
    for candidate in [ProcessInfo.processInfo.environment["HOME"], NSHomeDirectory()] {
      guard let home = candidate, !home.isEmpty else { continue }
      let clean = (home as NSString).standardizingPath
      if !roots.contains(clean) { roots.append(clean) }
      let resolved = (clean as NSString).resolvingSymlinksInPath
      if !roots.contains(resolved) { roots.append(resolved) }
    }
    return roots
  }

  /// Endpoint-security agents keep per-user caches under the Darwin folder.
  /// Deleting anything inside one trips sensor tamper detection, so they are
  /// never touched.
  private static let endpointSecurityPrefixes = [
    "com.crowdstrike.", "com.sentinelone.", "com.sentinel-labs.", "com.eset.",
    "com.jamf.", "com.jamfsoftware.", "com.paloaltonetworks.",
    "com.cisco.anyconnect", "com.cisco.secureclient",
  ]

  private static func isEndpointSecurityCache(_ path: String) -> Bool {
    let lower = path.lowercased()
    guard lower.hasPrefix("/private/var/folders/") || lower.hasPrefix("/var/folders/") else {
      return false
    }
    return endpointSecurityPrefixes.contains { lower.contains($0) }
  }

  /// Identity, not spelling: two names for the same inode are the same file,
  /// which is what makes a symlink or hardlink detour fail.
  private static func isSameFile(_ lhs: String, _ rhs: String) -> Bool {
    var left = stat()
    var right = stat()
    guard stat(lhs, &left) == 0, stat(rhs, &right) == 0 else { return false }
    return left.st_dev == right.st_dev && left.st_ino == right.st_ino
  }

  /// True when [path] is the protected root itself or sits anywhere beneath
  /// it, compared by identity while walking up.
  private static func isWithin(_ path: String, _ protectedRoot: String) -> Bool {
    var rootInfo = stat()
    guard stat(protectedRoot, &rootInfo) == 0 else { return false }

    var current = (path as NSString).standardizingPath
    while true {
      var info = stat()
      if stat(current, &info) == 0, info.st_dev == rootInfo.st_dev,
        info.st_ino == rootInfo.st_ino
      {
        return true
      }
      let parent = (current as NSString).deletingLastPathComponent
      if parent == current || parent.isEmpty { return false }
      current = parent
    }
  }

  private static func isDirectChild(_ path: String, of protectedRoot: String) -> Bool {
    let clean = (path as NSString).standardizingPath
    let parent = (clean as NSString).deletingLastPathComponent
    return clean != (protectedRoot as NSString).standardizingPath && parent != clean
      && isSameFile(parent, protectedRoot)
  }
}
