import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    FlutterMethodChannel(
      name: "com.ptools.harvest/app_badge",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "setBadgeCount" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let count = max(call.arguments as? Int ?? 0, 0)
      NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
      NSApplication.shared.dockTile.display()
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    hideNativeWindowControls()
  }

  private func hideNativeWindowControls() {
    let buttonTypes: [NSWindow.ButtonType] = [
      .closeButton,
      .miniaturizeButton,
      .zoomButton,
    ]

    for type in buttonTypes {
      guard let button = self.standardWindowButton(type) else { continue }
      button.isHidden = true
    }
  }
}
