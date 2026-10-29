import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    super.init()
    // Registered before launch finishes, so files that start AppFlowy reach it.
    addApplicationLifecycleDelegate(ExternalFileOpener.shared)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
        for window in sender.windows {
            window.makeKeyAndOrderFront(self)
        }
    }

    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// Hands the files Finder asks AppFlowy to open to Dart, which shows each one
/// in a new tab.
final class ExternalFileOpener: NSObject, FlutterAppLifecycleDelegate {
  static let shared = ExternalFileOpener()

  private var channel: FlutterMethodChannel?
  /// Paths waiting for Dart, which asks for them once it is listening.
  private var pending: [String] = []
  private var dartTakesFiles = false

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "appflowy/file_open", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "takePendingFiles" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.dartTakesFiles = true
      result(self.takePending())
    }
    self.channel = channel
    dartTakesFiles = false
  }

  func handleOpen(_ urls: [URL]) -> Bool {
    let paths = urls.filter { $0.isFileURL }.map { $0.path }
    if paths.isEmpty {
      return false
    }
    pending.append(contentsOf: paths)
    revealMainWindow()
    if dartTakesFiles, let channel = channel {
      channel.invokeMethod("openFiles", arguments: takePending())
    }
    // Anything else is left to the other delegates.
    return paths.count == urls.count
  }

  private func takePending() -> [String] {
    let paths = pending
    pending.removeAll()
    return paths
  }

  private func revealMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    for window in NSApp.windows where window is MainFlutterWindow {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.makeKeyAndOrderFront(nil)
    }
  }
}
