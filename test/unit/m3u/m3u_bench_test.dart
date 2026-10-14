@Tags(['bench'])
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/sources/m3u/byte_source.dart';
import 'package:iptv_player/sources/m3u/m3u_adapter.dart';
import 'package:iptv_player/sources/models.dart';

/// Synthetic playlist: 70% live, 20% movies, 10% episodes.
List<int> syntheticPlaylist(int count) {
  final b = StringBuffer(
    '#EXTM3U url-tvg="http://epg.example.com/guide.xml" '
    'url-logo="http://img.example.com/"\n',
  );
  for (var i = 0; i < count; i++) {
    final group = 'Group ${i % 250}';
    switch (i % 10) {
      case < 7:
        b
          ..write('#EXTINF:-1 tvg-id="ch$i.example" tvg-name="Channel $i" ')
          ..write('tvg-logo="logo$i.png" tvg-chno="$i" group-title="$group",')
          ..write('Channel $i HD\n')
          ..write('http://127.0.0.1:8080/live/user/pass/$i.ts\n');
      case < 9:
        b
          ..write(
            '#EXTINF:-1 tvg-logo="poster$i.jpg" group-title="VOD $group",',
          )
          ..write('Movie $i (2020)\n')
          ..write('http://127.0.0.1:8080/movie/user/pass/$i.mkv\n');
      default:
        b
          ..write('#EXTINF:-1 group-title="Series ${i % 40}",')
          ..write('Show ${i % 500} S0${i % 9 + 1}E${i % 30}\n')
          ..write('http://127.0.0.1:8080/series/user/pass/$i.mp4\n');
    }
  }
  return utf8.encode(b.toString());
}

void main() {
  test('100k-entry playlist parses in under 20 s', () async {
    final bytes = syntheticPlaylist(100000);
    final adapter = M3uAdapter(
      const SourceConfig(kind: SourceKind.m3uUrl, url: 'http://127.0.0.1/x'),
      dio: Dio(),
      byteSource: MemoryByteSource(bytes),
    );
    final watch = Stopwatch()..start();
    var channels = 0, movies = 0, episodes = 0, batches = 0;
    await for (final batch in adapter.fetchCatalog()) {
      batches++;
      switch (batch) {
        case ChannelsBatch(:final items):
          expect(items.length, lessThanOrEqualTo(kM3uBatchSize));
          channels += items.length;
        case MoviesBatch(:final items):
          movies += items.length;
        case EpisodesBatch(:final items):
          episodes += items.length;
        default:
          break;
      }
    }
    watch.stop();
    debugPrint(
      'M3U bench: ${bytes.length ~/ 1024} KB, $batches batches, '
      '${watch.elapsedMilliseconds} ms',
    );
    expect(channels, 70000);
    expect(movies, 20000);
    expect(episodes, 10000);
    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
  });
}
