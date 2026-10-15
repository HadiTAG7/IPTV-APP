// A scripted EpgService: records refresh calls and lets the test end runs.
import 'dart:async';

import 'package:iptv_player/epg/epg_progress.dart';
import 'package:iptv_player/epg/epg_service.dart';

typedef RefreshCall = ({int sourceId, bool force, bool lite, int refreshHours});

class FakeEpgService implements EpgService {
  /// Every refresh() call, in order.
  final calls = <RefreshCall>[];

  /// Sources needsRefresh() answers true for.
  final due = <int>{};

  /// needsRefresh() calls (source ids).
  final needsCalls = <int>[];

  final _runs = <int, StreamController<EpgProgress>>{};
  final cancelled = <int>[];

  @override
  Stream<EpgProgress> refresh(
    int sourceId, {
    bool force = false,
    bool lite = false,
    int refreshHours = 12,
  }) {
    calls.add((
      sourceId: sourceId,
      force: force,
      lite: lite,
      refreshHours: refreshHours,
    ));
    final run = _runs[sourceId] ??= StreamController<EpgProgress>.broadcast();
    return run.stream;
  }

  /// Sends [event] to the run of [sourceId].
  void emit(int sourceId, EpgProgress event) => _runs[sourceId]?.add(event);

  /// Ends the run of [sourceId] with [terminal] (default: done, 1 guide).
  Future<void> finish(int sourceId, [EpgProgress? terminal]) async {
    final run = _runs.remove(sourceId);
    if (run == null) return;
    run.add(terminal ?? EpgRefreshDone(sourceId, guides: 1, imported: 1));
    await run.close();
  }

  @override
  bool isRefreshing(int sourceId) => _runs.containsKey(sourceId);

  @override
  Future<bool> needsRefresh(int sourceId, {int refreshHours = 12}) async {
    needsCalls.add(sourceId);
    return due.contains(sourceId);
  }

  @override
  Future<void> cancel(int sourceId) async {
    cancelled.add(sourceId);
    await finish(sourceId, EpgRefreshCancelled(sourceId));
  }

  @override
  Future<void> dispose() async {
    for (final id in _runs.keys.toList()) {
      await finish(id, EpgRefreshCancelled(id));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
