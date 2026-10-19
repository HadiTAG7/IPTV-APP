import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/key_repeat.dart' show arrowDirection;
import '../../widgets/dialog_click_guard.dart';
import '../connection_budget.dart';
import '../detach/detached_windows.dart';
import 'play_request.dart';
import 'player_dialogs.dart';
import 'player_screen.dart';

/// Route name of the fullscreen player.
const kPlayerRouteName = '/player';

/// How long the player takes to fade in and out.
const kPlayerFadeIn = Duration(milliseconds: 180);
const kPlayerFadeOut = Duration(milliseconds: 120);

/// Opens the fullscreen player for [request]. Completes when the player is
/// closed.
///
/// The player fades in and out quickly: the page zoom of other routes
/// looked poor over a black video surface while the desktop window enters
/// or leaves fullscreen at the same time.
///
/// When [context] is inside a home tab, the player's Guide button closes the
/// player and shows the Guide tab ([PlayerGuideScope]); elsewhere it just
/// closes the player.
///
/// The player counts against its source's connections from this call on
/// ([MainPlayerSource.hold]; the player screen takes that over), so
/// nothing else takes the connection while it waits or asks (a separate
/// window's Retry hears that the main window uses it).
///
/// Anything (a channel, a movie, an episode) whose source has no connection
/// left because detached windows use them ([connectionBudgetProvider])
/// asks first: close the (newest) window and play here, play a live
/// channel in that window instead, or cancel. A source full only because
/// of streams still stopping ([ConnectionDrains]: a split-screen tile's,
/// the last player's, or one on its way to a separate window) opens once
/// they have stopped (at most [ConnectionDrains.timeout]), after asking
/// about a window listed meanwhile. A dialog shows that wait, and Cancel
/// (or Back) drops it; a newer call drops it too and goes on with its own
/// request. While the question or the window's closing is pending, other
/// calls are ignored: they would stack a second player.
Future<void> openPlayer(BuildContext context, PlayRequest request) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final pending = container.read(_pendingOpenProvider);
  // The newest request wins over one still waiting for streams to stop.
  pending.wait?.cancel();
  if (pending.asking) return;
  final hold = Object();
  final player = container.read(mainPlayerSourceProvider.notifier)
    ..hold(hold, request.sourceId);
  try {
    if (_othersOf(container).waitsForStops(request.sourceId)) {
      final wait = _StopsWait();
      pending.wait = wait;
      final bool go;
      try {
        go = await _waitForStops(context, container, request.sourceId, wait);
      } finally {
        if (identical(pending.wait, wait)) pending.wait = null;
      }
      if (!go || !context.mounted) return;
    }
    final window = _windowInTheWay(container, request);
    if (window != null) {
      pending.asking = true;
      final bool playHere;
      try {
        playHere = await _offerWindow(context, container, request, window);
      } finally {
        pending.asking = false;
      }
      if (!playHere || !context.mounted) return;
    }
    await _pushPlayer(context, request);
  } finally {
    // The player screen holds it from its first frame (until it closes);
    // nothing opened otherwise.
    player.release(hold);
  }
}

/// What [openPlayer] has pending (one per provider container).
class _PendingOpen {
  /// Waiting for streams still stopping ([_waitForStops]).
  _StopsWait? wait;

  /// Asking about a detached window, or waiting for one to close.
  bool asking = false;
}

final _pendingOpenProvider = Provider<_PendingOpen>(
  (ref) => _PendingOpen(),
  name: '_pendingOpenProvider',
);

/// One [openPlayer] call waiting for streams still stopping, which a newer
/// call or the user cancels.
class _StopsWait {
  bool cancelled = false;

  /// Closes the dialog showing the wait, once it is shown.
  VoidCallback? _close;

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _close?.call();
  }
}

/// The connection budget without the fullscreen player: what the requested
/// player (held by [openPlayer]) has to share its source with.
ConnectionBudget _othersOf(ProviderContainer container) =>
    container.read(connectionBudgetProvider).without(player: true);

/// Waits until no stream of [sourceId] is stopping any more, with a dialog
/// that says so (it closes by itself). True when the player may go on;
/// false when [wait] was cancelled (the dialog's Cancel, Back, or a newer
/// [openPlayer] call).
Future<bool> _waitForStops(
  BuildContext context,
  ProviderContainer container,
  int sourceId,
  _StopsWait wait,
) async {
  final settled = container
      .read(connectionDrainsProvider.notifier)
      .settled(sourceId);
  final go = await showDialog<bool>(
    context: context,
    // The second click of a double click on the channel would cancel it.
    builder: (_) => DialogClickGuard(
      child: _StopsWaitDialog(settled: settled, wait: wait),
    ),
  );
  if (go != true) wait.cancelled = true;
  return !wait.cancelled;
}

/// Shows that the player waits for a stream still stopping; closes by
/// itself with true once [settled] completes (also when its wait gave up:
/// the drains' safety timeout has released the source then), with false
/// on Cancel or when [wait] is cancelled.
class _StopsWaitDialog extends StatefulWidget {
  const _StopsWaitDialog({required this.settled, required this.wait});

  final Future<bool> settled;
  final _StopsWait wait;

  @override
  State<_StopsWaitDialog> createState() => _StopsWaitDialogState();
}

class _StopsWaitDialogState extends State<_StopsWaitDialog> {
  bool _closed = false;
  final _cancelNode = FocusNode(debugLabel: 'player-wait-stops-cancel');

  @override
  void initState() {
    super.initState();
    final wait = widget.wait;
    wait._close = () => _close(false);
    unawaited(widget.settled.then((_) => _close(true)));
    // Cancelled before it was shown: it goes at once (not while building).
    if (wait.cancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(false));
    }
  }

  @override
  void dispose() {
    widget.wait._close = null;
    _cancelNode.dispose();
    super.dispose();
  }

  /// Any arrow on the message goes to Cancel, the dialog's only control.
  KeyEventResult _onMessageKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || arrowDirection(event.logicalKey) == null) {
      return KeyEventResult.ignored;
    }
    _cancelNode.requestFocus();
    return KeyEventResult.handled;
  }

  void _close(bool go) {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    // Another dialog may already be above it (a newer call's).
    if (route.isCurrent) {
      navigator.pop(go);
    } else {
      navigator.removeRoute(route, go);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('player-wait-stops'),
      title: Text(l10n.playerWaitStopsTitle),
      // Focus starts on the message, not on Cancel: OK pressed again on the
      // remote or keyboard (as for the channel) leaves the wait alone.
      // Back cancels; any arrow reaches Cancel, and none comes back.
      content: Focus(
        key: const ValueKey('player-wait-stops-message'),
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _onMessageKey,
        child: SizedBox(
          width: 360,
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Text(
                  l10n.playerWaitStopsMessage,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('player-wait-stops-cancel'),
          focusNode: _cancelNode,
          onPressed: () => _close(false),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

/// The newest detached window playing from [request]'s source when that
/// source has no connection left for the player; else null.
DetachedViewer? _windowInTheWay(
  ProviderContainer container,
  PlayRequest request,
) {
  final windows = container.read(detachedWindowsProvider);
  final others = _othersOf(container);
  if (windows.isEmpty ||
      connectionFits(container, request.sourceId, budget: others)) {
    return null;
  }
  final ids = others.viewersOn(request.sourceId);
  return windows.where((w) => ids.contains(w.id)).lastOrNull;
}

/// What to do with a request whose source's connections are all in
/// detached windows.
enum _WindowChoice { playInWindow, closeWindow }

/// Asks what to do about [window]; true when the player should open now
/// (the window was closed and has exited: its connection is free).
Future<bool> _offerWindow(
  BuildContext context,
  ProviderContainer container,
  PlayRequest request,
  DetachedViewer window,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final windows = container.read(detachedWindowsProvider.notifier);
  final live = request.isLive;
  final choice = await showPlayerChoiceDialog<_WindowChoice>(
    context,
    title: l10n.detachInUseTitle(
      window.title.isEmpty ? l10n.playerDetach : window.title,
    ),
    message: live ? l10n.detachInUseMessage : l10n.detachInUseMessageVod,
    choices: [
      // The window plays live channels only.
      if (live)
        PlayerChoice(
          value: _WindowChoice.playInWindow,
          label: l10n.detachPlayInWindow,
          icon: Icons.open_in_new,
        ),
      PlayerChoice(
        value: _WindowChoice.closeWindow,
        label: l10n.detachCloseWindow,
        icon: Icons.close,
      ),
    ],
  );
  switch (choice) {
    case null:
      return false;
    case _WindowChoice.playInWindow:
      if (!await windows.playInWindow(window.id, request)) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.detachPlayInWindowFailed)),
          );
      }
      return false;
    case _WindowChoice.closeWindow:
      // Its connection is free once it has stopped and exited.
      await windows.close(window.id);
      return true;
  }
}

Future<void> _pushPlayer(BuildContext context, PlayRequest request) {
  final openGuide = guideOpenerFor(context);
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      settings: RouteSettings(name: kPlayerRouteName, arguments: request),
      fullscreenDialog: true,
      transitionDuration: kPlayerFadeIn,
      reverseTransitionDuration: kPlayerFadeOut,
      pageBuilder: (_, _, _) => PlayerGuideScope(
        openGuide: openGuide,
        child: PlayerScreen(request: request),
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

/// Shows the Guide tab of the home shell around [context], or null when
/// [context] is not inside a home tab (e.g. a pushed page). It goes through
/// [HomeShellState.showTab], so it still works when the layout changed while
/// the player was open (a phone held in landscape swaps in the large
/// layout).
VoidCallback? guideOpenerFor(BuildContext context) {
  final shell = HomeShell.maybeOf(context);
  if (shell == null) return null;
  return () => shell.showTab(HomeTab.guide, enter: true);
}

/// Tells the player how to reach the Guide tab after it closes.
class PlayerGuideScope extends InheritedWidget {
  const PlayerGuideScope({
    super.key,
    required this.openGuide,
    required super.child,
  });

  /// Shows the Guide tab; null when the player was not opened from a home
  /// tab (its Guide button then just closes the player).
  final VoidCallback? openGuide;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerGuideScope>()?.openGuide;

  @override
  bool updateShouldNotify(PlayerGuideScope oldWidget) =>
      oldWidget.openGuide != openGuide;
}
