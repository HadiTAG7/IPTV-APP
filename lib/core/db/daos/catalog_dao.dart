import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../sources/models.dart';
import '../../text/normalize.dart';
import '../app_db.dart';
import 'query_utils.dart';

const _allKinds = {ContentKind.live, ContentKind.movie, ContentKind.series};

typedef _GenState = ({int committed, int? open, int last});

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
/// The open generation is stored in `sources.openGeneration` and numbers are
/// never reused. [beginGeneration] closes any earlier open generation, and
/// every upsert, commit and abort checks its number inside its transaction,
/// so a stale writer (a cancelled or superseded sync) fails with a
/// [StateError] instead of mixing into, committing or aborting a newer one.
/// Batches of one generation are written one after another by one writer.
class CatalogDao extends DatabaseAccessor<AppDatabase> {
  CatalogDao(super.attachedDatabase);

  /// Next free position per (kind, categoryKey) of each open generation.
  final _open = <(int, int), Map<(ContentKind, String), int>>{};

  // -------------------------------------------------------------------------
  // Generation swap.

  /// Opens a new generation of [sourceId] and returns its number (above every
  /// number handed out before). Leftovers of an interrupted or superseded
  /// sync are discarded; that sync's later writes are rejected.
  Future<int> beginGeneration(int sourceId) async {
    final gen = await transaction(() async {
      final state = await _state(sourceId);
      await _discardAbove(sourceId, state.committed);
      final gen = math.max(state.last, state.committed) + 1;
      await _writeSource(
        sourceId,
        SourcesCompanion(
          openGeneration: Value(gen),
          lastGeneration: Value(gen),
        ),
      );
      return gen;
    });
    _open.removeWhere((k, _) => k.$1 == sourceId);
    _open[(sourceId, gen)] = {};
    return gen;
  }

  /// Same as [beginGeneration], wrapped in a session object.
  Future<CatalogWriteSession> openGeneration(int sourceId) async =>
      CatalogWriteSession._(this, sourceId, await beginGeneration(sourceId));

  /// The generation a sync is writing for [sourceId], or null.
  Future<int?> openGenerationOf(int sourceId) async =>
      (await _state(sourceId)).open;

  Future<void> upsertCategories(
    int sourceId,
    int gen,
    List<CategoryData> items,
  ) async {
    if (items.isEmpty) return;
    await transaction(() async {
      await _requireOpen(sourceId, gen);
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
    await transaction(() async {
      await _requireOpen(sourceId, gen);
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
  /// counts are refreshed. Throws a [StateError] unless [gen] is open.
  ///
  /// Kinds missing from [kinds] were not fetched by this sync and keep their
  /// committed rows (carried into [gen]).
  Future<void> commitGeneration(
    int sourceId,
    int gen, {
    Set<ContentKind> kinds = _allKinds,
  }) async {
    await transaction(() async {
      await _requireOpen(sourceId, gen);
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
      await _writeSource(
        sourceId,
        SourcesCompanion(
          generation: Value(gen),
          openGeneration: const Value(null),
        ),
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

  /// Drops everything written for [gen] when it is the open generation.
  /// Rows that existed before keep their (possibly refreshed) data and return
  /// to the committed generation; rows first seen in [gen] are deleted.
  ///
  /// Does nothing when [gen] is not open (committed, aborted, superseded by
  /// a newer [beginGeneration], or its source is gone), so a late cancel
  /// never touches another sync's rows.
  Future<void> abortGeneration(int sourceId, int gen) async {
    _open.remove((sourceId, gen));
    await transaction(() async {
      final state = await _stateOrNull(sourceId);
      if (state == null || state.open != gen) return;
      await _discardAbove(sourceId, state.committed);
      await _writeSource(
        sourceId,
        const SourcesCompanion(openGeneration: Value(null)),
      );
    });
  }

  Future<_GenState?> _stateOrNull(int sourceId) {
    final s = db.sources;
    return (selectOnly(s)
          ..addColumns([s.generation, s.openGeneration, s.lastGeneration])
          ..where(s.id.equals(sourceId)))
        .map(
          (r) => (
            committed: r.read(s.generation)!,
            open: r.read(s.openGeneration),
            last: r.read(s.lastGeneration)!,
          ),
        )
        .getSingleOrNull();
  }

  Future<_GenState> _state(int sourceId) async =>
      await _stateOrNull(sourceId) ??
      (throw StateError('Unknown source $sourceId'));

  /// Throws a [StateError] unless [gen] is the open generation.
  Future<void> _requireOpen(int sourceId, int gen) async {
    final state = await _state(sourceId);
    if (state.open == gen) return;
    _open.remove((sourceId, gen));
    throw StateError(
      'Generation $gen is not open for source $sourceId '
      '(open: ${state.open}, committed: ${state.committed})',
    );
  }

  Future<void> _writeSource(int sourceId, SourcesCompanion values) =>
      (update(db.sources)..where((s) => s.id.equals(sourceId))).write(values);

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

  /// Position counters of the open generation [gen], rebuilt from the rows
  /// already written when this DAO did not start it (e.g. another isolate).
  Future<Map<(ContentKind, String), int>> _counters(
    int sourceId,
    int gen,
  ) async {
    final open = _open[(sourceId, gen)];
    if (open != null) return open;
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

  /// (categoryKey, itemKey) memberships of [keys] already written in [gen].
  Future<Set<(String, String)>> _writtenMemberships(
    int sourceId,
    int gen,
    ContentKind kind,
    Iterable<String> keys,
  ) async {
    final found = <(String, String)>{};
    for (final chunk in chunked(keys.toSet().toList())) {
      final rows = await customSelect(
        'SELECT category_key, item_key FROM category_items '
        'WHERE source_id = ?1 AND kind = ?2 AND generation = ?3 '
        'AND item_key IN (${sqlParams(chunk.length, 4)})',
        variables: [
          Variable.withInt(sourceId),
          Variable.withString(kind.name),
          Variable.withInt(gen),
          for (final k in chunk) Variable.withString(k),
        ],
        readsFrom: {db.categoryItems},
      ).get();
      for (final r in rows) {
        found.add((r.read<String>('category_key'), r.read<String>('item_key')));
      }
    }
    return found;
  }

  /// Writes item rows plus their `category_items` memberships with dense
  /// positions per (kind, categoryKey), in one transaction.
  ///
  /// An item repeated within a generation (Xtream per-category fetches list
  /// a multi-category stream once per category) keeps one membership per
  /// category. A position clash with another writer fails the batch.
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
    Map<(ContentKind, String), int>? counters;
    final previous = <(ContentKind, String), int?>{};
    try {
      await transaction(() async {
        await _requireOpen(sourceId, gen);
        final next = counters = await _counters(sourceId, gen);
        final written = await _writtenMemberships(
          sourceId,
          gen,
          kind,
          items.map(keyOf),
        );
        final memberships = <CategoryItemsCompanion>[];
        for (final item in items) {
          final key = keyOf(item);
          for (final category in categoriesOf(item)) {
            if (!written.add((category, key))) continue;
            final slot = (kind, category);
            previous.putIfAbsent(slot, () => next[slot]);
            final position = next[slot] ?? 0;
            next[slot] = position + 1;
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
        await batch((b) {
          for (final item in items) {
            writeRow(b, item);
          }
          b.insertAll(db.categoryItems, memberships);
        });
      });
    } on Object {
      // Hand the positions back so the category stays dense.
      final next = counters;
      if (next != null) {
        previous.forEach((slot, n) {
          if (n == null) {
            next.remove(slot);
          } else {
            next[slot] = n;
          }
        });
      }
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Reads.

  /// Committed generation of [sourceId] (0 before the first sync).
  Future<int> committedGeneration(int sourceId) async =>
      (await _state(sourceId)).committed;

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

  /// All movies, newest added first (the panel's `added` time; titles
  /// without one come last), then by name in natural order (`Movie 2`
  /// before `Movie 10`).
  Future<List<MovieRow>> allMoviesPage(
    int sourceId,
    int offset,
    int limit,
  ) async => [
    for (final r in await _allInOrder(
      db.movies,
      sourceId,
      offset,
      limit,
      newestFirst: true,
    ))
      r.toRow(),
  ];

  /// All series by name in natural order (`Season 2` before `Season 10`).
  Future<List<SeriesRow>> allSeriesPage(
    int sourceId,
    int offset,
    int limit,
  ) async => [
    for (final r in await _allInOrder(db.series, sourceId, offset, limit))
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

  /// A page of every committed item of [table], by name in natural order;
  /// with [newestFirst], items with a later `added_at` come first.
  ///
  /// The order needs a sort (no index holds it): only the keys are sorted,
  /// which keeps the sorter small on deep pages (it holds offset + limit
  /// entries), then the page's rows are read by key.
  Future<List<D>> _allInOrder<D>(
    TableInfo<Table, D> table,
    int sourceId,
    int offset,
    int limit, {
    bool newestFirst = false,
  }) async {
    if (limit <= 0) return const [];
    final name = table.actualTableName;
    final newest = newestFirst ? 'added_at IS NULL, added_at DESC, ' : '';
    final keys = [
      for (final r in await customSelect(
        'SELECT "key" FROM $name WHERE source_id = ?1 '
        'AND first_gen <= (SELECT generation FROM sources WHERE id = ?1) '
        'ORDER BY $newest${naturalOrderSql('name_norm')}, "key" '
        'LIMIT ?2 OFFSET ?3',
        variables: [
          Variable.withInt(sourceId),
          Variable.withInt(limit),
          Variable.withInt(_nonNeg(offset)),
        ],
        readsFrom: {table, db.sources},
      ).get())
        r.read<String>('key'),
    ];
    final byKey = <String, D>{};
    for (final part in chunked(keys)) {
      final rows = await customSelect(
        'SELECT * FROM $name WHERE source_id = ?1 '
        'AND "key" IN (${sqlParams(part.length, 2)})',
        variables: [
          Variable.withInt(sourceId),
          for (final k in part) Variable.withString(k),
        ],
        readsFrom: {table},
      ).get();
      for (final r in rows) {
        byKey[r.read<String>('key')] = await table.map(r.data);
      }
    }
    // A sync committing between the two reads may have removed some.
    return [for (final k in keys) ?byKey[k]];
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
