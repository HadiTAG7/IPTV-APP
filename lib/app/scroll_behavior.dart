import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The app's scroll behaviour.
///
/// On desktop, horizontal rows (category chips, the Favorites tabs, poster
/// rows, the player's buttons) scroll by mouse too ([MouseRowScroll]): the
/// vertical wheel moves them sideways and arrows at their ends page them.
/// Mouse dragging stays off, as Flutter has it: a click that moves by a
/// pixel would scroll the row instead of pressing the chip.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final scrollbar = super.buildScrollbar(context, child, details);
    final controller = details.controller;
    final desktop = switch (getPlatform(context)) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => true,
      _ => false,
    };
    if (!desktop ||
        controller == null ||
        axisDirectionToAxis(details.direction) != Axis.horizontal) {
      return scrollbar;
    }
    return MouseRowScroll(
      controller: controller,
      direction: details.direction,
      child: scrollbar,
    );
  }
}

/// Mouse scrolling for one horizontal scrollable: the vertical wheel moves
/// it while it can still move that way (unless a vertical page around it
/// can scroll: the page goes first), and an arrow at each end with more to
/// see pages it by most of its width.
class MouseRowScroll extends StatefulWidget {
  const MouseRowScroll({
    super.key,
    required this.controller,
    required this.direction,
    required this.child,
  });

  final ScrollController controller;

  /// [AxisDirection.right] (left to right) or [AxisDirection.left] (right
  /// to left): where the start of the row is.
  final AxisDirection direction;
  final Widget child;

  /// How long an arrow press takes to page the row.
  static const pageDuration = Duration(milliseconds: 250);

  @override
  State<MouseRowScroll> createState() => _MouseRowScrollState();
}

class _MouseRowScrollState extends State<MouseRowScroll> {
  bool _canBack = false;
  bool _canForward = false;

  ScrollPosition? get _position {
    final c = widget.controller;
    return c.hasClients && c.positions.length == 1 ? c.position : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!mounted) return;
    final p = _position;
    final ready = p != null && p.hasContentDimensions && p.hasPixels;
    final back = ready && p.pixels > p.minScrollExtent + 0.5;
    final forward = ready && p.pixels < p.maxScrollExtent - 0.5;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    // Sideways wheels and trackpads reach the row itself.
    if (delta.dy == 0 || delta.dx.abs() >= delta.dy.abs()) return;
    final p = _position;
    if (p == null || !p.hasContentDimensions || !p.hasPixels) return;
    final end = delta.dy > 0 ? p.maxScrollExtent : p.minScrollExtent;
    if ((delta.dy > 0 && p.pixels >= end) ||
        (delta.dy < 0 && p.pixels <= end)) {
      return;
    }
    // A row inside a vertical page (poster rows) leaves the wheel to the
    // page while it can still scroll; its arrows still move the row.
    final page = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (page != null &&
        page.hasContentDimensions &&
        page.hasPixels &&
        (delta.dy > 0 ? page.extentAfter > 0 : page.extentBefore > 0)) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (_position == p) p.pointerScroll(dy);
    });
  }

  void _page(int direction) {
    final p = _position;
    if (p == null || !p.hasContentDimensions || !p.hasPixels) return;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    p.animateTo(
      target,
      duration: MouseRowScroll.pageDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The start of the row is on the left for a left-to-right row.
    final startOnLeft = widget.direction == AxisDirection.right;
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) {
          if (n.depth == 0) _update();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0) _update();
            return false;
          },
          child: Stack(
            children: [
              widget.child,
              if (_canBack)
                _RowArrow(
                  key: const ValueKey('row-scroll-back'),
                  onLeft: startOnLeft,
                  onPressed: () => _page(-1),
                ),
              if (_canForward)
                _RowArrow(
                  key: const ValueKey('row-scroll-forward'),
                  onLeft: !startOnLeft,
                  onPressed: () => _page(1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round arrow over one end of a row, pointing out of it. Mouse only: it
/// never takes focus, so the remote and keyboard skip it.
class _RowArrow extends StatelessWidget {
  const _RowArrow({super.key, required this.onLeft, required this.onPressed});

  final bool onLeft;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fade = LinearGradient(
      begin: onLeft ? Alignment.centerLeft : Alignment.centerRight,
      end: onLeft ? Alignment.centerRight : Alignment.centerLeft,
      colors: const [AppColors.background, Color(0x000B0E13)],
    );
    return Positioned(
      top: 0,
      bottom: 0,
      left: onLeft ? 0 : null,
      right: onLeft ? null : 0,
      child: ExcludeFocus(
        child: SizedBox(
          width: 56,
          child: Stack(
            children: [
              // The fade lets clicks and hover through to the row; only
              // the circle is the arrow.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: fade),
                  ),
                ),
              ),
              Align(
                alignment: onLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: onPressed,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceHighest,
                          shape: BoxShape.circle,
                        ),
                        // The arrow points where its end of the row is, whatever
                        // the reading direction.
                        child: Icon(
                          onLeft ? Icons.chevron_left : Icons.chevron_right,
                          textDirection: TextDirection.ltr,
                          size: 22,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
