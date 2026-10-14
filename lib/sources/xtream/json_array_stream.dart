/// Bounded-memory decoding of huge Xtream list responses.
///
/// `get_live_streams` and friends can return tens of megabytes. Instead of
/// decoding one giant tree, [JsonArraySplitter] scans raw bytes, tracking
/// string/escape state and nesting depth, and decodes each element of the
/// top-level array on its own. UTF-8 multi-byte sequences never contain ASCII
/// bytes, so chunk boundaries can fall anywhere.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'coerce.dart';

/// Yields every object in a top-level JSON array read from [bytes].
///
/// A top-level object (`{"0":{...},"1":{...}}`, used by some panels) is
/// buffered and its values yielded. `[]`, `{}`, `null` and an empty body
/// yield nothing. Non-object elements are skipped. Malformed input throws
/// [FormatException].
Stream<Map<String, Object?>> jsonArrayStream(Stream<List<int>> bytes) async* {
  final splitter = JsonArraySplitter();
  await for (final chunk in bytes) {
    for (final item in splitter.add(chunk)) {
      yield item;
    }
  }
  for (final item in splitter.close()) {
    yield item;
  }
}

enum _Mode { start, array, whole, done }

const _space = 0x20;
const _tab = 0x09;
const _lf = 0x0A;
const _cr = 0x0D;
const _quote = 0x22;
const _backslash = 0x5C;
const _comma = 0x2C;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;

bool _isLeadingNoise(int b) =>
    b == _space ||
    b == _lf ||
    b == _cr ||
    b == _tab ||
    // UTF-8 BOM bytes.
    b == 0xEF ||
    b == 0xBB ||
    b == 0xBF;

/// Incremental splitter behind [jsonArrayStream].
class JsonArraySplitter {
  static final Converter<List<int>, Object?> _decoder = const Utf8Decoder(
    allowMalformed: true,
  ).fuse(const JsonDecoder());

  final _buf = BytesBuilder();
  var _mode = _Mode.start;
  var _depth = 0;
  var _inString = false;
  var _escape = false;

  /// Feeds one chunk; returns the objects completed by it.
  List<Map<String, Object?>> add(List<int> chunk) {
    final out = <Map<String, Object?>>[];
    var i = 0;
    if (_mode == _Mode.start) {
      while (i < chunk.length && _isLeadingNoise(chunk[i])) {
        i++;
      }
      if (i == chunk.length) return out;
      if (chunk[i] == _openBracket) {
        _mode = _Mode.array;
        _depth = 1;
        i++;
      } else {
        _mode = _Mode.whole;
      }
    }
    switch (_mode) {
      case _Mode.array:
        _scan(chunk, i, out);
      case _Mode.whole:
        _append(chunk, i, chunk.length);
      case _Mode.start:
      case _Mode.done:
        break;
    }
    return out;
  }

  /// Signals end of input; returns any remaining objects.
  List<Map<String, Object?>> close() {
    switch (_mode) {
      case _Mode.start:
      case _Mode.done:
        return const [];
      case _Mode.array:
        throw const FormatException('Unexpected end of JSON array');
      case _Mode.whole:
        _mode = _Mode.done;
        final value = _decoder.convert(_buf.takeBytes());
        if (value == null) return const [];
        if (value is! List && value is! Map) {
          throw const FormatException('Expected a JSON array or object');
        }
        return [
          for (final e in asList(value))
            if (e is Map<String, Object?>) e,
        ];
    }
  }

  void _scan(List<int> c, int from, List<Map<String, Object?>> out) {
    var start = from;
    for (var i = from; i < c.length; i++) {
      final b = c[i];
      if (_inString) {
        if (_escape) {
          _escape = false;
        } else if (b == _backslash) {
          _escape = true;
        } else if (b == _quote) {
          _inString = false;
        }
        continue;
      }
      switch (b) {
        case _quote:
          _inString = true;
        case _openBrace:
        case _openBracket:
          _depth++;
        case _closeBrace:
        case _closeBracket:
          if (_depth == 1) {
            if (b != _closeBracket) {
              throw const FormatException('Unbalanced JSON array');
            }
            _append(c, start, i);
            _emit(out);
            _depth = 0;
            _mode = _Mode.done;
            return;
          }
          _depth--;
        case _comma:
          if (_depth == 1) {
            _append(c, start, i);
            _emit(out);
            start = i + 1;
          }
      }
    }
    _append(c, start, c.length);
  }

  void _append(List<int> c, int start, int end) {
    if (end <= start) return;
    _buf.add(
      c is Uint8List
          ? Uint8List.sublistView(c, start, end)
          : c.sublist(start, end),
    );
  }

  void _emit(List<Map<String, Object?>> out) {
    final bytes = _buf.takeBytes();
    if (bytes.every(_isWhitespace)) return;
    final value = _decoder.convert(bytes);
    if (value is Map<String, Object?>) out.add(value);
  }

  static bool _isWhitespace(int b) =>
      b == _space || b == _lf || b == _cr || b == _tab;
}
