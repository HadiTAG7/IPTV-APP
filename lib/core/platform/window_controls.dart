import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'window_fullscreen.dart';

/// What a detached player window can do with its own OS window: stay on
/// top, carry the channel's name as its title, shrink to a small corner
/// window ("compact", picture in picture) and go fullscreen.
///
/// [WindowControls.native] talks to the Windows runner's window channel
/// (`windows/runner/flutter_window.cpp`); elsewhere (Linux) those calls are
/// unanswered and do nothing. All of them are idempotent and never throw.
@immutable
class WindowControls {
  const WindowControls({
    required this.setAlwaysOnTop,
    required this.setTitle,
    required this.enterCompact,
    required this.exitCompact,
    required this.fullscreen,
  });

  /// The runner's window channel for [platform] (Windows: compact, always
  /// on top and fullscreen through the runner; Linux: media_kit's GTK
  /// fullscreen, the rest no-ops). Failures go to [onError], once per
  /// method for an unanswered one.
  factory WindowControls.native({
    required TargetPlatform platform,
    void Function(String message)? onError,
  }) {
    final missing = <String>{};
    Future<void> invoke(String method, [Object? arguments]) async {
      try {
        await windowsWindowChannel.invokeMethod<void>(method, arguments);
      } on MissingPluginException {
        // No runner support (Linux, an older runner): nothing to do.
        if (missing.add(method)) onError?.call('Window $method unsupported');
      } on Object catch (e) {
        onError?.call('Window $method failed: $e');
      }
    }

    return WindowControls(
      setAlwaysOnTop: (on) => invoke('setAlwaysOnTop', on),
      setTitle: (title) => invoke('setTitle', _clip(title)),
      enterCompact: () => invoke('enterCompact'),
      exitCompact: () => invoke('exitCompact'),
      fullscreen: platform == TargetPlatform.windows
          ? WindowFullscreen.windows(onError: onError)
          : const WindowFullscreen(),
    );
  }

  /// Keeps the window above all others (or not). Compact windows stay on
  /// top whatever this says; leaving compact restores this choice.
  final Future<void> Function(bool alwaysOnTop) setAlwaysOnTop;

  /// The window's title (task bar, Alt+Tab).
  final Future<void> Function(String title) setTitle;

  /// A small 16:9 window in the corner of the work area, on top of the
  /// others. Leaves fullscreen first.
  final Future<void> Function() enterCompact;

  /// Back to the size and place the window had before [enterCompact].
  final Future<void> Function() exitCompact;

  /// True fullscreen; the runner leaves compact first.
  final WindowFullscreen fullscreen;

  /// Longest title sent to the runner.
  static const maxTitleLength = 200;

  static String _clip(String title) {
    if (title.length <= maxTitleLength) return title;
    var end = maxTitleLength - 1;
    // Never split a surrogate pair (an emoji).
    final last = title.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return '${title.substring(0, end)}…';
  }
}
