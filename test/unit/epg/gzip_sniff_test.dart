import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/gzip_sniff.dart';

Stream<List<int>> chunks(List<List<int>> parts) => Stream.fromIterable(parts);

/// Splits [bytes] so the first chunk has [first] bytes and the rest [size].
List<List<int>> split(List<int> bytes, {int first = 1, int size = 7}) {
  final out = <List<int>>[bytes.sublist(0, first)];
  for (var i = first; i < bytes.length; i += size) {
    out.add(
      bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
    );
  }
  return out;
}

Future<List<int>> collect(Stream<List<int>> s) async => [
  for (final c in await s.toList()) ...c,
];

void main() {
  final text = utf8.encode(
    '<?xml version="1.0"?><tv><channel id="a.example"/></tv>' * 50,
  );
  final gz = gzip.encode(text);

  group('maybeGunzip', () {
    test('passes plain bytes through unchanged', () async {
      expect(await collect(maybeGunzip(chunks([text]))), text);
      expect(await collect(maybeGunzip(chunks(split(text)))), text);
    });

    test('decompresses gzip regardless of chunking', () async {
      expect(await collect(maybeGunzip(chunks([gz]))), text);
      expect(await collect(maybeGunzip(chunks(split(gz, first: 2)))), text);
      expect(await collect(maybeGunzip(chunks(split(gz, size: 1)))), text);
    });

    test('handles a one-byte first chunk', () async {
      expect(gz[0], 0x1f);
      expect(await collect(maybeGunzip(chunks(split(gz)))), text);
      expect(await collect(maybeGunzip(chunks(split(text)))), text);
    });

    test('skips empty chunks before deciding', () async {
      final parts = [<int>[], <int>[], ...split(gz)];
      expect(await collect(maybeGunzip(chunks(parts))), text);
    });

    test('plain data starting with 0x1f is not gzip', () async {
      final bytes = [0x1f, 0x41, 0x42, 0x43];
      expect(
        await collect(
          maybeGunzip(
            chunks([
              [0x1f],
              [0x41, 0x42, 0x43],
            ]),
          ),
        ),
        bytes,
      );
    });

    test('empty and one-byte inputs pass through', () async {
      expect(await collect(maybeGunzip(chunks([]))), isEmpty);
      expect(
        await collect(
          maybeGunzip(
            chunks([
              [0x1f],
            ]),
          ),
        ),
        [0x1f],
      );
    });

    test('a gzip body that the server labelled as text is still decoded', () {
      // Headers are never consulted; only the magic bytes matter.
      expect(
        collect(maybeGunzip(chunks([gzip.encode(utf8.encode('ok'))]))),
        completion(utf8.encode('ok')),
      );
    });

    test('corrupt gzip reports an error and completes', () async {
      final corrupt = [...gz.take(10), ...List.filled(64, 0xff)];
      await expectLater(
        collect(maybeGunzip(chunks([corrupt]))),
        throwsA(isA<FormatException>()),
      );

      final errors = <Object>[];
      final done = Completer<void>();
      maybeGunzip(chunks([corrupt, corrupt]))
          .listen(null, onError: errors.add, onDone: done.complete);
      await done.future;
      expect(errors, hasLength(1));
    });

    test('truncated gzip yields the decodable prefix or an error', () async {
      final events = <Object>[];
      final done = Completer<void>();
      maybeGunzip(chunks([gz.sublist(0, gz.length ~/ 2)]))
          .listen(events.add, onError: events.add, onDone: done.complete);
      await done.future;
      final bytes = [for (final e in events) ...?(e is List<int> ? e : null)];
      expect(text.sublist(0, bytes.length), bytes);
      expect(bytes.length, lessThan(text.length));
    });

    test('forwards upstream errors', () async {
      final controller = StreamController<List<int>>();
      final result = collect(maybeGunzip(controller.stream));
      controller
        ..add(text.sublist(0, 10))
        ..addError(const SocketException('boom'));
      unawaited(controller.close());
      await expectLater(result, throwsA(isA<SocketException>()));
    });

    test('respects pause from the consumer', () async {
      final controller = StreamController<List<int>>();
      final received = <int>[];
      final sub = maybeGunzip(controller.stream).listen(received.addAll);
      final done = sub.asFuture<void>();
      controller.add(text.sublist(0, 4));
      await pumpEventQueue();
      sub.pause();
      expect(controller.isPaused, isTrue);
      sub.resume();
      expect(controller.isPaused, isFalse);
      controller.add(text.sublist(4));
      unawaited(controller.close());
      await done;
      expect(received, text);
    });
  });
}
