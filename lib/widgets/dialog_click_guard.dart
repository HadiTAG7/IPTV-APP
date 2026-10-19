import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A dialog that ignores clicks, on it and beside it (it covers the
/// barrier), for [kDoubleTapTimeout] after it opens, like the in-player
/// channel panel's open guard: the click that opened it may be the first of
/// a double click. Keys work at once. [onClick], when given, gets the
/// global spot of a click on it or beside it while that click is handled
/// (a click that closes it, with a button or the barrier, has closed it by
/// then), and null after.
class DialogClickGuard extends StatefulWidget {
  const DialogClickGuard({super.key, this.onClick, required this.child});

  final ValueChanged<Offset?>? onClick;
  final Widget child;

  @override
  State<DialogClickGuard> createState() => _DialogClickGuardState();
}

class _DialogClickGuardState extends State<DialogClickGuard> {
  bool _justOpened = true;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kDoubleTapTimeout, () {
      if (mounted) setState(() => _justOpened = false);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _onPointerUp(PointerUpEvent event) {
    final onClick = widget.onClick;
    if (onClick == null) return;
    onClick(event.position);
    // After the pop (a button) or maybePop (the barrier) this click caused.
    Timer.run(() => onClick(null));
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Beside the dialog too: the barrier under it still takes the click.
    behavior: HitTestBehavior.translucent,
    onPointerUp: _onPointerUp,
    child: AbsorbPointer(absorbing: _justOpened, child: widget.child),
  );
}
