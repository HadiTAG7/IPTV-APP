import 'package:flutter/foundation.dart';

import '../../features/live/live_models.dart';
import '../../sources/models.dart';

/// What a screen asks the player to play.
///
/// [item] is the catalog entry (e.g. `ChannelRow.toPlayable()`); the player
/// resolves it through the source's adapter. For live TV, zapping (up/down,
/// CH+/CH-) walks [zapKeys] when given, else the channels of [categoryKey]
/// (null: all channels of the source); [list] names that list for the
/// player's channel panel.
@immutable
class PlayRequest {
  const PlayRequest({
    required this.sourceId,
    required this.item,
    this.categoryKey,
    this.zapKeys,
    this.list,
    this.startAt,
    this.seriesKey,
    this.title,
  });

  final int sourceId;
  final PlayableRef item;

  /// Category the live channel was opened from, for zapping in that list.
  final String? categoryKey;

  /// Explicit ordered channel keys to zap through (favourites, recents,
  /// search results). Takes precedence over [categoryKey].
  final List<String>? zapKeys;

  /// The Live screen list zapping walks (Favorites, one of the user's
  /// lists, Recent, All channels or a category), so the player's channel
  /// panel opens on it. Null when the zapping list is none of these (search
  /// results); the panel then works it out from [categoryKey].
  final LiveList? list;

  /// Resume position for movies and episodes.
  final Duration? startAt;

  /// Series of an episode (next-episode countdown, progress).
  final String? seriesKey;

  /// Display title; defaults to [PlayableRef.title].
  final String? title;

  PlayableKind get kind => item.kind;
  bool get isLive => item.kind == PlayableKind.live;

  /// [title], else the item's own title.
  String? get displayTitle => title ?? item.title;

  PlayRequest copyWith({
    PlayableRef? item,
    String? categoryKey,
    List<String>? zapKeys,
    LiveList? list,
    Duration? startAt,
    String? seriesKey,
    String? title,
  }) => PlayRequest(
    sourceId: sourceId,
    item: item ?? this.item,
    categoryKey: categoryKey ?? this.categoryKey,
    zapKeys: zapKeys ?? this.zapKeys,
    list: list ?? this.list,
    startAt: startAt ?? this.startAt,
    seriesKey: seriesKey ?? this.seriesKey,
    title: title ?? this.title,
  );

  @override
  String toString() =>
      'PlayRequest(source $sourceId, ${item.kind.name} ${item.key})';
}
