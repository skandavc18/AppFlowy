import Cocoa
import FlutterMacOS
import Security

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
      if MacOSBackgroundController.shared.isAttached {
        MacOSBackgroundController.shared.showWindow()
      } else {
        for window in sender.windows {
          window.makeKeyAndOrderFront(self)
        }
      }
    }

    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// Keychain-backed secret store (`appflowy/secure_store`) on macOS.
final class MacOSSecureSecretChannel {
  static let shared = MacOSSecureSecretChannel()
  private var channel: FlutterMethodChannel?
  private static let servicePrefix = "io.appflowy.secrets."

  func attach(to messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "appflowy/secure_store", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.channel = ch
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let scope = (args?["scope"] as? String) ?? ""
    let id = (args?["id"] as? String) ?? ""

    switch call.method {
    case "store":
      let secret = (args?["secret"] as? String) ?? ""
      let label = (args?["label"] as? String) ?? "AppFlowy: \(id)"
      guard !scope.isEmpty, !id.isEmpty else {
        result(FlutterError(code: "invalid-args", message: "scope and id are required", details: nil))
        return
      }
      if secret.isEmpty {
        deleteItem(scope: scope, id: id)
        result(nil)
        return
      }
      if let err = storeItem(scope: scope, id: id, label: label, secret: secret) {
        result(FlutterError(code: "keychain-error", message: err, details: nil))
      } else {
        result(nil)
      }
    case "lookup":
      guard !scope.isEmpty, !id.isEmpty else {
        result(nil)
        return
      }
      result(lookupItem(scope: scope, id: id))
    case "clear":
      if !scope.isEmpty && !id.isEmpty {
        deleteItem(scope: scope, id: id)
      }
      result(nil)
    case "clearAll":
      for s in ["provider", "mail"] {
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "\(Self.servicePrefix)\(s)",
        ]
        SecItemDelete(query as CFDictionary)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func storeItem(scope: String, id: String, label: String, secret: String) -> String? {
    let data = Data(secret.utf8)
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "\(Self.servicePrefix)\(scope)",
      kSecAttrAccount as String: id,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrLabel as String: label,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      return nil
    }
    if updateStatus == errSecItemNotFound {
      var addQuery = baseQuery
      for (k, v) in attributes { addQuery[k] = v }
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      return addStatus == errSecSuccess ? nil : "Keychain status \(addStatus)"
    }
    return "Keychain status \(updateStatus)"
  }

  private func lookupItem(scope: String, id: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "\(Self.servicePrefix)\(scope)",
      kSecAttrAccount as String: id,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func deleteItem(scope: String, id: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "\(Self.servicePrefix)\(scope)",
      kSecAttrAccount as String: id,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

/// Menu-bar status item, close-to-menu-bar, and LaunchAgents login startup for
/// `appflowy/background` on macOS.
final class MacOSBackgroundController: NSObject, NSWindowDelegate {
  static let shared = MacOSBackgroundController()

  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  private var keepRunning = false
  private var quitting = false
  private static let launchAgentLabel = "io.appflowy.appflowy.background"

  var isAttached: Bool { window != nil && channel != nil }

  func attach(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    window.delegate = self
    let ch = FlutterMethodChannel(name: "appflowy/background", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.channel = ch
    if CommandLine.arguments.contains("--background") {
      DispatchQueue.main.async {
        window.orderOut(nil)
      }
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard keepRunning && !quitting else {
      return true
    }
    sender.orderOut(nil)
    channel?.invokeMethod("onClosedToTray", arguments: nil)
    return false
  }

  func showWindow() {
    guard let window = window else { return }
    NSApp.activate(ignoringOtherApps: true)
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    channel?.invokeMethod("onWindowShown", arguments: nil)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      guard let args = call.arguments as? [String: Any],
            let keep = args["keepRunning"] as? Bool else {
        result(false)
        return
      }
      keepRunning = keep
      if !keep {
        removeStatusItem()
        if let window = window, !window.isVisible {
          showWindow()
        }
        result(true)
        return
      }
      let tooltip = (args["tooltip"] as? String) ?? "AppFlowy"
      let entries = (args["menu"] as? [[String: Any]]) ?? []
      installStatusItem(tooltip: tooltip, entries: entries)
      result(true)
    case "isLaunchAtLoginEnabled":
      result(FileManager.default.fileExists(atPath: launchAgentURL().path))
    case "setLaunchAtLogin":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      result(setLaunchAgent(enabled: enabled))
    case "showWindow":
      showWindow()
      result(nil)
    case "hideWindow":
      window?.orderOut(nil)
      result(nil)
    case "quit":
      quitting = true
      removeStatusItem()
      NSApp.terminate(nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installStatusItem(tooltip: String, entries: [[String: Any]]) {
    let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem = item
    if let button = item.button {
      if let appIcon = NSApp.applicationIconImage?.copy() as? NSImage {
        appIcon.size = NSSize(width: 18, height: 18)
        button.image = appIcon
      } else {
        button.title = "AF"
      }
      button.toolTip = tooltip
    }
    let menu = NSMenu()
    for entry in entries {
      if (entry["separator"] as? Bool) == true {
        menu.addItem(NSMenuItem.separator())
        continue
      }
      guard let id = entry["id"] as? String,
            let label = entry["label"] as? String,
            !id.isEmpty, !label.isEmpty else {
        continue
      }
      let menuItem = NSMenuItem(title: label, action: #selector(onMenuItemClicked(_:)), keyEquivalent: "")
      menuItem.target = self
      menuItem.representedObject = id
      if (entry["checked"] as? Bool) == true {
        menuItem.state = .on
      }
      menu.addItem(menuItem)
    }
    item.menu = menu
  }

  private func removeStatusItem() {
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  @objc private func onMenuItemClicked(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    if id == "open" {
      showWindow()
    }
    channel?.invokeMethod("onTrayAction", arguments: id)
  }

  private func launchAgentURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
      .appendingPathComponent("\(Self.launchAgentLabel).plist")
  }

  private func setLaunchAgent(enabled: Bool) -> Bool {
    let url = launchAgentURL()
    if !enabled {
      try? FileManager.default.removeItem(at: url)
      return true
    }
    guard let executable = Bundle.main.executablePath else {
      return false
    }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let plist: [String: Any] = [
        "Label": Self.launchAgentLabel,
        "ProgramArguments": [executable, "--background"],
        "RunAtLoad": true,
      ]
      let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      return false
    }
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
