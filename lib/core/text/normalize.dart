/// Text folding used for search and guide matching (Arabic + Latin).
///
/// Search: [normalizeForSearch]. Guide matching: [normalizeForEpg], which also
/// strips quality/country tags such as `HD`, `FHD`, `4K`, `(1080p)`, `AR:`.
library;

const _arabicIndicZero = 0x0660;
const _easternArabicIndicZero = 0x06F0;

final _spaces = RegExp(r'\s+');

/// Lower-cases Latin, removes Arabic diacritics and tatweel, folds common
/// Arabic letter variants, converts Arabic-Indic digits and collapses spaces.
String normalizeForSearch(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    final mapped = _foldRune(rune);
    if (mapped != null) out.writeCharCode(mapped);
  }
  return out.toString().toLowerCase().replaceAll(_spaces, ' ').trim();
}

int? _foldRune(int r) {
  // Harakat U+064B..U+0652, superscript alef U+0670, tatweel U+0640.
  if ((r >= 0x064B && r <= 0x0652) || r == 0x0670 || r == 0x0640) return null;
  switch (r) {
    case 0x0623: // أ
    case 0x0625: // إ
    case 0x0622: // آ
    case 0x0671: // ٱ
      return 0x0627; // ا
    case 0x0649: // ى
      return 0x064A; // ي
    case 0x0629: // ة
      return 0x0647; // ه
    case 0x0624: // ؤ
      return 0x0648; // و
    case 0x0626: // ئ
      return 0x064A; // ي
  }
  if (r >= _arabicIndicZero && r <= _arabicIndicZero + 9) {
    return 0x30 + (r - _arabicIndicZero);
  }
  if (r >= _easternArabicIndicZero && r <= _easternArabicIndicZero + 9) {
    return 0x30 + (r - _easternArabicIndicZero);
  }
  return r;
}

// Tags commonly glued to channel names by providers.
final _bracketed = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
final _prefixTag = RegExp(r'^\s*(\|[^|]{1,6}\||[a-z]{2,3}\s*[:|])\s*');
final _qualityTags = RegExp(
  r'(?<![a-z0-9])(uhd|fhd|hd|sd|hevc|h265|h264|4k|8k|1080p?|720p?|576p?|480p?|50fps|60fps|backup|vip)(?![a-z0-9])',
);
final _atTag = RegExp(r'@\w+');
final _punct = RegExp(r'''[|:\-_.,+*/\\'"!#~]''');

/// [normalizeForSearch] plus removal of quality/country tags and punctuation,
/// for matching playlist channel names against XMLTV display names.
String normalizeForEpg(String input) {
  var s = normalizeForSearch(input);
  s = s.replaceAll(_bracketed, ' ');
  // Strip repeated leading country prefixes such as "ar:" or "|sa|".
  for (var i = 0; i < 2; i++) {
    final next = s.replaceFirst(_prefixTag, '');
    if (next == s) break;
    s = next;
  }
  s = s.replaceAll(_atTag, ' ');
  s = s.replaceAll(_qualityTags, ' ');
  s = s.replaceAll(_punct, ' ');
  return s.replaceAll(_spaces, ' ').trim();
}
