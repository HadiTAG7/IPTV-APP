import 'package:flutter/foundation.dart';

import '../../core/db/app_db.dart';

/// The kinds of channel list the Live screen can show.
enum LiveListKind { favorites, recent, all, category }

/// One channel list: a virtual list (Favorites, Recent, All channels) or a
/// provider category. Equal lists have the same [id].
@immutable
class LiveList {
  const LiveList._(this.kind, [this.categoryKey]);

  const LiveList.favorites() : this._(LiveListKind.favorites);
  const LiveList.recent() : this._(LiveListKind.recent);
  const LiveList.all() : this._(LiveListKind.all);
  const LiveList.category(String key) : this._(LiveListKind.category, key);

  /// The virtual lists, in the order the category pane shows them.
  static const virtual = [
    LiveList.favorites(),
    LiveList.recent(),
    LiveList.all(),
  ];

  final LiveListKind kind;

  /// The provider category key ([LiveListKind.category] only).
  final String? categoryKey;

  bool get isCategory => kind == LiveListKind.category;

  /// Stable text id, e.g. `all` or `cat:News` (also what is saved).
  String get id => switch (kind) {
    LiveListKind.favorites => 'fav',
    LiveListKind.recent => 'recent',
    LiveListKind.all => 'all',
    LiveListKind.category => 'cat:$categoryKey',
  };

  /// The list saved as [id], or null for an unknown id.
  static LiveList? fromId(String? id) => switch (id) {
    'fav' => const LiveList.favorites(),
    'recent' => const LiveList.recent(),
    'all' => const LiveList.all(),
    final String s when s.startsWith('cat:') && s.length > 4 =>
      LiveList.category(s.substring(4)),
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is LiveList && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LiveList($id)';
}

/// A row of the category pane (or a phone chip).
@immutable
class LiveCategoryEntry {
  const LiveCategoryEntry({
    required this.list,
    required this.name,
    required this.count,
    this.hidden = false,
  });

  final LiveList list;

  /// Display name; virtual lists use a localised name.
  final String name;

  /// Channels in the list.
  final int count;
  final bool hidden;
}

/// One position of a channel list: the channel's key and its row, or a null
/// [row] when the channel is gone from the catalog (a stale favourite).
@immutable
class LiveEntry {
  const LiveEntry(this.key, this.row);

  final String key;
  final ChannelRow? row;

  bool get available => row != null;
}
