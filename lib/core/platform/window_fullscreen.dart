import 'dart:async';

import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

/// The Windows runner's window channel (`windows/runner/flutter_window.cpp`),
/// also used by the detached player windows (`window_controls.dart`).
const windowsWindowChannel = MethodChannel('iptv_player/window');

/// True fullscreen for the desktop app window: no title bar, covering the
/// taskbar, and back to the window's previous size and position.
///
/// The default uses media_kit_video's native helpers (GTK on Linux). On
/// Windows use [WindowFullscreen.windows]: those helpers never tell the
/// taskbar the window is fullscreen, and Windows keeps it over a maximized
/// window. Both are idempotent and never throw.
class WindowFullscreen {
  const WindowFullscreen({
    this.enter = defaultEnterNativeFullscreen,
    this.exit = defaultExitNativeFullscreen,
  });

  /// The runner's own fullscreen, as Chromium does it: the taskbar is told
  /// the window is fullscreen, and the window comes back exactly as it was
  /// (maximized or not, without a restore animation). Failures go to
  /// [onError].
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

/// One screen's hold on the app window's fullscreen (the player, the split
/// screen). The last screen that entered fullscreen owns it, and only the
/// owner gives it back: a closing screen never undoes the fullscreen of
/// the one that opened during its exit transition, or of the one it handed
/// over to.
class WindowFullscreenHold {
  WindowFullscreenHold(this.window);

  /// The desktop window; null on Android (nothing to hold).
  final WindowFullscreen? window;

  /// The hold that entered fullscreen last.
  static WindowFullscreenHold? _owner;

  bool _on = false;

  /// Whether this screen wants the window fullscreen.
  bool get isOn => _on;

  /// Enters ([on]) or gives back fullscreen. False when nothing changed
  /// (no window, or already so).
  bool set(bool on) {
    final window = this.window;
    if (window == null || on == _on) return false;
    _on = on;
    if (on) {
      _owner = this;
      unawaited(window.enter());
    } else if (identical(_owner, this)) {
      _owner = null;
      unawaited(window.exit());
    }
    return true;
  }
}
