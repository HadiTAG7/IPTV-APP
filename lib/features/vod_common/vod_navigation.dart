import 'package:flutter/material.dart';

import '../movies/movie_detail_screen.dart';
import '../series/series_detail_screen.dart';

/// Route name of the movie detail page.
const kMovieDetailRouteName = '/movie';

/// Route name of the series detail page.
const kSeriesDetailRouteName = '/series';

/// Opens the detail page of movie [movieKey] of source [sourceId] (from the
/// movie grid, search or favourites). Completes when the page is closed.
Future<void> openMovieDetail(
  BuildContext context,
  int sourceId,
  String movieKey,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    settings: RouteSettings(
      name: kMovieDetailRouteName,
      arguments: (sourceId: sourceId, key: movieKey),
    ),
    builder: (_) => MovieDetailScreen(sourceId: sourceId, movieKey: movieKey),
  ),
);

/// Opens the detail page (seasons and episodes) of series [seriesKey] of
/// source [sourceId]. Completes when the page is closed.
Future<void> openSeriesDetail(
  BuildContext context,
  int sourceId,
  String seriesKey,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    settings: RouteSettings(
      name: kSeriesDetailRouteName,
      arguments: (sourceId: sourceId, key: seriesKey),
    ),
    builder: (_) =>
        SeriesDetailScreen(sourceId: sourceId, seriesKey: seriesKey),
  ),
);
