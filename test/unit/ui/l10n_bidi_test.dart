import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/theme/app_theme.dart';

/// Bidi isolate controls (LRI, RLI, FSI) and their terminator (PDI).
final _isolateOpeners = {0x2066, 0x2067, 0x2068};
const _pdi = 0x2069;

final _latinToken = RegExp(r'[A-Za-z][A-Za-z0-9:/.+\-]*');
final _arabicLetter = RegExp(r'\p{Script=Arabic}', unicode: true);

Map<String, String> _messages(String file) {
  final arb = (jsonDecode(File('lib/l10n/$file').readAsStringSync()) as Map)
      .cast<String, Object?>();
  return {
    for (final e in arb.entries)
      if (!e.key.startsWith('@')) e.key: e.value! as String,
  };
}

/// [text] laid out on one line of a [direction] paragraph in Tajawal.
TextPainter _layout(String text, TextDirection direction) => TextPainter(
  text: TextSpan(
    text: text,
    style: const TextStyle(fontFamily: kAppFontFamily, fontSize: 20),
  ),
  textDirection: direction,
)..layout(maxWidth: 1e6);

/// Left edges of the visible characters of `text[start, end)`, in logical
/// order.
List<double> _xs(TextPainter painter, String text, int start, int end) => [
  for (var i = start; i < end; i++)
    if (text[i].trim().isNotEmpty && !_isControl(text.codeUnitAt(i)))
      painter
          .getBoxesForSelection(
            TextSelection(baseOffset: i, extentOffset: i + 1),
          )
          .first
          .left,
];

bool _isControl(int unit) =>
    _isolateOpeners.contains(unit) || unit == _pdi || unit == 0x200E;

Matcher _ordered({required bool ltr}) => predicate<List<double>>((xs) {
  for (var i = 1; i < xs.length; i++) {
    if (ltr ? xs[i] <= xs[i - 1] : xs[i] >= xs[i - 1]) return false;
  }
  return true;
}, ltr ? 'drawn left to right' : 'drawn right to left');

/// Expects [fragment] (its first occurrence in [text]) to be drawn in
/// reading order for its own direction inside a [paragraph] paragraph.
void _expectFragment(
  String text,
  String fragment, {
  required TextDirection paragraph,
  required bool ltr,
  String? reason,
}) {
  final start = text.indexOf(fragment);
  expect(start, isNot(-1), reason: '"$fragment" in "$text"');
  final painter = _layout(text, paragraph);
  addTearDown(painter.dispose);
  expect(
    _xs(painter, text, start, start + fragment.length),
    _ordered(ltr: ltr),
    reason: reason ?? fragment,
  );
}

void main() {
  final arMessages = _messages('app_ar.arb');
  final enMessages = _messages('app_en.arb');
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));
  const rtl = TextDirection.rtl;
  const ltr = TextDirection.ltr;

  test('every isolate is closed in the same message', () {
    for (final (file, messages) in [('en', enMessages), ('ar', arMessages)]) {
      for (final MapEntry(:key, :value) in messages.entries) {
        var depth = 0;
        for (final unit in value.codeUnits) {
          if (_isolateOpeners.contains(unit)) depth++;
          if (unit == _pdi) depth--;
          expect(depth, greaterThanOrEqualTo(0), reason: '$file $key');
        }
        expect(depth, 0, reason: '$file $key');
      }
    }
  });

  test('the invalid-URL error shows http:// and https:// in order', () {
    final text = ar.errorInvalidUrl;
    _expectFragment(text, 'http://', paragraph: rtl, ltr: true);
    _expectFragment(text, 'https://', paragraph: rtl, ltr: true);
  });

  test('paid apps in the Arabic help text read right to left', () {
    final text = ar.helpLegalBody;
    _expectFragment(text, 'OSN+', paragraph: rtl, ltr: true);
    final painter = _layout(text, rtl);
    addTearDown(painter.dispose);
    // "شاهد VIP، TOD by beIN، stc tv، OSN+": the first item is rightmost.
    final starts = [
      for (final item in ['شاهد', 'VIP', 'TOD by beIN', 'stc tv', 'OSN+'])
        _xs(painter, text, text.indexOf(item), text.indexOf(item) + 1).single,
    ];
    expect(starts, _ordered(ltr: false));
  });

  test('Latin fragments in Arabic messages keep their order', () {
    for (final MapEntry(:key, :value) in arMessages.entries) {
      if (value.contains('{')) continue;
      final painter = _layout(value, rtl);
      addTearDown(painter.dispose);
      if (!_arabicLetter.hasMatch(value)) {
        expect(
          _xs(painter, value, 0, value.length),
          _ordered(ltr: true),
          reason: key,
        );
        continue;
      }
      for (final m in _latinToken.allMatches(value)) {
        var end = m.end;
        while (value[end - 1] == '.') {
          end--;
        }
        expect(
          _xs(painter, value, m.start, end),
          _ordered(ltr: true),
          reason: '$key: ${value.substring(m.start, end)}',
        );
      }
    }
  });

  group('user text keeps its own direction', () {
    test('Latin titles, queries, names and URLs in Arabic', () {
      _expectFragment(
        ar.liveNowTitle('News (Live)'),
        'News (Live)',
        paragraph: rtl,
        ltr: true,
      );
      _expectFragment(
        ar.liveNextTitle('Match: A vs B!'),
        'Match: A vs B!',
        paragraph: rtl,
        ltr: true,
      );
      _expectFragment(
        ar.searchNoResults('abc!'),
        'abc!',
        paragraph: rtl,
        ltr: true,
      );
      _expectFragment(
        ar.settingsDeleteSourceConfirm('My TV (2)'),
        'My TV (2)',
        paragraph: rtl,
        ltr: true,
      );
      _expectFragment(
        ar.lanOrOpen('http://192.168.1.5:8080/'),
        'http://192.168.1.5:8080/',
        paragraph: rtl,
        ltr: true,
      );
      _expectFragment(
        ar.settingsVersion('1.2.0-beta'),
        '1.2.0-beta',
        paragraph: rtl,
        ltr: true,
      );
    });

    test('Arabic titles, queries and names in English', () {
      _expectFragment(
        en.liveNowTitle('أخبار (مباشر)'),
        'أخبار (مباشر)',
        paragraph: ltr,
        ltr: false,
      );
      _expectFragment(
        en.searchNoResults('بحث!'),
        'بحث!',
        paragraph: ltr,
        ltr: false,
      );
      _expectFragment(
        en.settingsDeleteSourceConfirm('قناتي (2)'),
        'قناتي (2)',
        paragraph: ltr,
        ltr: false,
      );
    });
  });
}
