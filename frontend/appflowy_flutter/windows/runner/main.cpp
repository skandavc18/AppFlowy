#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The absolute path of the existing file |argument| names, or empty.
std::wstring RegularFilePath(const wchar_t *argument)
{
  if (argument[0] == L'\0' || argument[0] == L'-')
  {
    return std::wstring();
  }
  const DWORD capacity = ::GetFullPathNameW(argument, 0, nullptr, nullptr);
  if (capacity == 0)
  {
    return std::wstring();
  }
  std::wstring path(capacity, L'\0');
  const DWORD length =
      ::GetFullPathNameW(argument, capacity, path.data(), nullptr);
  if (length == 0 || length >= capacity)
  {
    return std::wstring();
  }
  path.resize(length);
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
  {
    return std::wstring();
  }
  return path;
}

// Splits the command line into the files it names, which Explorer passes when
// a person opens them with AppFlowy, and the rest, which go to Dart as UTF-8.
void SplitCommandLine(std::vector<std::string> *arguments,
                      std::vector<std::wstring> *files)
{
  int count = 0;
  wchar_t **argv = ::CommandLineToArgvW(::GetCommandLineW(), &count);
  if (argv == nullptr)
  {
    return;
  }
  // Skip the first argument as it's the binary name.
  for (int i = 1; i < count; i++)
  {
    std::wstring path = RegularFilePath(argv[i]);
    if (path.empty())
    {
      arguments->push_back(Utf8FromUtf16(argv[i]));
    }
    else
    {
      files->push_back(std::move(path));
    }
  }
  ::LocalFree(argv);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  std::vector<std::string> command_line_arguments;
  std::vector<std::wstring> files_to_open;
  SplitCommandLine(&command_line_arguments, &files_to_open);

  // Windows passes this when it starts AppFlowy at sign-in so workflows can
  // run: the window stays hidden behind its notification-area icon. Opening
  // files always shows it.
  const bool start_hidden =
      files_to_open.empty() && command_line != nullptr &&
      wcsstr(command_line, L"--background") != nullptr;

  HANDLE hMutexInstance = CreateMutex(NULL, TRUE, L"AppFlowyMutex");
  const bool already_running = GetLastError() == ERROR_ALREADY_EXISTS;
  HWND handle = FindWindowA(NULL, "AppFlowy");

  if (already_running)
  {
    // The running AppFlowy opens them in new tabs.
    if (!files_to_open.empty())
    {
      return FlutterWindow::SendFilesToInstance(L"AppFlowy", files_to_open)
                 ? 0
                 : EXIT_FAILURE;
    }

    // Already running. A sign-in start must not pop that window up.
    if (start_hidden)
    {
      return 0;
    }

    flutter::DartProject project(L"data");
    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
    FlutterWindow window(project);
    if (window.SendAppLinkToInstance(L"AppFlowy"))
    {
      return false;
    }

    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(handle, &place);
    ShowWindow(handle, SW_NORMAL);
    return 0;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, start_hidden);
  window.OpenFiles(files_to_open);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  if (!window.Create(L"AppFlowy", origin, size))
  {
    return EXIT_FAILURE;
  }

  if (!start_hidden)
  {
    window.Show();
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(hMutexInstance);
  return EXIT_SUCCESS;
}
