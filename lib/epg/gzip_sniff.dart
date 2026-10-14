import 'dart:async';
import 'dart:io' show gzip;

/// Gunzips [bytes] when they start with the gzip magic `1f 8b`, otherwise
/// passes them through unchanged.
///
/// Detection looks at the bytes themselves (servers often mislabel `.xml.gz`
/// as `text/xml` or vice versa), buffering until two bytes have arrived so a
/// one-byte first chunk is handled. Decompression is streaming.
Stream<List<int>> maybeGunzip(Stream<List<int>> bytes) =>
    Stream<List<int>>.eventTransformed(bytes, _SniffSink.new);

class _SniffSink implements EventSink<List<int>> {
  _SniffSink(this._out);

  final EventSink<List<int>> _out;

  /// Bytes seen before the format is known; `null` once decided.
  List<int>? _head = <int>[];

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
      final head = _head!..addAll(chunk);
      if (head.length < 2) return;
      _head = null;
      _decide(head).add(head);
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
      final head = _head;
      if (head != null) {
        // Fewer than two bytes in total: cannot be gzip.
        if (head.isNotEmpty) _out.add(head);
        _out.close();
        return;
      }
      _target!.close();
    } catch (e, s) {
      _fail(e, s);
      _out.close();
    }
  }

  Sink<List<int>> _decide(List<int> head) {
    final out = _ForwardSink(_out);
    final isGzip = head[0] == 0x1f && head[1] == 0x8b;
    return _target = isGzip ? gzip.decoder.startChunkedConversion(out) : out;
  }

  void _fail(Object error, StackTrace stackTrace) {
    _failed = true;
    _out.addError(error, stackTrace);
  }
}

class _ForwardSink implements Sink<List<int>> {
  _ForwardSink(this._out);

  final EventSink<List<int>> _out;

  @override
  void add(List<int> data) => _out.add(data);

  @override
  void close() => _out.close();
}
