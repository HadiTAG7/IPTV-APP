#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // True fullscreen for the player, asked for on the "iptv_player/window"
  // channel (lib/core/platform/window_fullscreen.dart): no title bar or
  // borders, covering the whole monitor including the taskbar.
  void EnterFullscreen();
  void ExitFullscreen();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // The window as it was before fullscreen, restored by ExitFullscreen.
  bool fullscreen_ = false;
  LONG style_before_fullscreen_ = 0;
  LONG ex_style_before_fullscreen_ = 0;
  RECT rect_before_fullscreen_ = {};
  WINDOWPLACEMENT placement_before_fullscreen_ = {};
  // The monitor the window was on, and its work area then.
  HMONITOR monitor_before_fullscreen_ = nullptr;
  RECT work_area_before_fullscreen_ = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
