import 'package:iptv_player/player/detach/detached_windows.dart';
import 'package:iptv_player/player/ui/play_request.dart';

import 'player_harness.dart';

/// [DetachedWindows] that records instead of starting processes.
class RecordingDetachedWindows extends DetachedWindows {
  RecordingDetachedWindows(this.rig, {this.initial = const []});

  final PlayerRig rig;
  final List<DetachedViewer> initial;

  /// [detach] throws like a viewer that could not start.
  bool fail = false;

  /// What [playInWindow] answers.
  bool playResult = true;

  final detached = <DetachRequest>[];

  /// The engines' log when each [detach] was called.
  final engineLogAtDetach = <List<String>>[];
  final playedInWindow = <(int, PlayRequest)>[];
  final closed = <int>[];

  @override
  List<DetachedViewer> build() => initial;

  @override
  Future<int> detach(DetachRequest request) async {
    detached.add(request);
    engineLogAtDetach.add([...rig.engines.log]);
    if (fail) throw const ViewerLaunchException('start');
    return 1;
  }

  @override
  Future<bool> playInWindow(int viewerId, PlayRequest request) async {
    playedInWindow.add((viewerId, request));
    return playResult;
  }

  @override
  Future<void> close(int viewerId, {Duration? wait}) async {
    closed.add(viewerId);
    state = [
      for (final w in state)
        if (w.id != viewerId) w,
    ];
  }
}
