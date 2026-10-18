/// Xtream `get_short_epg` decoding.
library;

import 'dart:convert';

import '../../epg/epg_models.dart';
import 'coerce.dart';

const _strictUtf8 = Utf8Decoder();
final _lineBreaks = RegExp(r'[\r\n]');

/// An ordinary word: all capitals, or lower case with an optional capital
/// first letter. Words like `Kids` or `UEFA` are valid base64 by accident.
final _plainWord = RegExp(r'^(?:[A-Z]+|[A-Z]?[a-z]+)$');

/// Decodes a base64 title/description; returns [s] unchanged when it is not
/// valid base64 of strict UTF-8 text.
///
/// A lone ordinary word (`Kids`, `UEFA`) is also returned unchanged: without
/// other fields to compare with (see [parseShortEpg]) it is more likely plain
/// text than base64.
String decodeXtreamText(String s) =>
    _plainWord.hasMatch(s.trim()) ? s : (_tryDecode(s) ?? s);

String? _tryDecode(String s) {
  final trimmed = s.trim().replaceAll(_lineBreaks, '');
  if (trimmed.isEmpty) return null;
  try {
    final text = _strictUtf8.convert(base64.decode(base64.normalize(trimmed)));
    return _looksLikeText(text) ? text : null;
  } on FormatException {
    return null;
  }
}

// Rejects decodings that contain control characters (other than tab and line
// breaks): real titles never do, accidental decodings of plain words often do.
bool _looksLikeText(String text) {
  for (final c in text.codeUnits) {
    if (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) return false;
    if (c == 0x7F) return false;
  }
  return true;
}

/// Parses a `get_short_epg` (or `get_simple_data_table`) response.
///
/// Times come from `start_timestamp`/`stop_timestamp` (epoch seconds, possibly
/// strings). `epg_listings` may be a list or a map. Entries without valid times
/// are skipped. The channel id is `channel_id`, else `epg_id`, else
/// [channelId]. The result is sorted by start time.
///
/// Panels that base64-encode do so for every title and description, so the
/// choice is made once per listing: fields are decoded when at least one of
/// them decodes and is not an ordinary word. A plain-text listing of `Kids`
/// and `UEFA` is therefore kept as is.
List<EpgProgramme> parseShortEpg(Object? json, {String? channelId}) {
  final entries = [
    for (final raw in asList(json is List ? json : asMap(json)['epg_listings']))
      asMap(raw),
  ];
  final encoded = entries.any(
    (e) => [e['title'], e['description']].any((v) {
      final s = asStr(v);
      return s != null && !_plainWord.hasMatch(s) && _tryDecode(s) != null;
    }),
  );
  String? text(Object? v) {
    final s = asStr(v);
    if (s == null) return null;
    final out = unescapeGuideText(encoded ? (_tryDecode(s) ?? s) : s).trim();
    return out.isEmpty ? null : out;
  }

  final out = <EpgProgramme>[];
  for (final e in entries) {
    final start = asEpoch(e['start_timestamp']);
    final stop = asEpoch(e['stop_timestamp']);
    if (start == null || stop == null || !stop.isAfter(start)) continue;
    out.add(
      EpgProgramme(
        channelId:
            asStr(e['channel_id']) ?? asStr(e['epg_id']) ?? channelId ?? '',
        start: start,
        stop: stop,
        title: text(e['title']) ?? '',
        desc: text(e['description']),
      ),
    );
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
