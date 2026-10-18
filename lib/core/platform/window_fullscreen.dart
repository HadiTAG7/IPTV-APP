import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

/// True fullscreen for the desktop app window: no title bar, covering the
/// taskbar, and back to the window's previous size and position.
///
/// The default uses media_kit_video's native helpers (Win32 on Windows,
/// GTK on Linux). Both are idempotent and never throw.
class WindowFullscreen {
  const WindowFullscreen({
    this.enter = defaultEnterNativeFullscreen,
    this.exit = defaultExitNativeFullscreen,
  });

  final Future<void> Function() enter;
  final Future<void> Function() exit;
}
