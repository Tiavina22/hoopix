import Cocoa
import FlutterMacOS

/// Walks a directory and reports each child's recursive size as it lands.
///
/// This replaces one `du` per child for the listing view, because separate
/// `du` invocations cannot deduplicate hardlinks between them: a file with
/// two links under two sibling folders would be counted twice. Mole's
/// analyzer walks the tree itself for the same reason, keeping one
/// `(dev, ino)` set for the whole scan — the first link counts its full
/// size, later ones count zero, which is how `du` totals a single tree.
///
/// Walking also yields what `du` cannot report: each entry's last-access
/// time, and the file/directory counts behind the progress.
final class DirectoryScanChannel: NSObject, FlutterStreamHandler {
  static let methodChannelName = "fit.hoopix/scan"
  static let eventChannelName = "fit.hoopix/scan_events"

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var sink: FlutterEventSink?

  /// Scans keyed by the id Dart gave them, so a scan the user navigated away
  /// from can be cancelled without touching the one that replaced it.
  private var cancelled = Set<Int>()
  private let state = NSLock()

  private let queue = DispatchQueue(
    label: "fit.hoopix.scan", qos: .userInitiated, attributes: .concurrent)

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(
      name: Self.eventChannelName, binaryMessenger: messenger)
    super.init()

    eventChannel.setStreamHandler(self)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func onListen(withArguments _: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    sink = eventSink
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]

    switch call.method {
    case "startScan":
      guard let path = arguments?["path"] as? String, let id = arguments?["id"] as? Int else {
        result(
          FlutterError(code: "bad_arguments", message: "startScan needs path and id", details: nil))
        return
      }
      start(path: path, id: id)
      result(nil)

    case "cancelScan":
      guard let id = arguments?["id"] as? Int else {
        result(FlutterError(code: "bad_arguments", message: "cancelScan needs id", details: nil))
        return
      }
      state.lock()
      cancelled.insert(id)
      state.unlock()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isCancelled(_ id: Int) -> Bool {
    state.lock()
    defer { state.unlock() }
    return cancelled.contains(id)
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.sink?(event) }
  }

  private func start(path: String, id: Int) {
    queue.async { [weak self] in
      guard let self else { return }

      let children: [String]
      do {
        children = try FileManager.default.contentsOfDirectory(atPath: path)
      } catch {
        self.emit([
          "id": id, "kind": "failed", "reason": error.localizedDescription,
          "code": (error as NSError).code,
        ])
        return
      }

      // One set for the whole scan, so a hardlink is charged once no matter
      // which child it turns up under.
      let seen = SeenInodes()

      // Listing first, so every row is on screen before any measuring.
      var directories: [String] = []
      for name in children {
        let child = path + "/" + name
        var info = stat()
        guard lstat(child, &info) == 0 else { continue }

        let mode = info.st_mode & S_IFMT
        // Symlinks are listed at their own size and never followed, the same
        // as `du -P` and as Mole's walker.
        let isDirectory = mode == S_IFDIR
        if isDirectory { directories.append(child) }

        self.emit([
          "id": id,
          "kind": "entry",
          "path": child,
          "isDirectory": isDirectory,
          "sizeBytes": isDirectory ? NSNull() : NSNumber(value: Self.countable(info, seen)),
          "accessed": NSNumber(value: Int(info.st_atimespec.tv_sec)),
        ])
      }
      self.emit(["id": id, "kind": "listed", "pending": directories.count])

      if directories.isEmpty {
        self.emit(["id": id, "kind": "complete", "deduped": seen.deduped])
        return
      }

      // Bounded like Mole's directory workers: enough to hide the slow
      // subtrees behind the fast ones without exhausting threads on
      // high-fan-out trees.
      let group = DispatchGroup()
      let width = min(ProcessInfo.processInfo.activeProcessorCount * 2, 6)
      let permits = DispatchSemaphore(value: width)

      for directory in directories {
        guard !self.isCancelled(id) else { break }
        permits.wait()
        self.queue.async(group: group) {
          defer { permits.signal() }
          guard !self.isCancelled(id) else { return }

          let total = Self.walk(directory, id: id, seen: seen) { self.isCancelled(id) }
          guard !self.isCancelled(id) else { return }
          self.emit([
            "id": id, "kind": "size", "path": directory, "sizeBytes": NSNumber(value: total),
          ])
        }
      }

      group.notify(queue: self.queue) {
        guard !self.isCancelled(id) else { return }
        // A total that depended on hardlink dedup is scan-order
        // dependent, so the caller must not cache it.
        self.emit(["id": id, "kind": "complete", "deduped": seen.deduped])
      }
    }
  }

  /// Recursive on-disk total for one subtree. Stays on one filesystem and
  /// never follows symlinks, so a mount or a link cannot pull the walk
  /// somewhere the user did not ask about.
  private static func walk(
    _ root: String, id: Int, seen: SeenInodes, cancelled: () -> Bool
  ) -> Int64 {
    guard !cancelled() else { return 0 }

    var rootInfo = stat()
    guard lstat(root, &rootInfo) == 0 else { return 0 }
    let device = rootInfo.st_dev

    var total: Int64 = 0
    var pending = [root]

    while let current = pending.popLast() {
      if cancelled() { return total }
      guard let names = try? FileManager.default.contentsOfDirectory(atPath: current) else {
        continue
      }

      for name in names {
        let child = current + "/" + name
        var info = stat()
        guard lstat(child, &info) == 0 else { continue }
        // Do not cross mount points.
        if info.st_dev != device { continue }

        if (info.st_mode & S_IFMT) == S_IFDIR {
          pending.append(child)
        } else {
          total += countable(info, seen)
        }
      }
    }
    return total
  }

  /// On-disk size for one entry: the smaller of its allocated blocks and its
  /// logical length. A hardlinked file counts in full the first time it is
  /// seen in this scan and zero afterwards.
  private static func countable(_ info: stat, _ seen: SeenInodes) -> Int64 {
    let allocated = Int64(info.st_blocks) * 512
    let size = min(allocated, Int64(info.st_size))
    guard info.st_nlink > 1 else { return size }
    return seen.insert(device: info.st_dev, inode: info.st_ino) ? size : 0
  }
}

/// The `(dev, ino)` pairs already counted in one scan.
private final class SeenInodes {
  private var seen = Set<Key>()
  private var didDedupe = false
  private let lock = NSLock()

  /// True once a link was charged zero because another link to the same file
  /// had already been counted.
  var deduped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return didDedupe
  }

  private struct Key: Hashable {
    let device: dev_t
    let inode: ino_t
  }

  /// True when this is the first time the pair is seen — that link pays for
  /// the file, the rest count zero.
  func insert(device: dev_t, inode: ino_t) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let inserted = seen.insert(Key(device: device, inode: inode)).inserted
    if !inserted { didDedupe = true }
    return inserted
  }
}
