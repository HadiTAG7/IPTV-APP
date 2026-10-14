/// Xtream `get_short_epg` decoding.
library;

import 'dart:convert';

import '../../epg/epg_models.dart';
import 'coerce.dart';

const _strictUtf8 = Utf8Decoder();
final _lineBreaks = RegExp(r'[\r\n]');

/// Decodes a base64 title/description; returns [s] unchanged when it is not
/// valid base64 of strict UTF-8 text.
String decodeXtreamText(String s) {
  final trimmed = s.trim().replaceAll(_lineBreaks, '');
  if (trimmed.isEmpty) return s;
  try {
    final text = _strictUtf8.convert(base64.decode(base64.normalize(trimmed)));
    return _looksLikeText(text) ? text : s;
  } on FormatException {
    return s;
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
List<EpgProgramme> parseShortEpg(Object? json, {String? channelId}) {
  final listings = asList(json is List ? json : asMap(json)['epg_listings']);
  final out = <EpgProgramme>[];
  for (final raw in listings) {
    final e = asMap(raw);
    final start = asEpoch(e['start_timestamp']);
    final stop = asEpoch(e['stop_timestamp']);
    if (start == null || stop == null || !stop.isAfter(start)) continue;
    final desc = _text(e['description']);
    out.add(
      EpgProgramme(
        channelId:
            asStr(e['channel_id']) ?? asStr(e['epg_id']) ?? channelId ?? '',
        start: start,
        stop: stop,
        title: _text(e['title']) ?? '',
        desc: desc,
      ),
    );
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

String? _text(Object? v) {
  final s = asStr(v);
  if (s == null) return null;
  final decoded = decodeXtreamText(s).trim();
  return decoded.isEmpty ? null : decoded;
}
