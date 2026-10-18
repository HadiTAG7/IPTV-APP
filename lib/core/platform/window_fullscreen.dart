import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

/// The Windows runner's window channel (`windows/runner/flutter_window.cpp`).
@visibleForTesting
const windowsWindowChannel = MethodChannel('iptv_player/window');

/// True fullscreen for the desktop app window: no title bar, covering the
/// taskbar, and back to the window's previous size and position.
///
/// The default uses media_kit_video's native helpers (GTK on Linux). On
/// Windows use [WindowFullscreen.windows]: those helpers leave a maximized
/// window maximized, and Windows keeps the taskbar over it. Both are
/// idempotent and never throw.
class WindowFullscreen {
  const WindowFullscreen({
    this.enter = defaultEnterNativeFullscreen,
    this.exit = defaultExitNativeFullscreen,
  });

  /// The runner's own fullscreen: it restores a maximized window first and
  /// maximizes it again on exit. Failures go to [onError].
  factory WindowFullscreen.windows({void Function(String message)? onError}) {
    Future<void> invoke(String method) async {
      try {
        await windowsWindowChannel.invokeMethod<void>(method);
      } on Object catch (e) {
        onError?.call('Window $method failed: $e');
      }
    }

    return WindowFullscreen(
      enter: () => invoke('enterFullscreen'),
      exit: () => invoke('exitFullscreen'),
    );
  }

  final Future<void> Function() enter;
  final Future<void> Function() exit;
}
