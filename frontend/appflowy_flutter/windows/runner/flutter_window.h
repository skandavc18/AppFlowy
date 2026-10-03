#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
//
// It also owns AppFlowy's life outside the window: the notification-area icon,
// closing to it instead of quitting while workflows should keep running, and
// starting with Windows. Dart drives all of it over "appflowy/background".
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |started_in_background| is true when Windows launched AppFlowy at sign-in
  // with the window hidden.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool started_in_background = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct TrayMenuItem {
    std::string id;
    std::wstring label;
    bool checked = false;
    bool separator = false;
  };

  void HandleBackgroundCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void NotifyDart(const std::string& method,
                  std::unique_ptr<flutter::EncodableValue> arguments = nullptr);

  void AddTrayIcon();
  void RemoveTrayIcon();
  void UpdateTrayIcon();
  void ShowTrayMenu();
  void RunTrayAction(const std::string& id);

  // Brings the window back from the notification area.
  void RevealWindow();
  // Ends the process: tray icon removed, window destroyed, loop quits.
  void QuitNow();

  bool SetLaunchAtLogin(bool enabled);
  bool IsLaunchAtLoginEnabled();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      background_channel_;

  bool started_in_background_ = false;
  bool keep_running_ = false;
  bool tray_added_ = false;
  bool quitting_ = false;
  bool window_visible_ = false;
  // Kept apart from the window handle: the base class clears that before
  // OnDestroy runs, and the icon must still be removed then.
  HWND tray_window_ = nullptr;
  HICON tray_icon_ = nullptr;
  std::wstring tray_tooltip_ = L"AppFlowy";
  std::vector<TrayMenuItem> tray_menu_;
  UINT taskbar_created_message_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
