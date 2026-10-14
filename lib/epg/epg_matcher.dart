import '../core/text/normalize.dart';
import 'epg_models.dart';

/// How a playlist channel was linked to a guide channel, strongest first.
enum MatchKind { manual, tvgId, tvgName, name }

/// A playlist channel to link to the guide.
class MatchCandidate {
  const MatchCandidate({
    required this.key,
    required this.name,
    this.tvgId,
    this.tvgName,
  });

  /// Stable channel key (see `channels.key`).
  final String key;
  final String name;
  final String? tvgId;
  final String? tvgName;
}

/// The guide channel chosen for a playlist channel.
class EpgMatch {
  const EpgMatch(this.xmltvId, this.kind);

  /// XMLTV `channel@id`, as written in the guide.
  final String xmltvId;
  final MatchKind kind;

  @override
  bool operator ==(Object other) =>
      other is EpgMatch && other.xmltvId == xmltvId && other.kind == kind;

  @override
  int get hashCode => Object.hash(xmltvId, kind);

  @override
  String toString() => 'EpgMatch($xmltvId, ${kind.name})';
}

/// Links playlist [channels] to [guideChannels], keyed by
/// [MatchCandidate.key]; channels without a match are absent.
///
/// Per channel, the first rule that matches wins:
/// 1. [manual] override (`key` → xmltv id). An empty id means "no guide" and
///    also suppresses automatic matching. The id is kept even when this guide
///    lacks it, with the guide's spelling when it has it (case-insensitive).
/// 2. `tvg-id` equals a guide channel id, ignoring case.
/// 3. [normalizeForEpg] of `tvg-name` equals that of any display name.
/// 4. [normalizeForEpg] of the channel name equals that of any display name.
///
/// When several guide channels qualify, the first in document order wins.
/// Lookups use hash indexes, so cost is linear in the input sizes.
Map<String, EpgMatch> matchChannels(
  List<MatchCandidate> channels,
  List<EpgChannel> guideChannels, {
  Map<String, String> manual = const {},
}) {
  final byId = <String, String>{};
  final byName = <String, String>{};
  for (final g in guideChannels) {
    final id = g.id.trim();
    if (id.isEmpty) continue;
    byId.putIfAbsent(id.toLowerCase(), () => g.id);
    for (final display in g.displayNames) {
      final norm = normalizeForEpg(display);
      if (norm.isNotEmpty) byName.putIfAbsent(norm, () => g.id);
    }
  }

  String? byNormalized(String? text) {
    if (text == null) return null;
    final norm = normalizeForEpg(text);
    return norm.isEmpty ? null : byName[norm];
  }

  final result = <String, EpgMatch>{};
  for (final c in channels) {
    final override = manual[c.key]?.trim();
    if (override != null) {
      if (override.isNotEmpty) {
        final id = byId[override.toLowerCase()] ?? override;
        result[c.key] = EpgMatch(id, MatchKind.manual);
      }
      continue;
    }

    final tvgId = c.tvgId?.trim();
    if (tvgId != null && tvgId.isNotEmpty) {
      final id = byId[tvgId.toLowerCase()];
      if (id != null) {
        result[c.key] = EpgMatch(id, MatchKind.tvgId);
        continue;
      }
    }

    final tvgNameMatch = byNormalized(c.tvgName);
    if (tvgNameMatch != null) {
      result[c.key] = EpgMatch(tvgNameMatch, MatchKind.tvgName);
      continue;
    }

    // Playlists often repeat the name as tvg-name; skip the second lookup.
    if (c.name == c.tvgName) continue;
    final nameMatch = byNormalized(c.name);
    if (nameMatch != null) result[c.key] = EpgMatch(nameMatch, MatchKind.name);
  }
  return result;
}
