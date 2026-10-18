import 'package:flutter/foundation.dart';

import '../../core/db/app_db.dart';

/// The kinds of channel list the Live screen can show.
enum LiveListKind { favorites, channelList, recent, all, category }

/// One channel list: a virtual list (Favorites, Recent, All channels), one
/// of the user's own lists or a provider category. Equal lists have the
/// same [id].
@immutable
class LiveList {
  const LiveList._(this.kind, {this.categoryKey, this.listId});

  const LiveList.favorites() : this._(LiveListKind.favorites);
  const LiveList.recent() : this._(LiveListKind.recent);
  const LiveList.all() : this._(LiveListKind.all);
  const LiveList.category(String key)
    : this._(LiveListKind.category, categoryKey: key);

  /// The user's channel list [id] (`ChannelListsDao`).
  const LiveList.channelList(int id)
    : this._(LiveListKind.channelList, listId: id);

  /// The virtual lists, in the order the category pane shows them (the
  /// user's own lists go between Favorites and Recent).
  static const virtual = [
    LiveList.favorites(),
    LiveList.recent(),
    LiveList.all(),
  ];

  final LiveListKind kind;

  /// The provider category key ([LiveListKind.category] only).
  final String? categoryKey;

  /// The channel list id ([LiveListKind.channelList] only).
  final int? listId;

  bool get isCategory => kind == LiveListKind.category;

  /// Whether this is one of the user's own lists.
  bool get isChannelList => kind == LiveListKind.channelList;

  /// Stable text id, e.g. `all`, `list:3` or `cat:News` (also what is
  /// saved).
  String get id => switch (kind) {
    LiveListKind.favorites => 'fav',
    LiveListKind.channelList => 'list:$listId',
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
    final String s when s.startsWith('list:') => _channelListFromId(s),
    _ => null,
  };

  static LiveList? _channelListFromId(String id) {
    final listId = int.tryParse(id.substring(5));
    return listId == null ? null : LiveList.channelList(listId);
  }

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
