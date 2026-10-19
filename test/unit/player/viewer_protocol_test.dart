// The detached-window line protocol. Synthetic data only (127.0.0.1 URLs,
// made-up credentials).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/player/detach/viewer_protocol.dart';
import 'package:iptv_player/player/engine/engine_factory.dart';
import 'package:iptv_player/sources/models.dart';

const _url = 'http://127.0.0.1:9/live/viewer7/Secret-Pass-9/501.ts';

PlayMessage _play() => PlayMessage.of(
  const StreamRequest(
    url: _url,
    kind: PlayableKind.live,
    headers: {'user-agent': 'Custom/1.0', 'Referer': 'http://127.0.0.1:9/'},
    isHls: true,
  ),
  title: 'Panel News',
  logo: 'http://127.0.0.1:9/logo.png',
  channelKey: '501',
  maxConnections: 1,
  options: const EngineOptions(
    lite: true,
    hardwareDecoding: false,
    preferredLanguages: ['ara', 'en'],
    subtitleLanguages: ['en'],
  ),
  secrets: const {'viewer7', 'Secret-Pass-9', 'x'},
);

/// A connected socket pair on the loopback interface.
Future<(Socket, Socket)> _pair() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = server.first;
  final client = await Socket.connect(
    InternetAddress.loopbackIPv4,
    server.port,
  );
  final other = await accepted;
  await server.close();
  return (client, other);
}

void main() {
  group('command line', () {
    const token = 'abcdefghijklmnopqrstuvwxyz0123456789-_ABCDE';

    test('round trip, without any URL', () {
      const args = ViewerLaunchArgs(port: 50123, token: token, locale: 'ar');
      final line = args.toArgs();
      expect(line, [
        '--viewer',
        '--port=50123',
        '--token=$token',
        '--locale=ar',
      ]);
      expect(line.join(' '), isNot(contains('http')));
      final parsed = ViewerLaunchArgs.parse(line);
      expect(parsed.port, 50123);
      expect(parsed.token, token);
      expect(parsed.locale, 'ar');
      expect(ViewerLaunchArgs.isViewer(line), isTrue);
      expect(ViewerLaunchArgs.isViewer(const []), isFalse);
      // The token never shows in logs.
      expect(parsed.toString(), isNot(contains(token)));
    });

    test('a broken viewer line is refused, without echoing the token', () {
      for (final line in [
        ['--viewer'],
        ['--viewer', '--token=$token'],
        ['--viewer', '--port=0', '--token=$token'],
        ['--viewer', '--port=70000', '--token=$token'],
        ['--viewer', '--port=x', '--token=$token'],
        ['--viewer', '--port=5000'],
        ['--viewer', '--port=5000', '--token=short'],
        ['--viewer', '--port=5000', '--token=${'a' * 21}'],
        ['--viewer', '--port=5000', '--token=has spaces in it plenty long'],
        ['--port=5000', '--token=$token'],
      ]) {
        expect(
          () => ViewerLaunchArgs.parse(line),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              isNot(contains(token)),
            ),
          ),
          reason: '$line',
        );
      }
    });

    test('an unknown locale is English', () {
      final parsed = ViewerLaunchArgs.parse([
        '--viewer',
        '--port=5000',
        '--token=$token',
        '--locale=fr',
      ]);
      expect(parsed.locale, 'en');
    });

    test('tokens are long, random and fit the command line rule', () {
      final tokens = {for (var i = 0; i < 50; i++) newViewerToken()};
      expect(tokens, hasLength(50));
      for (final t in tokens) {
        // 32 random bytes: 256 bits.
        expect(base64Url.decode('$t='), hasLength(32));
        expect(
          ViewerLaunchArgs.parse(['--viewer', '--port=1', '--token=$t']).token,
          t,
        );
      }
    });

    test('token comparison', () {
      const t = 'abcdefghijklmnopqrstuvwxyz012345';
      expect(tokensMatch(t, t), isTrue);
      expect(tokensMatch(t, '${t}x'), isFalse);
      expect(tokensMatch(t, t.substring(1)), isFalse);
      expect(tokensMatch(t, 'Abcdefghijklmnopqrstuvwxyz012345'), isFalse);
      expect(tokensMatch(t, ''), isFalse);
      expect(tokensMatch(t, 'abcdefghijklmnopqrstuvwxyz012346'), isFalse);
    });
  });

  group('messages', () {
    test('every message survives a round trip', () {
      final messages = <ViewerMessage>[
        const HelloMessage(token: 'tok-123'),
        const ReadyMessage(),
        const PlayingMessage(),
        const ViewerErrorMessage('HTTP error 403 Forbidden'),
        const ClosedMessage(),
        const CloseMessage(),
        _play(),
      ];
      for (final m in messages) {
        final line = encodeViewerMessage(m);
        expect(line, endsWith('\n'));
        expect(line.indexOf('\n'), line.length - 1);
        final back = decodeViewerMessage(line.trim());
        expect(back.runtimeType, m.runtimeType);
        expect(back!.toJson(), m.toJson());
      }
    });

    test('play carries the stream, the engine options and the secrets', () {
      final back = decodeViewerMessage(encodeViewerMessage(_play()))!;
      back as PlayMessage;
      expect(back.userAgent, 'Custom/1.0');
      expect(back.headers, {'Referer': 'http://127.0.0.1:9/'});
      final stream = back.stream;
      expect(stream.url, _url);
      expect(stream.kind, PlayableKind.live);
      expect(stream.isHls, isTrue);
      expect(stream.headers, {
        'Referer': 'http://127.0.0.1:9/',
        'User-Agent': 'Custom/1.0',
      });
      final options = back.engineOptions;
      expect(options.lite, isTrue);
      expect(options.hardwareDecoding, isFalse);
      expect(options.preferredLanguages, ['ara', 'en']);
      expect(options.subtitleLanguages, ['en']);
      expect(back.title, 'Panel News');
      expect(back.channelKey, '501');
      expect(back.maxConnections, 1);
      // Too short to mask is dropped.
      expect(back.secrets, unorderedEquals(['viewer7', 'Secret-Pass-9']));
      expect(
        back.redactText('failed: $_url user viewer7'),
        isNot(anyOf(contains('Secret-Pass-9'), contains('viewer7'))),
      );
    });

    test('what the app sends always fits the limits', () {
      final play = PlayMessage.of(
        StreamRequest(
          url: _url,
          kind: PlayableKind.live,
          headers: {
            'Referer': 'http://127.0.0.1:9/',
            'X-Bad': 'a\r\nInjected: 1',
            'X-Huge': 'x' * 5000,
          },
        ),
        title: 'ق' * 600,
        logo: 'http://127.0.0.1:9/${'l' * 9000}.png',
        channelKey: '501',
        secrets: ['p' * 2000, 'Secret-Pass-9'],
      );
      final back = decodeViewerMessage(encodeViewerMessage(play));
      expect(back, isA<PlayMessage>());
      back as PlayMessage;
      expect(back.headers, {'Referer': 'http://127.0.0.1:9/'});
      expect(back.title, hasLength(512));
      expect(back.logo, isNull);
      expect(back.channelKey, '501');
      expect(back.secrets, ['Secret-Pass-9']);

      final error = decodeViewerMessage(
        encodeViewerMessage(ViewerErrorMessage('e' * 5000)),
      );
      expect((error! as ViewerErrorMessage).message, hasLength(1024));
    });

    test('nothing prints a URL or a credential', () {
      final play = _play();
      expect(play.toString(), isNot(contains('127.0.0.1')));
      expect(
        const ViewerErrorMessage(
          'failed http://u:p@127.0.0.1/get.php?username=a&password=b',
        ).toString(),
        isNot(anyOf(contains('u:p@'), contains('password=b'))),
      );
      expect(
        const HelloMessage(token: 'secret-token').toString(),
        isNot(contains('secret-token')),
      );
    });

    test('malformed lines decode to null', () {
      final ok = _play().toJson();
      Map<String, Object?> play(Map<String, Object?> change) => {
        'type': 'play',
        ...ok,
        ...change,
      };
      final lines = <String>[
        '',
        'not json',
        '[1, 2]',
        '"play"',
        '{}',
        '{"type": "launch"}',
        '{"type": 1}',
        '{"type": "hello"}',
        '{"type": "hello", "token": "", "version": 1}',
        '{"type": "hello", "token": "t", "version": "1"}',
        '{"type": "error"}',
        '{"type": "error", "message": 5}',
        jsonEncode(play({'url': null})),
        jsonEncode(play({'url': ''})),
        jsonEncode(play({'url': 'no scheme here'})),
        jsonEncode(play({'url': 'http://'})),
        jsonEncode(play({'url': 'http://h/${'x' * 9000}'})),
        jsonEncode(play({'headers': 'Referer: x'})),
        jsonEncode(
          play({
            'headers': {'Referer': 'a\r\nInjected: 1'},
          }),
        ),
        jsonEncode(
          play({
            'headers': {'Referer': 5},
          }),
        ),
        jsonEncode(play({'isHls': 'yes'})),
        jsonEncode(play({'title': null})),
        jsonEncode(play({'title': 'x' * 2000})),
        jsonEncode(play({'maxConnections': -1})),
        jsonEncode(play({'maxConnections': 1.5})),
        jsonEncode(play({'preferredLanguages': 'ara'})),
        jsonEncode(play({'preferredLanguages': List.filled(40, 'en')})),
        jsonEncode(
          play({
            'secrets': [1],
          }),
        ),
        '{"type": "play", "url": ${jsonEncode(_url)}}',
        '${'{"type":"ready","pad":"'}${'x' * kMaxViewerLineBytes}"}',
      ];
      for (final line in lines) {
        expect(
          decodeViewerMessage(line),
          isNull,
          reason: line.length > 80 ? '${line.substring(0, 80)}…' : line,
        );
      }
      // Unknown extra fields are fine.
      expect(
        decodeViewerMessage('{"type": "ready", "extra": true}'),
        isA<ReadyMessage>(),
      );
    });

    test('directions', () {
      expect(_play().fromViewer, isFalse);
      expect(const CloseMessage().fromViewer, isFalse);
      for (final m in const <ViewerMessage>[
        HelloMessage(token: 't'),
        ReadyMessage(),
        PlayingMessage(),
        ViewerErrorMessage('e'),
        ClosedMessage(),
      ]) {
        expect(m.fromViewer, isTrue, reason: m.type);
      }
    });
  });

  group('line framing', () {
    test('lines split across chunks, CR LF, bad UTF-8', () {
      final d = ViewerLineDecoder();
      expect(d.add(utf8.encode('{"a"')), isEmpty);
      expect(d.add(utf8.encode(':1}\r\n{"b":2}\nrest')), [
        '{"a":1}',
        '{"b":2}',
      ]);
      expect(d.add(utf8.encode('\n')), ['rest']);
      expect(d.add([0xFF, 0xFE, 0x0A]), [null]);
      expect(d.add(utf8.encode('قناة\n')), ['قناة']);
    });

    test('a line over the limit throws', () {
      final d = ViewerLineDecoder(maxLineBytes: 16);
      expect(d.add(utf8.encode('0123456789\n')), ['0123456789']);
      expect(d.add(utf8.encode('0123456789')), isEmpty);
      expect(
        () => d.add(utf8.encode('0123456789')),
        throwsA(isA<ViewerLineTooLong>()),
      );
      expect(
        () => ViewerLineDecoder(maxLineBytes: 4).add(utf8.encode('12345\n')),
        throwsA(isA<ViewerLineTooLong>()),
      );
    });
  });

  group('socket channel', () {
    test(
      'messages both ways; junk and misdirected lines are dropped',
      () async {
        final (a, b) = await _pair();
        final dropped = <String>[];
        final app = SocketViewerChannel(
          a,
          acceptFromViewer: true,
          onMalformed: dropped.add,
        );
        final viewer = SocketViewerChannel(b, acceptFromViewer: false);
        final atApp = <ViewerMessage>[];
        final atViewer = <ViewerMessage>[];
        app.messages.listen(atApp.add);
        viewer.messages.listen(atViewer.add);

        expect(app.send(_play()), isTrue);
        expect(viewer.send(const ReadyMessage()), isTrue);
        // A viewer may not send app messages, nor junk.
        viewer.send(const CloseMessage());
        b.write('garbage $_url\n');
        viewer.send(const PlayingMessage());
        await viewer.flush();
        await app.flush();
        await pumpEventQueue();

        expect(atViewer.single, isA<PlayMessage>());
        expect((atViewer.single as PlayMessage).stream.url, _url);
        expect(atApp.map((m) => m.type), ['ready', 'playing']);
        expect(dropped, hasLength(2));
        // The reason never carries the line (it may hold a URL).
        expect(dropped.join(), isNot(contains('Secret-Pass-9')));

        viewer.close();
        await app.done.timeout(const Duration(seconds: 5));
        expect(app.isClosed, isTrue);
        expect(app.send(const CloseMessage()), isFalse);
        expect(viewer.send(const ReadyMessage()), isFalse);
      },
    );

    test('an endless line closes the connection', () async {
      final (a, b) = await _pair();
      final dropped = <String>[];
      final app = SocketViewerChannel(
        a,
        acceptFromViewer: true,
        onMalformed: dropped.add,
        maxLineBytes: 1024,
      );
      final done = Completer<void>();
      b.listen((_) {}, onDone: done.complete, onError: (Object _) {});
      b.add(List.filled(4096, 0x41));
      await app.done.timeout(const Duration(seconds: 5));
      expect(dropped, ['line too long']);
      await done.future.timeout(const Duration(seconds: 5));
      b.destroy();
    });
  });
}
