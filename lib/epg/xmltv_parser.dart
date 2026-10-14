import 'dart:convert';

import 'package:xml/xml.dart'
    show XmlDefaultEntityMapping, XmlNullEntityMapping, XmlParserException;
import 'package:xml/xml_events.dart';

import 'epg_models.dart';
import 'gzip_sniff.dart';
import 'xmltv_time.dart';

/// One slice of parser output, holding at most `batchSize` items in total.
class XmltvBatch {
  const XmltvBatch({required this.channels, required this.programmes});

  final List<EpgChannel> channels;
  final List<EpgProgramme> programmes;
}

/// Streaming XMLTV reader for guides of any size.
///
/// Bytes go through [maybeGunzip], a lenient UTF-8 decoder and package:xml's
/// event parser into a small state machine; no DOM is built. Memory stays
/// flat: besides the current batch it keeps at most one held-back programme
/// and one cached shift per guide channel.
class XmltvParser {
  const XmltvParser();

  /// Parses an XMLTV document (plain or gzip) into batches.
  ///
  /// - Every `<channel>` is emitted. [wantedChannelIds] (case-insensitive)
  ///   filters programmes only, because matching and manual assignment need
  ///   the full guide channel list. `null` keeps all; an empty set keeps none.
  /// - Programme times are shifted by [shiftMinutesFor] (per channel, e.g.
  ///   `tvg-shift`) plus [offsetMinutes], then kept only when they overlap
  ///   [windowStart]..[windowEnd] (either bound may be `null`; touching an
  ///   edge does not count as overlap).
  /// - A programme without a usable `stop` (missing, invalid, or not after
  ///   `start`) ends where the next programme of the same channel starts, in
  ///   document order, or one hour after its own start when there is no later
  ///   one. It is held back until then, so output is not strictly in
  ///   document order.
  /// - `title`, `sub-title`, `desc` and `category` take the first value whose
  ///   `lang` (or its primary subtag) is earliest in [preferredLangs], else
  ///   the first value in the document.
  /// - Entities, CDATA, unknown or nested elements and a stray `<` in text
  ///   are tolerated. An element cut off by the end of input is dropped.
  Stream<XmltvBatch> parse(
    Stream<List<int>> bytes, {
    Set<String>? wantedChannelIds,
    DateTime? windowStart,
    DateTime? windowEnd,
    int batchSize = 5000,
    int Function(String channelId)? shiftMinutesFor,
    int offsetMinutes = 0,
    List<String> preferredLangs = const ['ar', 'en'],
  }) {
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be at least 1');
    }
    final machine = _XmltvMachine(
      wanted: wantedChannelIds?.map((id) => id.trim().toLowerCase()).toSet(),
      windowStart: windowStart,
      windowEnd: windowEnd,
      batchSize: batchSize,
      shiftMinutesFor: shiftMinutesFor,
      offsetMinutes: offsetMinutes,
      langs: [for (final l in preferredLangs) l.trim().toLowerCase()],
    );
    return _run(bytes, machine);
  }

  Stream<XmltvBatch> _run(
    Stream<List<int>> bytes,
    _XmltvMachine machine,
  ) async* {
    final lexer = _EventLexer(machine.handle);
    final text = maybeGunzip(bytes)
        .transform(const Utf8Decoder(allowMalformed: true));
    await for (final chunk in text) {
      lexer.add(chunk);
      for (final batch in machine.takeReady()) {
        yield batch;
      }
    }
    lexer.close();
    machine.finish();
    for (final batch in machine.takeReady()) {
      yield batch;
    }
  }
}

/// Stands in for a `<` that cannot start markup, so the XML parser reads it
/// as text; turned back into `<` when text is kept.
const _strayLt = '\uFFFF';

/// Longest incomplete markup carried between chunks before it is treated as
/// malformed. Real XMLTV elements are far smaller.
const _maxCarry = 1 << 20;

const _rawEntities = XmlNullEntityMapping();
const _entities = XmlDefaultEntityMapping.html5();

/// Feeds text chunks through package:xml's event parser.
///
/// This is the parser behind `toXmlEvents()`, driven per chunk so that markup
/// which never completes (a stray `<` in text) is emitted as text instead of
/// growing the carry-over buffer without bound. Entities are left encoded
/// here because an entity can be split across chunks; the state machine
/// decodes them once a field's text is complete.
class _EventLexer {
  _EventLexer(this._onEvent);

  final void Function(XmlEvent event) _onEvent;
  String _carry = '';

  void add(String chunk) {
    if (chunk.isEmpty) return;
    _run(_escapeStrayLt(_carry.isEmpty ? chunk : _carry + chunk), last: false);
  }

  void close() {
    if (_carry.isNotEmpty) _run(_carry, last: true);
    _carry = '';
  }

  void _run(String input, {required bool last}) {
    var buffer = input;
    for (;;) {
      var pos = 0;
      try {
        for (final event in parseEvents(
          buffer,
          entityMapping: _rawEntities,
          withLocation: true,
        )) {
          _onEvent(event);
          pos = event.stop!;
        }
        _carry = '';
        return;
      } on XmlParserException {
        // Markup at `pos` is incomplete or malformed.
      }
      final rest = buffer.substring(pos);
      if (!last && rest.length <= _maxCarry) {
        _carry = rest;
        return;
      }
      // It will never complete: its `<` is text, parsing resumes after it.
      _onEvent(XmlTextEvent(rest[0]));
      buffer = rest.substring(1);
    }
  }
}

/// Replaces each `<` that cannot be markup with [_strayLt]: one not followed
/// by a name, `/`, `!` or `?` (`a < b`), and a tag-like one with no `>`
/// before the next `<` (`x<y and z</desc>`). A `<` that cannot be decided
/// yet, at the end of [s], is left for the lexer to carry.
String _escapeStrayLt(String s) {
  var i = s.indexOf('<');
  if (i < 0) return s;
  StringBuffer? out;
  var from = 0;
  var gt = -1; // First `>` after the current `<` (s.length if none).
  final lastIndex = s.length - 1;
  while (i >= 0 && i < lastIndex) {
    final next = s.indexOf('<', i + 1);
    final c = s.codeUnitAt(i + 1);
    var stray = !_canStartMarkup(c);
    if (!stray && next >= 0 && c != 0x21 && c != 0x3f) {
      // Tags cannot contain `<`, so a tag must close before the next one.
      if (gt <= i) {
        gt = s.indexOf('>', i + 1);
        if (gt < 0) gt = s.length;
      }
      stray = gt > next;
    }
    if (stray) {
      (out ??= StringBuffer()).write(s.substring(from, i));
      out.write(_strayLt);
      from = i + 1;
    }
    i = next;
  }
  if (out == null) return s;
  out.write(s.substring(from));
  return out.toString();
}

bool _canStartMarkup(int c) =>
    (c >= 0x61 && c <= 0x7a) || // a-z
    (c >= 0x41 && c <= 0x5a) || // A-Z
    c == 0x2f || // /
    c == 0x21 || // !
    c == 0x3f || // ?
    c == 0x5f || // _
    c == 0x3a; // :

String _restoreStrayLt(String s) =>
    s.contains(_strayLt) ? s.replaceAll(_strayLt, '<') : s;

String? _attr(XmlStartElementEvent e, String name) {
  for (final a in e.attributes) {
    if (a.name == name) return _restoreStrayLt(_entities.decode(a.value));
  }
  return null;
}

enum _Context { none, channel, programme }

enum _Field { none, displayName, title, subTitle, desc, category }

/// Per-channel decisions, computed once per distinct programme `channel`.
class _ChannelRule {
  const _ChannelRule({required this.wanted, required this.shift});

  final bool wanted;
  final Duration shift;
}

const _noRank = 1 << 30;
const _defaultLength = Duration(hours: 1);

class _XmltvMachine {
  _XmltvMachine({
    required this.wanted,
    required this.windowStart,
    required this.windowEnd,
    required this.batchSize,
    required this.shiftMinutesFor,
    required this.offsetMinutes,
    required this.langs,
  });

  final Set<String>? wanted;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final int batchSize;
  final int Function(String channelId)? shiftMinutesFor;
  final int offsetMinutes;
  final List<String> langs;

  // Output.
  var _channels = <EpgChannel>[];
  var _programmes = <EpgProgramme>[];
  var _ready = <XmltvBatch>[];

  final _rules = <String, _ChannelRule>{};

  /// Programmes without a stop, by channel, waiting for the next start.
  final _pending = <String, EpgProgramme>{};

  // Element nesting.
  var _depth = 0;
  var _context = _Context.none;
  var _contextDepth = 0;
  var _contextName = '';

  // Current field and its text, kept raw until the field ends.
  var _field = _Field.none;
  var _fieldDepth = 0;
  var _fieldName = '';
  var _fieldRank = _noRank;
  final _raw = StringBuffer();
  final _text = StringBuffer();

  // Current <channel>.
  var _channelId = '';
  var _displayNames = <String>[];

  // Current <programme>; `_skip` when filtered out or unusable.
  var _skip = true;
  var _channel = '';
  DateTime _start = DateTime.utc(0);
  DateTime? _stop;
  String? _title;
  String? _subTitle;
  String? _desc;
  String? _category;
  var _titleRank = _noRank;
  var _subTitleRank = _noRank;
  var _descRank = _noRank;
  var _categoryRank = _noRank;

  // `<icon src>` of the current channel or programme.
  String? _icon;

  void handle(XmlEvent e) {
    switch (e) {
      case XmlStartElementEvent():
        _onStart(e);
      case XmlEndElementEvent():
        _onEnd(e.name);
      case XmlTextEvent():
        if (_field != _Field.none) _raw.write(e.value);
      case XmlCDATAEvent():
        if (_field != _Field.none) {
          _flushRaw();
          _text.write(e.value);
        }
      default:
        break;
    }
  }

  /// Completed batches since the last call.
  List<XmltvBatch> takeReady() {
    if (_ready.isEmpty) return const [];
    final ready = _ready;
    _ready = [];
    return ready;
  }

  /// Ends input: an unterminated element is dropped and held-back programmes
  /// get the default length.
  void finish() {
    for (final p in _pending.values) {
      _emitIfInWindow(p);
    }
    _pending.clear();
    if (_channels.isNotEmpty || _programmes.isNotEmpty) _cut();
  }

  void _onStart(XmlStartElementEvent e) {
    _depth++;
    final name = e.name;
    if (name == 'programme' || name == 'channel') {
      // A new one while another is open means the previous was not closed:
      // finish it and treat the new one as its sibling.
      if (_context != _Context.none) {
        _depth = _contextDepth;
        _endContext();
      }
      if (name == 'programme') {
        _beginProgramme(e);
      } else {
        _beginChannel(e);
      }
    } else if (_context != _Context.none &&
        _field == _Field.none &&
        _depth == _contextDepth + 1) {
      _onChild(name, e);
    }
    if (e.isSelfClosing) _onEnd(name);
  }

  /// Fields and contexts end only on their own end tag, so an unclosed child
  /// cannot swallow the rest and a stray end tag cannot end them early.
  void _onEnd(String name) {
    if (_context != _Context.none) {
      if (name == _contextName) {
        _depth = _contextDepth - 1;
        _endContext();
        return;
      }
      if (_field != _Field.none && name == _fieldName) {
        _depth = _fieldDepth - 1;
        _endField();
        return;
      }
      final floor = _field != _Field.none ? _fieldDepth : _contextDepth;
      if (_depth <= floor) return; // Stray end tag.
    }
    _depth--;
  }

  void _onChild(String name, XmlStartElementEvent e) {
    if (_context == _Context.channel) {
      switch (name) {
        case 'display-name':
          _beginField(_Field.displayName, name, 0);
        case 'icon':
          _takeIcon(e);
      }
      return;
    }
    if (_skip) return;
    switch (name) {
      case 'title':
        _beginRanked(_Field.title, name, e, _titleRank);
      case 'sub-title':
        _beginRanked(_Field.subTitle, name, e, _subTitleRank);
      case 'desc':
        _beginRanked(_Field.desc, name, e, _descRank);
      case 'category':
        _beginRanked(_Field.category, name, e, _categoryRank);
      case 'icon':
        _takeIcon(e);
    }
  }

  void _takeIcon(XmlStartElementEvent e) {
    if (_icon != null) return;
    final src = _attr(e, 'src')?.trim();
    if (src != null && src.isNotEmpty) _icon = src;
  }

  void _beginRanked(_Field f, String name, XmlStartElementEvent e, int best) {
    final rank = _langRank(_attr(e, 'lang'));
    // Only a strictly better language replaces a value already taken.
    if (rank < best) _beginField(f, name, rank);
  }

  void _beginField(_Field f, String name, int rank) {
    _field = f;
    _fieldDepth = _depth;
    _fieldName = name;
    _fieldRank = rank;
  }

  void _endField() {
    _flushRaw();
    final value = _restoreStrayLt(_text.toString()).trim();
    _text.clear();
    final field = _field;
    _field = _Field.none;
    if (value.isEmpty) return;
    switch (field) {
      case _Field.displayName:
        if (!_displayNames.contains(value)) _displayNames.add(value);
      case _Field.title:
        _title = value;
        _titleRank = _fieldRank;
      case _Field.subTitle:
        _subTitle = value;
        _subTitleRank = _fieldRank;
      case _Field.desc:
        _desc = value;
        _descRank = _fieldRank;
      case _Field.category:
        _category = value;
        _categoryRank = _fieldRank;
      case _Field.none:
        break;
    }
  }

  void _flushRaw() {
    if (_raw.isEmpty) return;
    _text.write(_entities.decode(_raw.toString()));
    _raw.clear();
  }

  int _langRank(String? lang) {
    if (lang == null) return langs.length;
    final l = lang.trim().toLowerCase();
    for (var i = 0; i < langs.length; i++) {
      final p = langs[i];
      if (l == p) return i;
      if (l.length > p.length && l.startsWith(p)) {
        final sep = l.codeUnitAt(p.length);
        if (sep == 0x2d || sep == 0x5f) return i; // '-' or '_'
      }
    }
    return langs.length;
  }

  void _beginChannel(XmlStartElementEvent e) {
    _enterContext(_Context.channel, 'channel');
    _channelId = _attr(e, 'id')?.trim() ?? '';
    _displayNames = [];
  }

  void _beginProgramme(XmlStartElementEvent e) {
    _enterContext(_Context.programme, 'programme');
    _skip = true;
    _title = _subTitle = _desc = _category = null;
    _titleRank = _subTitleRank = _descRank = _categoryRank = _noRank;

    String? channel, startText, stopText;
    for (final a in e.attributes) {
      switch (a.name) {
        case 'channel':
          channel = _restoreStrayLt(_entities.decode(a.value)).trim();
        case 'start':
          startText = a.value;
        case 'stop':
          stopText = a.value;
      }
    }
    if (channel == null || channel.isEmpty || startText == null) return;
    final rule = _ruleFor(channel);
    if (!rule.wanted) return;
    var start = parseXmltvTime(startText);
    if (start == null) return;
    var stop = stopText == null ? null : parseXmltvTime(stopText);
    if (rule.shift != Duration.zero) {
      start = start.add(rule.shift);
      stop = stop?.add(rule.shift);
    }
    if (stop != null && !stop.isAfter(start)) stop = null;

    _resolvePending(channel, start);

    final end = windowEnd;
    if (stop == null) {
      // Overlap is decided once the stop is known, unless it cannot overlap.
      if (end != null && !start.isBefore(end)) return;
    } else if (!_overlapsWindow(start, stop)) {
      return;
    }
    _skip = false;
    _channel = channel;
    _start = start;
    _stop = stop;
  }

  void _enterContext(_Context context, String name) {
    _context = context;
    _contextDepth = _depth;
    _contextName = name;
    _field = _Field.none;
    _raw.clear();
    _text.clear();
    _icon = null;
  }

  void _endContext() {
    if (_field != _Field.none) _endField();
    final context = _context;
    _context = _Context.none;
    if (context == _Context.channel) {
      if (_channelId.isEmpty) return;
      _channels.add(
        EpgChannel(id: _channelId, displayNames: _displayNames, icon: _icon),
      );
      _checkFull();
    } else if (context == _Context.programme && !_skip) {
      final stop = _stop;
      final p = EpgProgramme(
        channelId: _channel,
        start: _start,
        stop: stop ?? _start.add(_defaultLength),
        title: _title ?? '',
        subTitle: _subTitle,
        desc: _desc,
        category: _category,
        icon: _icon,
      );
      if (stop == null) {
        _pending[_channel] = p;
      } else {
        _emit(p);
      }
    }
  }

  _ChannelRule _ruleFor(String channel) =>
      _rules[channel] ??= _makeRule(channel);

  _ChannelRule _makeRule(String channel) {
    if (!(wanted?.contains(channel.toLowerCase()) ?? true)) {
      return const _ChannelRule(wanted: false, shift: Duration.zero);
    }
    final minutes = (shiftMinutesFor?.call(channel) ?? 0) + offsetMinutes;
    return _ChannelRule(wanted: true, shift: Duration(minutes: minutes));
  }

  /// Ends the held-back programme of [channel] at [nextStart] when that is
  /// later than its start; otherwise it keeps the default length.
  void _resolvePending(String channel, DateTime nextStart) {
    if (_pending.isEmpty) return;
    final p = _pending.remove(channel);
    if (p == null) return;
    if (!nextStart.isAfter(p.start)) {
      _emitIfInWindow(p);
      return;
    }
    _emitIfInWindow(
      EpgProgramme(
        channelId: p.channelId,
        start: p.start,
        stop: nextStart,
        title: p.title,
        subTitle: p.subTitle,
        desc: p.desc,
        category: p.category,
        icon: p.icon,
      ),
    );
  }

  bool _overlapsWindow(DateTime start, DateTime stop) {
    final from = windowStart;
    final to = windowEnd;
    return (from == null || stop.isAfter(from)) &&
        (to == null || start.isBefore(to));
  }

  void _emitIfInWindow(EpgProgramme p) {
    if (_overlapsWindow(p.start, p.stop)) _emit(p);
  }

  void _emit(EpgProgramme p) {
    _programmes.add(p);
    _checkFull();
  }

  void _checkFull() {
    if (_channels.length + _programmes.length >= batchSize) _cut();
  }

  void _cut() {
    _ready.add(XmltvBatch(channels: _channels, programmes: _programmes));
    _channels = [];
    _programmes = [];
  }
}
