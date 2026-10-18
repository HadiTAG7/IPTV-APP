#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <objbase.h>
#include <shobjidl.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

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
