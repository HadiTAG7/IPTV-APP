import '../../core/net/redact.dart';
import '../../l10n/gen/app_localizations.dart';
import '../engine/player_engine.dart';

/// `42:10`, or `1:02:03` past an hour. Western digits in every locale (they
/// match the remote's number keys).
String formatPosition(Duration d) {
  final neg = d.isNegative;
  final total = d.abs().inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  final body = h > 0
      ? '$h:$mm:${s.toString().padLeft(2, '0')}'
      : '$mm:${s.toString().padLeft(2, '0')}';
  return neg ? '-$body' : body;
}

/// Local wall-clock time as `HH:mm`.
String formatClock(DateTime t) {
  final local = t.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// The label of an aspect ratio mode.
String aspectLabel(AppLocalizations l10n, AspectMode mode) => switch (mode) {
  AspectMode.fit => l10n.aspectFit,
  AspectMode.fill => l10n.aspectFill,
  AspectMode.stretch => l10n.aspectStretch,
  AspectMode.ratio16x9 => l10n.aspect16x9,
  AspectMode.ratio4x3 => l10n.aspect4x3,
};

/// The display name of an engine.
String engineLabel(AppLocalizations l10n, EngineKind? kind) => switch (kind) {
  EngineKind.exo => l10n.engineExo,
  EngineKind.mpv => l10n.engineMpv,
  null => '-',
};

final _urlPattern = RegExp(
  // Up to whitespace, quotes (\x22, \x27) or angle brackets.
  r'\b([a-z][a-z0-9+.-]*)://([^\s\x22\x27<>]+)',
  caseSensitive: false,
);
final _trailingPunctuation = RegExp(r'[.,;:!?)\]}]+$');
final _pathStart = RegExp('[/?#]');
final _extension = RegExp(r'\.([a-z0-9]{1,5})$', caseSensitive: false);

/// [text] with every URL cut down to its scheme, host and port, plus the
/// file extension of its path: `http://host:8080/***.ts`.
///
/// For reports and on-screen details. Stream URLs of Xtream playlists carry
/// the account as bare path segments (`http://host/user/pass/123.ts`), which
/// [redact] cannot recognise without the source's secrets (an imported M3U
/// file has none), so no path or query is shown at all.
String hideUrlPaths(String text) => text.replaceAllMapped(_urlPattern, (m) {
  var url = m[2]!;
  final tail = _trailingPunctuation.firstMatch(url)?.group(0) ?? '';
  url = url.substring(0, url.length - tail.length);
  final cut = url.indexOf(_pathStart);
  final authority = cut < 0 ? url : url.substring(0, cut);
  final rest = cut < 0 ? '' : url.substring(cut);
  final host = authority.substring(authority.lastIndexOf('@') + 1);
  if (rest.isEmpty || rest == '/') return '${m[1]}://$host$rest$tail';
  final path = rest.split(RegExp('[?#]')).first;
  final ext = _extension.firstMatch(path)?.group(1);
  return '${m[1]}://$host/$redactedMark${ext == null ? '' : '.$ext'}$tail';
});
