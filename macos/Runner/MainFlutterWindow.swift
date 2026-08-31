import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open wide enough for the sidebar plus two metric cards side by side;
    // narrower than this and the dashboard starts wrapping on first launch.
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1100, height: 760)
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 820, height: 560)
    self.center()

    // Hoopix draws its own chrome: the sidebar runs the full height of the
    // window and the traffic lights float over it, the way native Mac apps
    // with a source list are laid out. Dragging the background moves the
    // window, since there is no visible title bar to grab.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
