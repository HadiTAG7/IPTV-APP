#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <objbase.h>
#include <shobjidl.h>

#include <algorithm>
#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The compact window: a 16:9 client area this share of the work area's
// width, at least this wide, this far from the work area's edges (sizes in
// pixels at 96 DPI).
constexpr int kCompactWidthPercent = 30;
constexpr int kCompactMinClientWidth = 320;
constexpr int kCompactMargin = 16;

// The size of a window with |window|'s styles whose client area is
// |client_width| x |client_height| at |dpi|. AdjustWindowRectExForDpi exists
// from Windows 10 1607 on; without it the frame is the system DPI's.
SIZE WindowSizeForClient(HWND window, int client_width, int client_height,
                         UINT dpi) {
  RECT rect = {0, 0, client_width, client_height};
  const DWORD style = static_cast<DWORD>(::GetWindowLong(window, GWL_STYLE));
  const DWORD ex_style =
      static_cast<DWORD>(::GetWindowLong(window, GWL_EXSTYLE));
  using AdjustForDpi = BOOL(WINAPI*)(LPRECT, DWORD, BOOL, DWORD, UINT);
  AdjustForDpi adjust_for_dpi = nullptr;
  HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (user32 != nullptr) {
    adjust_for_dpi = reinterpret_cast<AdjustForDpi>(
        ::GetProcAddress(user32, "AdjustWindowRectExForDpi"));
  }
  if (adjust_for_dpi == nullptr ||
      !adjust_for_dpi(&rect, style, FALSE, ex_style, dpi)) {
    ::AdjustWindowRectEx(&rect, style, FALSE, ex_style);
  }
  SIZE size = {rect.right - rect.left, rect.bottom - rect.top};
  return size;
}

// Tells the taskbar to stay behind |window| while it is fullscreen, or to
// come back. Windows usually works this out by itself; this makes it sure.
void MarkFullscreenInTaskbar(HWND window, bool fullscreen) {
  ITaskbarList2* taskbar = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&taskbar)))) {
    return;
  }
  if (SUCCEEDED(taskbar->HrInit())) {
    taskbar->MarkFullscreenWindow(window, fullscreen ? TRUE : FALSE);
  }
  taskbar->Release();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "iptv_player/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "enterFullscreen") {
          EnterFullscreen();
          result->Success();
        } else if (call.method_name() == "exitFullscreen") {
          ExitFullscreen();
          result->Success();
        } else if (call.method_name() == "setAlwaysOnTop") {
          const auto* always_on_top = std::get_if<bool>(call.arguments());
          if (always_on_top == nullptr) {
            result->Error("bad-arguments", "setAlwaysOnTop expects a bool");
            return;
          }
          SetAlwaysOnTop(*always_on_top);
          result->Success();
        } else if (call.method_name() == "setTitle") {
          const auto* title = std::get_if<std::string>(call.arguments());
          if (title == nullptr) {
            result->Error("bad-arguments", "setTitle expects a string");
            return;
          }
          SetTitle(*title);
          result->Success();
        } else if (call.method_name() == "enterCompact") {
          EnterCompact();
          result->Success();
        } else if (call.method_name() == "exitCompact") {
          ExitCompact();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (window_channel_) {
    window_channel_->SetMethodCallHandler(nullptr);
    window_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_SYSCOMMAND: {
      // No maximizing, restoring, moving or sizing while fullscreen (Win+Up,
      // Win+Down, the system menu): the window has no frame and must cover
      // the monitor. Restoring from minimized stays allowed.
      const UINT command = static_cast<UINT>(wparam) & 0xFFF0;
      if (fullscreen_ && !::IsIconic(hwnd) &&
          (command == SC_MAXIMIZE || command == SC_RESTORE ||
           command == SC_MOVE || command == SC_SIZE)) {
        return 0;
      }
      break;
    }
    case WM_WINDOWPOSCHANGING: {
      // While fullscreen the window keeps covering its monitor whatever
      // Windows asks (a restore from minimized, a work-area, resolution or
      // scale change would otherwise size the maximized window to the work
      // area and show the taskbar), as Chromium does.
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      if (fullscreen_ && !::IsIconic(hwnd) &&
          (pos->flags & (SWP_NOMOVE | SWP_NOSIZE)) !=
              (SWP_NOMOVE | SWP_NOSIZE)) {
        MONITORINFO monitor = {};
        monitor.cbSize = sizeof(monitor);
        ::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                         &monitor);
        pos->x = monitor.rcMonitor.left;
        pos->y = monitor.rcMonitor.top;
        pos->cx = monitor.rcMonitor.right - monitor.rcMonitor.left;
        pos->cy = monitor.rcMonitor.bottom - monitor.rcMonitor.top;
        pos->flags &= ~(SWP_NOMOVE | SWP_NOSIZE);
      }
      break;
    }
  }
  // A restarted Explorer has a new taskbar that forgot the window is
  // fullscreen.
  static const UINT taskbar_created = ::RegisterWindowMessage(L"TaskbarCreated");
  if (message == taskbar_created && fullscreen_) {
    MarkFullscreenInTaskbar(hwnd, true);
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::EnterFullscreen() {
  HWND window = GetHandle();
  if (fullscreen_ || window == nullptr) {
    return;
  }
  // A compact window goes back to its normal placement first, so leaving
  // fullscreen brings that back rather than the small corner window.
  ExitCompact();
  fullscreen_ = true;
  // A maximized window stays maximized: restoring it first, and maximizing
  // it again on exit, makes Windows animate a small window across the
  // screen. The taskbar is told the window is fullscreen instead, as
  // Chromium does.
  style_before_fullscreen_ = ::GetWindowLong(window, GWL_STYLE);
  ex_style_before_fullscreen_ = ::GetWindowLong(window, GWL_EXSTYLE);
  ::GetWindowRect(window, &rect_before_fullscreen_);
  placement_before_fullscreen_.length = sizeof(placement_before_fullscreen_);
  ::GetWindowPlacement(window, &placement_before_fullscreen_);
  monitor_before_fullscreen_ =
      ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO before = {};
  before.cbSize = sizeof(before);
  ::GetMonitorInfo(monitor_before_fullscreen_, &before);
  work_area_before_fullscreen_ = before.rcWork;

  ::SetWindowLong(window, GWL_STYLE,
                  style_before_fullscreen_ & ~(WS_CAPTION | WS_THICKFRAME));
  ::SetWindowLong(window, GWL_EXSTYLE,
                  ex_style_before_fullscreen_ &
                      ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE |
                        WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));
  MONITORINFO monitor = {};
  monitor.cbSize = sizeof(monitor);
  ::GetMonitorInfo(::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                   &monitor);
  const RECT& area = monitor.rcMonitor;
  ::SetWindowPos(window, nullptr, area.left, area.top, area.right - area.left,
                 area.bottom - area.top,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  MarkFullscreenInTaskbar(window, true);
}

void FlutterWindow::ExitFullscreen() {
  HWND window = GetHandle();
  if (!fullscreen_ || window == nullptr) {
    return;
  }
  fullscreen_ = false;
  ::SetWindowLong(window, GWL_STYLE, style_before_fullscreen_ | WS_VISIBLE);
  ::SetWindowLong(window, GWL_EXSTYLE, ex_style_before_fullscreen_);
  const RECT& before = rect_before_fullscreen_;
  // The saved rect only fits while its monitor and work area are as they
  // were (the rect of a maximized window pokes into a neighbour monitor by
  // its invisible borders, so "some monitor" is not enough).
  HMONITOR monitor = ::MonitorFromRect(&before, MONITOR_DEFAULTTONEAREST);
  MONITORINFO now = {};
  now.cbSize = sizeof(now);
  const bool same_place =
      monitor == monitor_before_fullscreen_ &&
      ::GetMonitorInfo(monitor, &now) &&
      ::EqualRect(&now.rcWork, &work_area_before_fullscreen_);
  if (same_place) {
    ::SetWindowPos(window, nullptr, before.left, before.top,
                   before.right - before.left, before.bottom - before.top,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  } else {
    // Its monitor is gone or changed (unplugged, resolution or taskbar
    // changes while fullscreen): the saved placement brings the window
    // back onto a monitor, maximized again if it was.
    ::SetWindowPlacement(window, &placement_before_fullscreen_);
    ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED);
  }
  MarkFullscreenInTaskbar(window, false);
}

void FlutterWindow::SetAlwaysOnTop(bool always_on_top) {
  always_on_top_ = always_on_top;
  ApplyTopmost();
}

void FlutterWindow::ApplyTopmost() {
  HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }
  HWND insert_after =
      always_on_top_ || compact_ ? HWND_TOPMOST : HWND_NOTOPMOST;
  ::SetWindowPos(window, insert_after, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void FlutterWindow::SetTitle(const std::string& title) {
  HWND window = GetHandle();
  // Titles come from the app and are short; anything huge is not one.
  if (window == nullptr || title.size() > 4096) {
    return;
  }
  std::wstring wide;
  if (!title.empty()) {
    const int utf8_length = static_cast<int>(title.size());
    const int length = ::MultiByteToWideChar(CP_UTF8, 0, title.data(),
                                             utf8_length, nullptr, 0);
    if (length <= 0) {
      return;
    }
    wide.resize(static_cast<size_t>(length));
    if (::MultiByteToWideChar(CP_UTF8, 0, title.data(), utf8_length,
                              wide.data(), length) != length) {
      return;
    }
  }
  ::SetWindowTextW(window, wide.c_str());
}

void FlutterWindow::EnterCompact() {
  HWND window = GetHandle();
  if (compact_ || window == nullptr) {
    return;
  }
  // Compact is the normal captioned window, only small: fullscreen ends
  // first.
  ExitFullscreen();
  placement_before_compact_.length = sizeof(placement_before_compact_);
  if (!::GetWindowPlacement(window, &placement_before_compact_)) {
    return;
  }
  if (::IsZoomed(window) || ::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  }
  HMONITOR monitor = ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (!::GetMonitorInfo(monitor, &info)) {
    return;
  }
  const RECT& work = info.rcWork;
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const int scale = static_cast<int>(dpi);
  const int margin = ::MulDiv(kCompactMargin, scale, 96);
  const int work_width = work.right - work.left;
  const int work_height = work.bottom - work.top;
  int client_width =
      std::max(work_width * kCompactWidthPercent / 100,
               ::MulDiv(kCompactMinClientWidth, scale, 96));
  SIZE size =
      WindowSizeForClient(window, client_width, client_width * 9 / 16, dpi);
  int width = static_cast<int>(size.cx);
  int height = static_cast<int>(size.cy);
  // A tiny work area still holds the whole window (still 16:9).
  const int max_width = std::max(work_width - 2 * margin, 1);
  const int max_height = std::max(work_height - 2 * margin, 1);
  if (width > max_width || height > max_height) {
    const int frame_width = width - client_width;
    const int frame_height = height - client_width * 9 / 16;
    client_width = std::min(max_width - frame_width,
                            (max_height - frame_height) * 16 / 9);
    client_width = std::max(client_width, 16);
    size =
        WindowSizeForClient(window, client_width, client_width * 9 / 16, dpi);
    width = static_cast<int>(size.cx);
    height = static_cast<int>(size.cy);
  }
  compact_ = true;
  const int x = static_cast<int>(work.right) - margin - width;
  const int y = static_cast<int>(work.bottom) - margin - height;
  ::SetWindowPos(window, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
}

void FlutterWindow::ExitCompact() {
  HWND window = GetHandle();
  if (!compact_ || window == nullptr) {
    return;
  }
  compact_ = false;
  // Never back to minimized: compact is left from the window's own button.
  WINDOWPLACEMENT placement = placement_before_compact_;
  if (placement.showCmd == static_cast<UINT>(SW_SHOWMINIMIZED)) {
    placement.showCmd = static_cast<UINT>(SW_SHOWNORMAL);
  }
  ::SetWindowPlacement(window, &placement);
  ApplyTopmost();
}
