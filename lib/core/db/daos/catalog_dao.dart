import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../../text/normalize.dart';
import '../app_db.dart';
import 'query_utils.dart';

const _allKinds = {ContentKind.live, ContentKind.movie, ContentKind.series};

/// Catalog writes (generation swap) and paged catalog reads.
///
/// A sync writes one new generation per source:
///
/// ```dart
/// final gen = await catalog.beginGeneration(sourceId);
/// await catalog.upsertCategories(sourceId, gen, categories);
/// await catalog.upsertChannels(sourceId, gen, batch); // many short batches
/// await catalog.commitGeneration(sourceId, gen); // or abortGeneration
/// ```
///
/// Each upsert is its own short transaction, so the UI and user-data writes
/// keep working during a sync. Readers only see the committed generation:
/// category paging filters `category_items` by `sources.generation`, and list
/// and search queries hide rows whose `firstGen` is not committed yet.
/// Rows that already existed are updated in place, so their data may refresh
/// before the commit. Favourites, progress, prefs, recent channels and the
/// EPG map are never touched here.
///
/// One open generation per source at a time; calls for the same source must
/// not run concurrently.
class CatalogDao extends DatabaseAccessor<AppDatabase> {
  CatalogDao(super.attachedDatabase);

  /// Next free position per (kind, categoryKey) of each open generation.
  final _open = <(int, int), Map<(ContentKind, String), int>>{};

  // -------------------------------------------------------------------------
  // Generation swap.

  /// Starts generation `committed + 1` and returns it. Leftovers of an
  /// interrupted sync (rows above the committed generation) are discarded.
  Future<int> beginGeneration(int sourceId) async {
    final gen = await transaction(() async {
      final current = await committedGeneration(sourceId);
      await _discardAbove(sourceId, current);
      return current + 1;
    });
    _open.removeWhere((k, _) => k.$1 == sourceId);
    _open[(sourceId, gen)] = {};
    return gen;
  }

  /// Same as [beginGeneration], wrapped in a session object.
  Future<CatalogWriteSession> openGeneration(int sourceId) async =>
      CatalogWriteSession._(this, sourceId, await beginGeneration(sourceId));

  Future<void> upsertCategories(
    int sourceId,
    int gen,
    List<CategoryData> items,
  ) async {
    if (items.isEmpty) return;
    await _counters(sourceId, gen);
    await batch((b) {
      for (final c in items) {
        final row = categoryCompanion(sourceId, gen, c);
        b.insert(
          db.categories,
          row,
          onConflict: DoUpdate(
            (_) => row.copyWith(firstGen: const Value.absent()),
          ),
        );
      }
    });
  }

  Future<void> upsertChannels(int sourceId, int gen, List<ChannelData> items) =>
      _upsertItems(
        sourceId,
        gen,
        ContentKind.live,
        items,
        (c) => c.key,
        (c) => c.categoryKeys,
        (b, c) {
          final row = channelCompanion(sourceId, gen, c);
          b.insert(
            db.channels,
            row,
            onConflict: DoUpdate(
              (_) => row.copyWith(firstGen: const Value.absent()),
            ),
          );
        },
      );

  Future<void> upsertMovies(int sourceId, int gen, List<MovieData> items) =>
      _upsertItems(
        sourceId,
        gen,
        ContentKind.movie,
        items,
        (m) => m.key,
        (m) => m.categoryKeys,
        (b, m) {
          final row = movieCompanion(sourceId, gen, m);
          b.insert(
            db.movies,
            row,
            onConflict: DoUpdate(
              (_) => row.copyWith(firstGen: const Value.absent()),
            ),
          );
        },
      );

  Future<void> upsertSeries(int sourceId, int gen, List<SeriesData> items) =>
      _upsertItems(
        sourceId,
        gen,
        ContentKind.series,
        items,
        (s) => s.key,
        (s) => s.categoryKeys,
        (b, s) {
          final row = seriesCompanion(sourceId, gen, s);
          b.insert(
            db.series,
            row,
            onConflict: DoUpdate(
              (_) => row.copyWith(firstGen: const Value.absent()),
            ),
          );
        },
      );

  /// Episodes that arrive with the catalog (M3U). They follow the generation
  /// swap like other catalog rows.
  Future<void> upsertEpisodes(
    int sourceId,
    int gen,
    List<EpisodeData> items,
  ) async {
    if (items.isEmpty) return;
    await _counters(sourceId, gen);
    await batch((b) {
      for (final e in items) {
        final row = episodeCompanion(sourceId, gen, e);
        b.insert(
          db.episodes,
          row,
          onConflict: DoUpdate(
            (_) => row.copyWith(firstGen: const Value.absent()),
          ),
        );
      }
    });
  }

  /// Stores lazily fetched episodes of one series (Xtream `get_series_info`),
  /// replacing the previously fetched set. These rows have no generation:
  /// a sync keeps them until their series disappears from the catalog.
  Future<void> saveFetchedEpisodes(
    int sourceId,
    String seriesKey,
    List<EpisodeData> episodes,
  ) => batch((b) {
    b.deleteWhere(
      db.episodes,
      (e) =>
          e.sourceId.equals(sourceId) &
          e.seriesKey.equals(seriesKey) &
          e.generation.isNull(),
    );
    b.insertAll(db.episodes, [
      for (final e in episodes)
        episodeCompanion(
          sourceId,
          null,
          e,
        ).copyWith(seriesKey: Value(seriesKey)),
    ], mode: InsertMode.insertOrReplace);
  });

  /// Makes [gen] the visible catalog in one short transaction: rows of older
  /// generations are deleted, `sources.generation` is set and category item
  /// counts are refreshed.
  ///
  /// Kinds missing from [kinds] were not fetched by this sync and keep their
  /// committed rows (carried into [gen]).
  Future<void> commitGeneration(
    int sourceId,
    int gen, {
    Set<ContentKind> kinds = _allKinds,
  }) async {
    await transaction(() async {
      final current = await committedGeneration(sourceId);
      if (gen != current + 1) {
        throw StateError(
          'Generation $gen is not open for source $sourceId '
          '(committed: $current)',
        );
      }
      for (final kind in _allKinds.difference(kinds)) {
        await _carryForward(sourceId, kind, gen);
      }
      final args = [Variable.withInt(sourceId), Variable.withInt(gen)];
      for (final table in <TableInfo<Table, Object?>>[
        db.categoryItems,
        db.categories,
        db.channels,
        db.movies,
        db.series,
        db.episodes, // NULL generation (lazy episodes) never matches.
      ]) {
        await _write(
          'DELETE FROM ${table.actualTableName} '
          'WHERE source_id = ?1 AND generation < ?2',
          args,
          table,
          UpdateKind.delete,
        );
      }
      await _write(
        'DELETE FROM episodes WHERE source_id = ?1 AND NOT EXISTS ('
        'SELECT 1 FROM series s WHERE s.source_id = episodes.source_id '
        'AND s."key" = episodes.series_key)',
        [Variable.withInt(sourceId)],
        db.episodes,
        UpdateKind.delete,
      );
      await (update(db.sources)..where((s) => s.id.equals(sourceId))).write(
        SourcesCompanion(generation: Value(gen)),
      );
      await _write(
        'UPDATE categories SET item_count = ('
        'SELECT COUNT(*) FROM category_items ci '
        'WHERE ci.source_id = categories.source_id AND ci.generation = ?2 '
        'AND ci.kind = categories.kind AND ci.category_key = categories."key") '
        'WHERE source_id = ?1',
        args,
        db.categories,
        UpdateKind.update,
      );
    });
    _open.remove((sourceId, gen));
  }

  /// Drops everything written for [gen]. Rows that existed before keep their
  /// (possibly refreshed) data and return to the committed generation; rows
  /// first seen in [gen] are deleted. A no-op for committed generations.
  Future<void> abortGeneration(int sourceId, int gen) async {
    _open.remove((sourceId, gen));
    await transaction(() async {
      final current = await committedGeneration(sourceId);
      if (gen > current) await _discardAbove(sourceId, current);
    });
  }

  Future<void> _discardAbove(int sourceId, int current) async {
    final args = [Variable.withInt(sourceId), Variable.withInt(current)];
    await _write(
      'DELETE FROM category_items WHERE source_id = ?1 AND generation > ?2',
      args,
      db.categoryItems,
      UpdateKind.delete,
    );
    for (final table in <TableInfo<Table, Object?>>[
      db.categories,
      db.channels,
      db.movies,
      db.series,
      db.episodes,
    ]) {
      final name = table.actualTableName;
      await _write(
        'DELETE FROM $name '
        'WHERE source_id = ?1 AND generation > ?2 AND first_gen > ?2',
        args,
        table,
        UpdateKind.delete,
      );
      await _write(
        'UPDATE $name SET generation = ?2 '
        'WHERE source_id = ?1 AND generation > ?2',
        args,
        table,
        UpdateKind.update,
      );
    }
  }

  Future<void> _carryForward(int sourceId, ContentKind kind, int gen) async {
    final args = [
      Variable.withInt(sourceId),
      Variable.withInt(gen),
      Variable.withString(kind.name),
    ];
    // Prefer the committed membership over anything written by mistake.
    await _write(
      'DELETE FROM category_items '
      'WHERE source_id = ?1 AND generation = ?2 AND kind = ?3',
      args,
      db.categoryItems,
      UpdateKind.delete,
    );
    await _write(
      'UPDATE category_items SET generation = ?2 '
      'WHERE source_id = ?1 AND generation < ?2 AND kind = ?3',
      args,
      db.categoryItems,
      UpdateKind.update,
    );
    await _write(
      'UPDATE categories SET generation = ?2 '
      'WHERE source_id = ?1 AND generation < ?2 AND kind = ?3',
      args,
      db.categories,
      UpdateKind.update,
    );
    final tables = switch (kind) {
      ContentKind.live => <TableInfo<Table, Object?>>[db.channels],
      ContentKind.movie => <TableInfo<Table, Object?>>[db.movies],
      ContentKind.series => <TableInfo<Table, Object?>>[db.series, db.episodes],
    };
    for (final table in tables) {
      await _write(
        'UPDATE ${table.actualTableName} SET generation = ?2 '
        'WHERE source_id = ?1 AND generation < ?2',
        args.sublist(0, 2),
        table,
        UpdateKind.update,
      );
    }
  }

  Future<int> _write(
    String sql,
    List<Variable<Object>> args,
    TableInfo<Table, Object?> table,
    UpdateKind kind,
  ) => customUpdate(sql, variables: args, updates: {table}, updateKind: kind);

  /// Position counters of an open generation, rebuilt from the rows already
  /// written when this DAO did not start it (e.g. another isolate).
  Future<Map<(ContentKind, String), int>> _counters(
    int sourceId,
    int gen,
  ) async {
    final open = _open[(sourceId, gen)];
    if (open != null) return open;
    final current = await committedGeneration(sourceId);
    if (gen != current + 1) {
      throw StateError(
        'Generation $gen is not open for source $sourceId '
        '(committed: $current)',
      );
    }
    final rows = await customSelect(
      'SELECT kind, category_key, MAX(position) + 1 AS next '
      'FROM category_items WHERE source_id = ?1 AND generation = ?2 '
      'GROUP BY kind, category_key',
      variables: [Variable.withInt(sourceId), Variable.withInt(gen)],
      readsFrom: {db.categoryItems},
    ).get();
    final counters = <(ContentKind, String), int>{};
    for (final r in rows) {
      final kind = ContentKind.values.byName(r.read<String>('kind'));
      counters[(kind, r.read<String>('category_key'))] = r.read<int>('next');
    }
    _open.removeWhere((k, _) => k.$1 == sourceId);
    return _open[(sourceId, gen)] = counters;
  }

  /// Writes item rows plus their `category_items` memberships with dense
  /// positions per (kind, categoryKey), in one batch.
  Future<void> _upsertItems<T>(
    int sourceId,
    int gen,
    ContentKind kind,
    List<T> items,
    String Function(T) keyOf,
    List<String> Function(T) categoriesOf,
    void Function(Batch b, T item) writeRow,
  ) async {
    if (items.isEmpty) return;
    final counters = await _counters(sourceId, gen);
    final previous = <(ContentKind, String), int?>{};
    final memberships = <CategoryItemsCompanion>[];
    for (final item in items) {
      final key = keyOf(item);
      for (final category in categoriesOf(item).toSet()) {
        final slot = (kind, category);
        previous.putIfAbsent(slot, () => counters[slot]);
        final position = counters[slot] ?? 0;
        counters[slot] = position + 1;
        memberships.add(
          CategoryItemsCompanion.insert(
            sourceId: sourceId,
            generation: gen,
            kind: kind,
            categoryKey: category,
            position: position,
            itemKey: key,
          ),
        );
      }
    }
    try {
      await batch((b) {
        for (final item in items) {
          writeRow(b, item);
        }
        b.insertAll(
          db.categoryItems,
          memberships,
          mode: InsertMode.insertOrReplace,
        );
      });
    } on Object {
      // Hand the positions back so the category stays dense.
      previous.forEach((slot, n) {
        if (n == null) {
          counters.remove(slot);
        } else {
          counters[slot] = n;
        }
      });
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Reads.

  /// Committed generation of [sourceId] (0 before the first sync).
  Future<int> committedGeneration(int sourceId) async {
    final gen =
        await (selectOnly(db.sources)
              ..addColumns([db.sources.generation])
              ..where(db.sources.id.equals(sourceId)))
            .map((r) => r.read(db.sources.generation))
            .getSingleOrNull();
    if (gen == null) throw StateError('Unknown source $sourceId');
    return gen;
  }

  Expression<int> _committedGen(int sourceId) => subqueryExpression<int>(
    selectOnly(db.sources)
      ..addColumns([db.sources.generation])
      ..where(db.sources.id.equals(sourceId)),
  );

  SimpleSelectStatement<$CategoriesTable, CategoryRecord> _categoriesQuery(
    int sourceId,
    ContentKind kind,
    bool includeHidden,
  ) => select(db.categories)
    ..where(
      (c) =>
          c.sourceId.equals(sourceId) &
          c.kind.equalsValue(kind) &
          c.firstGen.isSmallerOrEqual(_committedGen(sourceId)) &
          (includeHidden ? const Constant(true) : c.hidden.not()),
    )
    ..orderBy([
      (c) => OrderingTerm.asc(c.sortIndex),
      (c) => OrderingTerm.asc(c.nameNorm),
    ]);

  /// Visible categories in provider order.
  Future<List<CategoryRow>> categories(
    int sourceId,
    ContentKind kind, {
    bool includeHidden = false,
  }) async => [
    for (final r in await _categoriesQuery(sourceId, kind, includeHidden).get())
      r.toRow(),
  ];

  Stream<List<CategoryRow>> watchCategories(
    int sourceId,
    ContentKind kind, {
    bool includeHidden = false,
  }) => _categoriesQuery(
    sourceId,
    kind,
    includeHidden,
  ).watch().map((rows) => [for (final r in rows) r.toRow()]);

  Future<void> setCategoryHidden(
    int sourceId,
    ContentKind kind,
    String key,
    bool hidden,
  ) =>
      (update(db.categories)..where(
            (c) =>
                c.sourceId.equals(sourceId) &
                c.kind.equalsValue(kind) &
                c.key.equals(key),
          ))
          .write(CategoriesCompanion(hidden: Value(hidden)));

  /// Items in a category of the committed generation.
  Future<int> itemCount(
    int sourceId,
    ContentKind kind,
    String categoryKey,
  ) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM category_items WHERE source_id = ?1 '
      'AND generation = (SELECT generation FROM sources WHERE id = ?1) '
      'AND kind = ?2 AND category_key = ?3',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(kind.name),
        Variable.withString(categoryKey),
      ],
      readsFrom: {db.categoryItems, db.sources},
    ).getSingle();
    return row.read<int>('n');
  }

  /// Committed items of [kind] in the whole source.
  Future<int> totalCount(int sourceId, ContentKind kind) async {
    final table = _tableFor(kind);
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM ${table.actualTableName} WHERE source_id = ?1 '
      'AND first_gen <= (SELECT generation FROM sources WHERE id = ?1)',
      variables: [Variable.withInt(sourceId)],
      readsFrom: {table, db.sources},
    ).getSingle();
    return row.read<int>('n');
  }

  /// Position of [itemKey] in a category (for opening a list scrolled to
  /// the current channel), or null.
  Future<int?> positionInCategory(
    int sourceId,
    ContentKind kind,
    String categoryKey,
    String itemKey,
  ) async {
    final row = await customSelect(
      'SELECT MIN(position) AS p FROM category_items WHERE source_id = ?1 '
      'AND kind = ?2 AND item_key = ?3 AND category_key = ?4 '
      'AND generation = (SELECT generation FROM sources WHERE id = ?1)',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(kind.name),
        Variable.withString(itemKey),
        Variable.withString(categoryKey),
      ],
      readsFrom: {db.categoryItems, db.sources},
    ).getSingle();
    return row.read<int?>('p');
  }

  Future<List<ChannelRow>> channelsPage(
    int sourceId,
    String categoryKey,
    int offset,
    int limit,
  ) async => [
    for (final r in await _categoryPage(
      db.channels,
      sourceId,
      ContentKind.live,
      categoryKey,
      offset,
      limit,
    ))
      r.toRow(),
  ];

  Future<List<MovieRow>> moviesPage(
    int sourceId,
    String categoryKey,
    int offset,
    int limit,
  ) async => [
    for (final r in await _categoryPage(
      db.movies,
      sourceId,
      ContentKind.movie,
      categoryKey,
      offset,
      limit,
    ))
      r.toRow(),
  ];

  Future<List<SeriesRow>> seriesPage(
    int sourceId,
    String categoryKey,
    int offset,
    int limit,
  ) async => [
    for (final r in await _categoryPage(
      db.series,
      sourceId,
      ContentKind.series,
      categoryKey,
      offset,
      limit,
    ))
      r.toRow(),
  ];

  /// All channels ordered by number (unnumbered last), then name.
  Future<List<ChannelRow>> allChannelsPage(
    int sourceId,
    int offset,
    int limit,
  ) async {
    if (limit <= 0) return const [];
    final rows = await (_allChannelsQuery(
      sourceId,
    )..limit(limit, offset: _nonNeg(offset))).get();
    return [for (final r in rows) r.toRow()];
  }

  /// All movies ordered by name.
  Future<List<MovieRow>> allMoviesPage(
    int sourceId,
    int offset,
    int limit,
  ) async => [
    for (final r in await _allByName(db.movies, sourceId, offset, limit))
      r.toRow(),
  ];

  /// All series ordered by name.
  Future<List<SeriesRow>> allSeriesPage(
    int sourceId,
    int offset,
    int limit,
  ) async => [
    for (final r in await _allByName(db.series, sourceId, offset, limit))
      r.toRow(),
  ];

  /// Ordered channel keys of a category, for zapping (keys only: cheap even
  /// for 50k channels).
  Future<List<String>> channelKeysInCategory(
    int sourceId,
    String categoryKey,
  ) async {
    final rows = await customSelect(
      'SELECT item_key FROM category_items WHERE source_id = ?1 '
      'AND generation = (SELECT generation FROM sources WHERE id = ?1) '
      'AND kind = ?2 AND category_key = ?3 ORDER BY position',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(ContentKind.live.name),
        Variable.withString(categoryKey),
      ],
      readsFrom: {db.categoryItems, db.sources},
    ).get();
    return [for (final r in rows) r.read<String>('item_key')];
  }

  /// Keys in [allChannelsPage] order.
  Future<List<String>> allChannelKeys(int sourceId) {
    final q = selectOnly(db.channels)
      ..addColumns([db.channels.key])
      ..where(
        db.channels.sourceId.equals(sourceId) &
            db.channels.firstGen.isSmallerOrEqual(_committedGen(sourceId)),
      )
      ..orderBy(_channelOrder(db.channels));
    return q.map((r) => r.read(db.channels.key)!).get();
  }

  Future<ChannelRow?> channelByKey(int sourceId, String key) async =>
      (await (select(db.channels)
                ..where((c) => c.sourceId.equals(sourceId) & c.key.equals(key)))
              .getSingleOrNull())
          ?.toRow();

  /// First channel with this number (number entry on the remote).
  Future<ChannelRow?> channelByNumber(int sourceId, int number) async =>
      (await (select(db.channels)
                ..where(
                  (c) =>
                      c.sourceId.equals(sourceId) &
                      c.num.equals(number) &
                      c.firstGen.isSmallerOrEqual(_committedGen(sourceId)),
                )
                ..orderBy([(c) => OrderingTerm.asc(c.nameNorm)])
                ..limit(1))
              .getSingleOrNull())
          ?.toRow();

  /// Channels for [keys] in the same order; missing keys are skipped.
  Future<List<ChannelRow>> channelsByKeys(
    int sourceId,
    List<String> keys,
  ) async {
    final found = <String, ChannelRow>{};
    for (final chunk in chunked(keys)) {
      final rows = await (select(
        db.channels,
      )..where((c) => c.sourceId.equals(sourceId) & c.key.isIn(chunk))).get();
      for (final r in rows) {
        found[r.key] = r.toRow();
      }
    }
    return [for (final k in keys) ?found[k]];
  }

  Future<MovieRow?> movieByKey(int sourceId, String key) async =>
      (await (select(db.movies)
                ..where((m) => m.sourceId.equals(sourceId) & m.key.equals(key)))
              .getSingleOrNull())
          ?.toRow();

  Future<SeriesRow?> seriesByKey(int sourceId, String key) async =>
      (await (select(db.series)
                ..where((s) => s.sourceId.equals(sourceId) & s.key.equals(key)))
              .getSingleOrNull())
          ?.toRow();

  Future<EpisodeRow?> episodeByKey(int sourceId, String key) async =>
      (await (select(db.episodes)
                ..where((e) => e.sourceId.equals(sourceId) & e.key.equals(key)))
              .getSingleOrNull())
          ?.toRow();

  /// Episodes of a series ordered by season, then number.
  Future<List<EpisodeRow>> episodesForSeries(
    int sourceId,
    String seriesKey,
  ) async {
    final rows =
        await (select(db.episodes)
              ..where(
                (e) =>
                    e.sourceId.equals(sourceId) & e.seriesKey.equals(seriesKey),
              )
              ..orderBy([
                (e) => OrderingTerm.asc(e.season),
                (e) => OrderingTerm.asc(e.number),
                (e) => OrderingTerm.asc(e.key),
              ]))
            .get();
    return [for (final r in rows) r.toRow()];
  }

  /// Substring search on normalised names (Arabic folding, case-insensitive),
  /// best matches (earliest occurrence) first.
  Future<SearchResults> search(
    int sourceId,
    String query, {
    int limitPerKind = 50,
    Set<ContentKind> kinds = _allKinds,
  }) async {
    final norm = normalizeForSearch(query);
    if (norm.isEmpty || limitPerKind <= 0) return SearchResults.empty;
    return SearchResults(
      channels: kinds.contains(ContentKind.live)
          ? [
              for (final r in await _search(
                db.channels,
                sourceId,
                norm,
                limitPerKind,
              ))
                r.toRow(),
            ]
          : const [],
      movies: kinds.contains(ContentKind.movie)
          ? [
              for (final r in await _search(
                db.movies,
                sourceId,
                norm,
                limitPerKind,
              ))
                r.toRow(),
            ]
          : const [],
      series: kinds.contains(ContentKind.series)
          ? [
              for (final r in await _search(
                db.series,
                sourceId,
                norm,
                limitPerKind,
              ))
                r.toRow(),
            ]
          : const [],
    );
  }

  /// Key, name and guide ids of every committed channel, for EPG matching.
  Future<List<ChannelIdentity>> channelIdentities(int sourceId) {
    final c = db.channels;
    final q = selectOnly(c)
      ..addColumns([c.key, c.name, c.tvgId, c.tvgName])
      ..where(
        c.sourceId.equals(sourceId) &
            c.firstGen.isSmallerOrEqual(_committedGen(sourceId)),
      );
    return q
        .map(
          (r) => (
            key: r.read(c.key)!,
            name: r.read(c.name)!,
            tvgId: r.read(c.tvgId),
            tvgName: r.read(c.tvgName),
          ),
        )
        .get();
  }

  // -------------------------------------------------------------------------
  // Helpers.

  TableInfo<Table, Object?> _tableFor(ContentKind kind) => switch (kind) {
    ContentKind.live => db.channels,
    ContentKind.movie => db.movies,
    ContentKind.series => db.series,
  };

  SimpleSelectStatement<$ChannelsTable, ChannelRecord> _allChannelsQuery(
    int sourceId,
  ) => select(db.channels)
    ..where(
      (c) =>
          c.sourceId.equals(sourceId) &
          c.firstGen.isSmallerOrEqual(_committedGen(sourceId)),
    )
    ..orderBy([
      (c) => OrderingTerm.asc(c.num, nulls: NullsOrder.last),
      (c) => OrderingTerm.asc(c.nameNorm),
      (c) => OrderingTerm.asc(c.key),
    ]);

  /// Same order as [_allChannelsQuery], for `selectOnly`.
  List<OrderingTerm> _channelOrder($ChannelsTable c) => [
    OrderingTerm.asc(c.num, nulls: NullsOrder.last),
    OrderingTerm.asc(c.nameNorm),
    OrderingTerm.asc(c.key),
  ];

  Future<List<D>> _categoryPage<D>(
    TableInfo<Table, D> table,
    int sourceId,
    ContentKind kind,
    String categoryKey,
    int offset,
    int limit,
  ) async {
    if (limit <= 0) return const [];
    final from = _nonNeg(offset);
    final rows = await customSelect(
      'SELECT t.* FROM category_items ci '
      'JOIN ${table.actualTableName} t '
      'ON t.source_id = ci.source_id AND t."key" = ci.item_key '
      'WHERE ci.source_id = ?1 '
      'AND ci.generation = (SELECT generation FROM sources WHERE id = ?1) '
      'AND ci.kind = ?2 AND ci.category_key = ?3 '
      'AND ci.position >= ?4 AND ci.position < ?5 '
      'ORDER BY ci.position',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString(kind.name),
        Variable.withString(categoryKey),
        Variable.withInt(from),
        Variable.withInt(from + limit),
      ],
      readsFrom: {db.categoryItems, table, db.sources},
    ).get();
    return [for (final r in rows) await table.map(r.data)];
  }

  Future<List<D>> _allByName<D>(
    TableInfo<Table, D> table,
    int sourceId,
    int offset,
    int limit,
  ) async {
    if (limit <= 0) return const [];
    final rows = await customSelect(
      'SELECT * FROM ${table.actualTableName} WHERE source_id = ?1 '
      'AND first_gen <= (SELECT generation FROM sources WHERE id = ?1) '
      'ORDER BY name_norm, "key" LIMIT ?2 OFFSET ?3',
      variables: [
        Variable.withInt(sourceId),
        Variable.withInt(limit),
        Variable.withInt(_nonNeg(offset)),
      ],
      readsFrom: {table, db.sources},
    ).get();
    return [for (final r in rows) await table.map(r.data)];
  }

  Future<List<D>> _search<D>(
    TableInfo<Table, D> table,
    int sourceId,
    String norm,
    int limit,
  ) async {
    final rows = await customSelect(
      'SELECT * FROM ${table.actualTableName} WHERE source_id = ?1 '
      'AND first_gen <= (SELECT generation FROM sources WHERE id = ?1) '
      r"AND name_norm LIKE ?2 ESCAPE '\' "
      'ORDER BY instr(name_norm, ?3), name_norm, "key" LIMIT ?4',
      variables: [
        Variable.withInt(sourceId),
        Variable.withString('%${escapeLike(norm)}%'),
        Variable.withString(norm),
        Variable.withInt(limit),
      ],
      readsFrom: {table, db.sources},
    ).get();
    return [for (final r in rows) await table.map(r.data)];
  }
}

int _nonNeg(int v) => v < 0 ? 0 : v;

/// One open catalog generation; see [CatalogDao].
class CatalogWriteSession {
  CatalogWriteSession._(this._dao, this.sourceId, this.generation);

  final CatalogDao _dao;
  final int sourceId;
  final int generation;

  Future<void> categories(List<CategoryData> items) =>
      _dao.upsertCategories(sourceId, generation, items);

  Future<void> channels(List<ChannelData> items) =>
      _dao.upsertChannels(sourceId, generation, items);

  Future<void> movies(List<MovieData> items) =>
      _dao.upsertMovies(sourceId, generation, items);

  Future<void> series(List<SeriesData> items) =>
      _dao.upsertSeries(sourceId, generation, items);

  Future<void> episodes(List<EpisodeData> items) =>
      _dao.upsertEpisodes(sourceId, generation, items);

  Future<void> commit({Set<ContentKind> kinds = _allKinds}) =>
      _dao.commitGeneration(sourceId, generation, kinds: kinds);

  Future<void> abort() => _dao.abortGeneration(sourceId, generation);
}
