import 'dart:async';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// Gunzips [bytes] when they start with the gzip magic `1f 8b`, otherwise
/// passes them through unchanged.
///
/// Detection looks at the bytes themselves (servers often mislabel `.xml.gz`
/// as `text/xml` or vice versa). Chunks are forwarded as they are, never
/// copied; only a one-byte first chunk is held until the next byte arrives.
/// Decompression is streaming.
Stream<List<int>> maybeGunzip(Stream<List<int>> bytes) =>
    Stream<List<int>>.eventTransformed(bytes, _SniffSink.new);

class _SniffSink implements EventSink<List<int>> {
  _SniffSink(this._out);

  final EventSink<List<int>> _out;

  /// The first byte, while it is the only one seen.
  int? _first;

  /// Passthrough or gzip input, chosen after the first two bytes.
  Sink<List<int>>? _target;
  bool _failed = false;

  @override
  void add(List<int> chunk) {
    if (_failed) return;
    try {
      final target = _target;
      if (target != null) {
        target.add(chunk);
        return;
      }
      if (chunk.isEmpty) return;
      final first = _first;
      if (first == null) {
        if (chunk.length == 1) {
          _first = chunk[0];
          return;
        }
        _decide(chunk[0], chunk[1]).add(chunk);
        return;
      }
      _first = null;
      _decide(first, chunk[0])
        ..add(_byte(first))
        ..add(chunk);
    } catch (e, s) {
      _fail(e, s);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() {
    if (_failed) {
      _out.close();
      return;
    }
    try {
      final target = _target;
      if (target == null) {
        // Fewer than two bytes in total: cannot be gzip.
        final first = _first;
        if (first != null) _out.add(_byte(first));
        _out.close();
        return;
      }
      target.close();
    } catch (e, s) {
      _fail(e, s);
      _out.close();
    }
  }

  Sink<List<int>> _decide(int b0, int b1) {
    final out = _ForwardSink(_out);
    final isGzip = b0 == 0x1f && b1 == 0x8b;
    return _target = isGzip ? gzip.decoder.startChunkedConversion(out) : out;
  }

  void _fail(Object error, StackTrace stackTrace) {
    _failed = true;
    _out.addError(error, stackTrace);
  }
}

Uint8List _byte(int b) => Uint8List(1)..[0] = b;

class _ForwardSink implements Sink<List<int>> {
  _ForwardSink(this._out);

  final EventSink<List<int>> _out;

  @override
  void add(List<int> data) => _out.add(data);

  @override
  void close() => _out.close();
}
