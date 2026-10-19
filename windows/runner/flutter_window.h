#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

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

  // A detached player window (lib/core/platform/window_controls.dart): kept
  // on top of other windows, titled with the channel's name, or shrunk to a
  // small always-on-top window in the corner of its monitor ("compact").
  void SetAlwaysOnTop(bool always_on_top);
  void SetTitle(const std::string& title);
  void EnterCompact();
  void ExitCompact();
  // Applies the topmost state: on while compact or asked to stay on top.
  void ApplyTopmost();

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

  // SetAlwaysOnTop's choice; compact windows are on top regardless.
  bool always_on_top_ = false;
  // The window is compact; its placement before, restored by ExitCompact.
  bool compact_ = false;
  WINDOWPLACEMENT placement_before_compact_ = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
