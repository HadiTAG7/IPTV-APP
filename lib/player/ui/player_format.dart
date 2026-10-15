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
