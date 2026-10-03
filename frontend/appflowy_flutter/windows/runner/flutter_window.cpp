#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <cwchar>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")

namespace {

constexpr char kBackgroundChannel[] = "appflowy/background";

constexpr UINT kTrayCallbackMessage = WM_APP + 0x41;
constexpr UINT kQuitMessage = WM_APP + 0x42;
constexpr UINT kRevealMessage = WM_APP + 0x43;
constexpr UINT kHideMessage = WM_APP + 0x44;
constexpr UINT kTrayIconId = 0xAF01;
constexpr UINT_PTR kQuitFallbackTimer = 0xAF02;
constexpr UINT_PTR kBackgroundWatchdogTimer = 0xAF03;
constexpr UINT kFirstMenuCommand = 0x7A00;

// Dart flushes before it asks to quit; if it never answers, quit anyway.
constexpr UINT kQuitFallbackMs = 5000;
// A window started hidden that Dart never takes charge of is shown, rather
// than left as a process nobody can see or reach.
constexpr UINT kBackgroundWatchdogMs = 60000;

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"AppFlowy";

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int length =
      MultiByteToWideChar(CP_UTF8, 0, text.data(),
                          static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), length);
  return result;
}

std::wstring ExecutablePath() {
  std::wstring path(MAX_PATH, L'\0');
  while (true) {
    const DWORD written = GetModuleFileNameW(
        nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (written == 0) {
      return std::wstring();
    }
    if (written < path.size()) {
      path.resize(written);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

bool ContainsIgnoringCase(const std::wstring& haystack,
                          const std::wstring& needle) {
  if (needle.empty() || needle.size() > haystack.size()) {
    return false;
  }
  for (size_t start = 0; start + needle.size() <= haystack.size(); ++start) {
    if (CompareStringOrdinal(haystack.c_str() + start,
                             static_cast<int>(needle.size()), needle.c_str(),
                             static_cast<int>(needle.size()),
                             TRUE) == CSTR_EQUAL) {
      return true;
    }
  }
  return false;
}

const flutter::EncodableValue* Lookup(const flutter::EncodableMap& map,
                                      const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found == map.end() ? nullptr : &found->second;
}

bool BoolOr(const flutter::EncodableMap& map, const char* key, bool fallback) {
  const auto* value = Lookup(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* flag = std::get_if<bool>(value)) {
    return *flag;
  }
  return fallback;
}

std::string StringOr(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Lookup(map, key);
  if (value == nullptr) {
    return std::string();
  }
  if (const auto* text = std::get_if<std::string>(value)) {
    return *text;
  }
  return std::string();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool started_in_background)
    : project_(project), started_in_background_(started_in_background) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  background_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kBackgroundChannel,
          &flutter::StandardMethodCodec::GetInstance());
  background_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleBackgroundCall(call, std::move(result)); });
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  if (started_in_background_) {
    SetTimer(GetHandle(), kBackgroundWatchdogTimer, kBackgroundWatchdogMs,
             nullptr);
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // https://pub.dev/packages/window_manager#windows
    // this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (background_channel_) {
    background_channel_->SetMethodCallHandler(nullptr);
    background_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleBackgroundCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  HWND hwnd = GetHandle();

  if (method == "configure") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (arguments == nullptr) {
      result->Error("bad-arguments", "configure expects a map");
      return;
    }
    keep_running_ = BoolOr(*arguments, "keepRunning", false);
    const std::string tooltip = StringOr(*arguments, "tooltip");
    tray_tooltip_ = tooltip.empty() ? L"AppFlowy" : Utf16FromUtf8(tooltip);
    tray_menu_.clear();
    if (const auto* menu = Lookup(*arguments, "menu")) {
      if (const auto* entries = std::get_if<flutter::EncodableList>(menu)) {
        for (const auto& entry : *entries) {
          const auto* item = std::get_if<flutter::EncodableMap>(&entry);
          if (item == nullptr) {
            continue;
          }
          TrayMenuItem parsed;
          parsed.separator = BoolOr(*item, "separator", false);
          parsed.id = StringOr(*item, "id");
          parsed.label = Utf16FromUtf8(StringOr(*item, "label"));
          parsed.checked = BoolOr(*item, "checked", false);
          if (parsed.separator ||
              (!parsed.id.empty() && !parsed.label.empty())) {
            tray_menu_.push_back(std::move(parsed));
          }
        }
      }
    }
    if (hwnd != nullptr) {
      KillTimer(hwnd, kBackgroundWatchdogTimer);
    }
    if (keep_running_) {
      if (tray_added_) {
        UpdateTrayIcon();
      } else {
        AddTrayIcon();
      }
    } else {
      RemoveTrayIcon();
    }
    result->Success(flutter::EncodableValue(!keep_running_ || tray_added_));
    return;
  }

  if (method == "isLaunchAtLoginEnabled") {
    result->Success(flutter::EncodableValue(IsLaunchAtLoginEnabled()));
    return;
  }

  if (method == "setLaunchAtLogin") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(call.arguments());
    const bool enabled =
        arguments != nullptr && BoolOr(*arguments, "enabled", false);
    result->Success(flutter::EncodableValue(SetLaunchAtLogin(enabled)));
    return;
  }

  // Window changes are posted rather than made here: showing a window sends
  // messages that call back into Dart, and quitting destroys the engine that
  // is running this very callback.
  if (method == "showWindow") {
    if (hwnd != nullptr) {
      PostMessage(hwnd, kRevealMessage, 0, 0);
    }
    result->Success();
    return;
  }

  if (method == "hideWindow") {
    if (hwnd != nullptr) {
      PostMessage(hwnd, kHideMessage, 0, 0);
    }
    result->Success();
    return;
  }

  if (method == "quit") {
    if (hwnd != nullptr) {
      PostMessage(hwnd, kQuitMessage, 0, 0);
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::NotifyDart(
    const std::string& method,
    std::unique_ptr<flutter::EncodableValue> arguments) {
  if (background_channel_) {
    background_channel_->InvokeMethod(method, std::move(arguments));
  }
}

void FlutterWindow::AddTrayIcon() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || tray_added_) {
    return;
  }
  if (tray_icon_ == nullptr) {
    tray_icon_ = static_cast<HICON>(LoadImageW(
        GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
        LR_DEFAULTCOLOR));
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = tray_icon_;
  wcsncpy_s(data.szTip, tray_tooltip_.c_str(), _TRUNCATE);
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &data) == TRUE;
  if (tray_added_) {
    tray_window_ = hwnd;
  }
}

void FlutterWindow::UpdateTrayIcon() {
  if (!tray_added_ || tray_window_ == nullptr) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = tray_window_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_TIP;
  wcsncpy_s(data.szTip, tray_tooltip_.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_added_ && tray_window_ != nullptr) {
    NOTIFYICONDATAW data = {};
    data.cbSize = sizeof(data);
    data.hWnd = tray_window_;
    data.uID = kTrayIconId;
    Shell_NotifyIconW(NIM_DELETE, &data);
  }
  tray_added_ = false;
  tray_window_ = nullptr;
  if (tray_icon_ != nullptr) {
    DestroyIcon(tray_icon_);
    tray_icon_ = nullptr;
  }
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  // Dart supplies translated labels; until it has, the essentials in English.
  std::vector<TrayMenuItem> items = tray_menu_;
  if (items.empty()) {
    items.push_back({"open", L"Open AppFlowy"});
    items.push_back({"quit", L"Quit AppFlowy"});
  }
  for (size_t index = 0; index < items.size(); ++index) {
    const TrayMenuItem& item = items[index];
    if (item.separator) {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    UINT flags = MF_STRING;
    if (item.checked) {
      flags |= MF_CHECKED;
    }
    AppendMenuW(menu, flags, kFirstMenuCommand + static_cast<UINT>(index),
                item.label.c_str());
  }
  if (!items.empty() && !items.front().separator) {
    SetMenuDefaultItem(menu, kFirstMenuCommand, FALSE);
  }

  POINT cursor = {};
  GetCursorPos(&cursor);
  // Without this the menu does not close when the person clicks elsewhere.
  SetForegroundWindow(hwnd);
  const UINT alignment = GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0
                             ? TPM_RIGHTALIGN
                             : TPM_LEFTALIGN;
  const UINT command = static_cast<UINT>(TrackPopupMenu(
      menu,
      TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY | TPM_BOTTOMALIGN |
          alignment,
      cursor.x, cursor.y, 0, hwnd, nullptr));
  PostMessage(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  if (command < kFirstMenuCommand) {
    return;
  }
  const size_t index = command - kFirstMenuCommand;
  if (index < items.size()) {
    RunTrayAction(items[index].id);
  }
}

void FlutterWindow::RunTrayAction(const std::string& id) {
  if (id == "open") {
    RevealWindow();
    return;
  }
  NotifyDart("onTrayAction", std::make_unique<flutter::EncodableValue>(id));
  if (id == "quit") {
    HWND hwnd = GetHandle();
    if (hwnd != nullptr) {
      SetTimer(hwnd, kQuitFallbackTimer, kQuitFallbackMs, nullptr);
    }
  }
}

void FlutterWindow::RevealWindow() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  KillTimer(hwnd, kBackgroundWatchdogTimer);
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::QuitNow() {
  if (quitting_) {
    return;
  }
  quitting_ = true;
  HWND hwnd = GetHandle();
  RemoveTrayIcon();
  if (hwnd != nullptr) {
    KillTimer(hwnd, kQuitFallbackTimer);
    KillTimer(hwnd, kBackgroundWatchdogTimer);
    DestroyWindow(hwnd);
  }
}

bool FlutterWindow::IsLaunchAtLoginEnabled() {
  DWORD size = 0;
  if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                   nullptr, nullptr, &size) != ERROR_SUCCESS ||
      size == 0) {
    return false;
  }
  std::wstring value(size / sizeof(wchar_t) + 1, L'\0');
  DWORD capacity = static_cast<DWORD>(value.size() * sizeof(wchar_t));
  if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                   nullptr, value.data(), &capacity) != ERROR_SUCCESS) {
    return false;
  }
  value.resize(wcslen(value.c_str()));
  // Another copy of AppFlowy may own the entry; it only counts when it starts
  // THIS executable.
  return ContainsIgnoringCase(value, ExecutablePath());
}

bool FlutterWindow::SetLaunchAtLogin(bool enabled) {
  if (enabled) {
    const std::wstring path = ExecutablePath();
    if (path.empty()) {
      return false;
    }
    const std::wstring command = L"\"" + path + L"\" --background";
    return RegSetKeyValueW(
               HKEY_CURRENT_USER, kRunKey, kRunValue, REG_SZ, command.c_str(),
               static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t))) ==
           ERROR_SUCCESS;
  }
  // Never remove an entry that starts some other copy of AppFlowy.
  if (!IsLaunchAtLoginEnabled()) {
    return true;
  }
  const LSTATUS status =
      RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValue);
  return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      // Closing while workflows should keep running only hides the window;
      // Quit in the notification-area menu really ends the process.
      if (keep_running_ && !quitting_) {
        ShowWindow(hwnd, SW_HIDE);
        NotifyDart("onClosedToTray");
        return 0;
      }
      break;
    case kTrayCallbackMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RevealWindow();
          break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
      }
      return 0;
    case kQuitMessage:
      QuitNow();
      return 0;
    case kRevealMessage:
      RevealWindow();
      return 0;
    case kHideMessage:
      ShowWindow(hwnd, SW_HIDE);
      return 0;
    case WM_TIMER:
      if (wparam == kQuitFallbackTimer) {
        QuitNow();
        return 0;
      }
      if (wparam == kBackgroundWatchdogTimer) {
        KillTimer(hwnd, kBackgroundWatchdogTimer);
        if (!keep_running_) {
          RevealWindow();
        }
        return 0;
      }
      break;
    case WM_SHOWWINDOW:
      if (wparam != 0 && !window_visible_) {
        window_visible_ = true;
        NotifyDart("onWindowShown");
      } else if (wparam == 0) {
        window_visible_ = false;
      }
      break;
    case WM_WINDOWPOSCHANGED: {
      const auto* position = reinterpret_cast<const WINDOWPOS*>(lparam);
      if (position != nullptr) {
        if ((position->flags & SWP_SHOWWINDOW) != 0 && !window_visible_) {
          window_visible_ = true;
          NotifyDart("onWindowShown");
        } else if ((position->flags & SWP_HIDEWINDOW) != 0) {
          window_visible_ = false;
        }
      }
      break;
    }
  }

  // Explorer restarted and took every notification-area icon with it.
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    if (keep_running_) {
      tray_added_ = false;
      AddTrayIcon();
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
