import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/engine/mpv_engine.dart';
import 'package:iptv_player/player/engine/player_engine.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:media_kit/media_kit.dart';

/// Real libmpv where it is installed (Linux dev machines); skipped elsewhere.
String? _noLibmpv() {
  if (!Platform.isLinux) return 'libmpv probe runs on Linux only';
  try {
    MediaKit.ensureInitialized();
    return null;
  } on Object catch (e) {
    return 'libmpv not installed: $e';
  }
}

void main() {
  final skip = _noLibmpv();

  late HttpServer server;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.statusCode = HttpStatus.forbidden;
      unawaited(request.response.close());
    });
  });
  tearDown(() => server.close(force: true));

  Future<ErrorEvent> openForbidden(MpvEngine engine, String name) async {
    final error = engine.events
        .where((e) => e is ErrorEvent && e.fatal)
        .cast<ErrorEvent>()
        .first;
    await engine.open(
      StreamRequest(
        url: 'http://127.0.0.1:${server.port}/s403/$name.ts',
        kind: PlayableKind.live,
      ),
    );
    return error.timeout(const Duration(seconds: 15));
  }

  test(
    'an engine right after another still gets the HTTP status',
    () async {
      final core = MpvCore(
        createPlayer: ({required lite}) => Player(
          configuration: const PlayerConfiguration(
            logLevel: MPVLogLevel.warn,
            vo: 'null',
          ),
        ),
        createVideo: (_, {required hardwareDecoding}) => null,
      );
      final first = MpvEngine(core: core);
      final a = await openForbidden(first, 'a');
      expect(a.httpStatus, 403);
      await first.dispose();
      // A second libmpv core created now would never get FFmpeg's log
      // lines, and with them the status.
      final second = MpvEngine(core: core);
      final b = await openForbidden(second, 'b');
      expect(b.httpStatus, 403);
      expect(b.message, contains('403'));
      await second.dispose();
      await core.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
