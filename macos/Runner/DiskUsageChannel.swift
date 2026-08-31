import Cocoa
import FlutterMacOS

/// Reports what files actually occupy on disk, which Dart cannot ask for:
/// `FileStat` exposes only the logical length, while a sparse file or an
/// iCloud placeholder is charged for the blocks it really holds. `du` counts
/// blocks, so without this the file rows in Analyze would disagree with the
/// directory totals sitting right next to them.
final class DiskUsageChannel {
  static let channelName = "fit.hoopix/disk_usage"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      Self.handle(call, result: result)
    }
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "actualSizes" else {
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
          message: "actualSizes expects a `paths` list of strings",
          details: nil))
      return
    }

    // One call for the whole batch: a directory listing sizes hundreds of
    // files, and a channel round trip each would cost more than the stats.
    let sizes: [Any] = paths.map { path in
      guard let size = actualSize(of: path) else { return NSNull() }
      return NSNumber(value: size)
    }
    result(sizes)
  }

  /// The smaller of the allocated blocks and the logical length, the same
  /// rule Mole's analyzer applies: blocks reveal a sparse or placeholder
  /// file, while block rounding on a small file must not inflate it past its
  /// own length.
  ///
  /// `lstat`, not `stat`: a symlink is never followed, so its target is not
  /// counted twice.
  private static func actualSize(of path: String) -> Int64? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    guard (info.st_mode & S_IFMT) == S_IFREG else { return nil }

    let allocated = Int64(info.st_blocks) * 512
    let logical = Int64(info.st_size)
    return min(allocated, logical)
  }
}
