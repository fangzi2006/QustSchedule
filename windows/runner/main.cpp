#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\com.fangzi.qustschedule.SingleInstance";
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
// "QingKe KeBiaoTong" escaped for CP936 compatibility.
constexpr const wchar_t kAppWindowTitle[] = L"\u9752\u79D1\u8bfe\u8868\u901a";

HWND FindExistingAppWindow() {
  return ::FindWindowW(kWindowClassName, kAppWindowTitle);
}

void ActivateExistingWindow(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  } else {
    ::ShowWindow(hwnd, SW_SHOW);
  }
  ::SetForegroundWindow(hwnd);
  ::BringWindowToTop(hwnd);
}

bool AcquireSingleInstanceMutex(HANDLE* out_mutex) {
  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (mutex == nullptr) {
    // Allow startup if the OS fails to allocate a named mutex.
    *out_mutex = nullptr;
    return true;
  }

  if (::GetLastError() != ERROR_ALREADY_EXISTS) {
    *out_mutex = mutex;
    return true;
  }

  // Either another window is already running, or an updating old process is
  // currently shutting down right before relaunch.
  for (int attempt = 0; attempt < 30; ++attempt) {
    if (HWND existing = FindExistingAppWindow()) {
      ActivateExistingWindow(existing);
      ::CloseHandle(mutex);
      return false;
    }
    const DWORD wait_result = ::WaitForSingleObject(mutex, 100);
    if (wait_result == WAIT_OBJECT_0 || wait_result == WAIT_ABANDONED) {
      *out_mutex = mutex;
      return true;
    }
  }

  if (HWND existing = FindExistingAppWindow()) {
    ActivateExistingWindow(existing);
  }
  ::CloseHandle(mutex);
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex = nullptr;
  if (!AcquireSingleInstanceMutex(&single_instance_mutex)) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // Window title "QingKe KeBiaoTong" written with \u escapes: the MSVC project
  // compiles this file as the system ANSI code page (936 here) and treats
  // C4819 as an error, so raw non-ASCII bytes in this file break the build.
  if (!window.Create(kAppWindowTitle, origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::ReleaseMutex(single_instance_mutex);
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
