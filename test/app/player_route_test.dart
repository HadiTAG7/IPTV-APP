import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/ui/play_request.dart';
import 'package:iptv_player/player/ui/player_route.dart';
import 'package:iptv_player/player/ui/player_screen.dart';
import 'package:iptv_player/sources/models.dart';

import '../player_ui/support/player_harness.dart';

void main() {
  const channel = PlayableRef(
    kind: PlayableKind.live,
    key: '1001',
    url: 'http://127.0.0.1:9/live/1001.ts',
    title: 'Test News',
  );

  test('PlayRequest fields and copyWith', () {
    const request = PlayRequest(
      sourceId: 3,
      item: channel,
      categoryKey: 'news',
      zapKeys: ['1001', '1002'],
    );
    expect(request.isLive, isTrue);
    expect(request.kind, PlayableKind.live);
    expect(request.displayTitle, 'Test News');
    final movie = request.copyWith(
      item: const PlayableRef(kind: PlayableKind.movie, key: '2001'),
      startAt: const Duration(minutes: 5),
      title: 'Film',
    );
    expect(movie.sourceId, 3);
    expect(movie.isLive, isFalse);
    expect(movie.startAt, const Duration(minutes: 5));
    expect(movie.displayTitle, 'Film');
    expect(movie.categoryKey, 'news');
    expect('$movie', contains('movie 2001'));
  });

  testWidgets('openPlayer pushes a fullscreen PlayerScreen', (tester) async {
    final rig = PlayerRig()..autoPlay();
    final id = await seedLive(rig, count: 1);
    await pumpPlayerApp(tester, rig);
    var closed = false;
    final request = PlayRequest(sourceId: id, item: channel);
    unawaited(
      openPlayer(
        tester.element(find.byKey(launcherKey)),
        request,
      ).then((_) => closed = true),
    );
    await settle(tester);

    final screen = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
    expect(screen.request, same(request));
    expect(find.text('Test News'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(PlayerScreen)))!;
    expect(route.settings.name, kPlayerRouteName);
    expect((route as MaterialPageRoute<void>).fullscreenDialog, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    expect(closed, isTrue);
    await disposeRig(tester, rig);
  });
}
