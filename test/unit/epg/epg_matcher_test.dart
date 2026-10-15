import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/epg/epg_matcher.dart';
import 'package:iptv_player/epg/epg_models.dart';

EpgChannel guide(String id, [List<String> names = const []]) =>
    EpgChannel(id: id, displayNames: names);

MatchCandidate channel(
  String key,
  String name, {
  String? tvgId,
  String? tvgName,
}) => MatchCandidate(key: key, name: name, tvgId: tvgId, tvgName: tvgName);

void main() {
  final guideChannels = [
    guide('AlArabiya.ae', ['العربية', 'Al Arabiya']),
    guide('jazeera.qa', ['Al Jazeera Arabic', 'الجزيرة']),
    guide('news.example', ['Example News']),
    guide('sport1.example', ['Example Sport 1']),
    guide('sport2.example', ['Example Sport 2']),
  ];

  group('matchChannels', () {
    test('tvg-id matches the channel id ignoring case', () {
      final m = matchChannels([
        channel('1', 'Whatever', tvgId: 'alarabiya.AE'),
        channel('2', 'Whatever', tvgId: '  news.example '),
      ], guideChannels);
      expect(m['1'], const EpgMatch('AlArabiya.ae', MatchKind.tvgId));
      expect(m['2'], const EpgMatch('news.example', MatchKind.tvgId));
    });

    test('normalized tvg-name matches any display name', () {
      final m = matchChannels([
        channel('1', 'x', tvgName: 'AR: Al Jazeera Arabic HD'),
        channel('2', 'x', tvgName: 'الجزيرة FHD'),
      ], guideChannels);
      expect(m['1'], const EpgMatch('jazeera.qa', MatchKind.tvgName));
      expect(m['2'], const EpgMatch('jazeera.qa', MatchKind.tvgName));
    });

    test('normalized name matches Arabic display names', () {
      final m = matchChannels([
        channel('1', 'العربية HD'),
        channel('2', 'العربيه'),
        channel('3', 'أَلْعَرَبِيَّة'),
        channel('4', '|SA| Al Arabiya (1080p)'),
      ], guideChannels);
      for (final key in ['1', '2', '3', '4']) {
        expect(
          m[key],
          const EpgMatch('AlArabiya.ae', MatchKind.name),
          reason: key,
        );
      }
    });

    test('priority: tvg-id over tvg-name over name', () {
      final m = matchChannels([
        // Each rule would pick a different guide channel.
        channel(
          'all',
          'Example News',
          tvgId: 'sport1.example',
          tvgName: 'Example Sport 2',
        ),
        channel('nameVsTvgName', 'Example News', tvgName: 'Example Sport 2'),
        channel('nameOnly', 'Example News'),
      ], guideChannels);
      expect(m['all'], const EpgMatch('sport1.example', MatchKind.tvgId));
      expect(
        m['nameVsTvgName'],
        const EpgMatch('sport2.example', MatchKind.tvgName),
      );
      expect(m['nameOnly'], const EpgMatch('news.example', MatchKind.name));
    });

    test('unknown tvg-id falls back to names', () {
      final m = matchChannels([
        channel('1', 'Example News', tvgId: 'missing.example'),
        channel('2', 'Nope', tvgId: 'missing.example', tvgName: 'Al Arabiya'),
      ], guideChannels);
      expect(m['1'], const EpgMatch('news.example', MatchKind.name));
      expect(m['2'], const EpgMatch('AlArabiya.ae', MatchKind.tvgName));
    });

    test('manual override beats every rule', () {
      final m = matchChannels(
        [
          channel('1', 'Example News', tvgId: 'news.example'),
          channel('2', 'Example News'),
          channel('3', 'Example News'),
        ],
        guideChannels,
        manual: {
          '1': 'sport2.example',
          '2': 'SPORT1.EXAMPLE',
          '3': 'not-in-this-guide.example',
          'absent': 'news.example',
        },
      );
      expect(m['1'], const EpgMatch('sport2.example', MatchKind.manual));
      // The guide's spelling of the id is used when present.
      expect(m['2'], const EpgMatch('sport1.example', MatchKind.manual));
      expect(
        m['3'],
        const EpgMatch('not-in-this-guide.example', MatchKind.manual),
      );
      expect(m.containsKey('absent'), isFalse);
    });

    test('an empty manual id unlinks the channel', () {
      final m = matchChannels(
        [channel('1', 'Example News', tvgId: 'news.example')],
        guideChannels,
        manual: {'1': ''},
      );
      expect(m, isEmpty);
    });

    test('unmatched channels are absent', () {
      final m = matchChannels([
        channel('1', 'Totally Different', tvgId: 'nope', tvgName: 'Other'),
        channel('2', ''),
      ], guideChannels);
      expect(m, isEmpty);
    });

    test('names that normalize to nothing never match', () {
      final m = matchChannels(
        [
          channel('1', 'HD'),
          channel('2', ' '),
          channel('3', 'FHD', tvgName: '4K'),
        ],
        [
          guide('tags.example', ['SD', '']),
        ],
      );
      expect(m, isEmpty);
    });

    test('ambiguity: the first guide channel in document order wins', () {
      final m = matchChannels(
        [channel('1', 'Twin HD'), channel('2', 'x', tvgId: 'dup.example')],
        [
          guide('first.example', ['Twin']),
          guide('dup.example', ['Other']),
          guide('second.example', ['Twin']),
          guide('DUP.example', ['Twin']),
        ],
      );
      expect(m['1'], const EpgMatch('first.example', MatchKind.name));
      expect(m['2'], const EpgMatch('dup.example', MatchKind.tvgId));
    });

    test('empty inputs', () {
      expect(matchChannels(const [], guideChannels), isEmpty);
      expect(matchChannels([channel('1', 'Example News')], const []), isEmpty);
    });

    test('50k channels against 20k guide channels is fast', () {
      final guides = [
        for (var i = 0; i < 20000; i++)
          guide('ch$i.example', ['Channel $i', 'قناة $i']),
      ];
      final channels = [
        for (var i = 0; i < 50000; i++)
          switch (i % 4) {
            0 => channel('k$i', 'x', tvgId: 'CH${i % 25000}.EXAMPLE'),
            1 => channel('k$i', 'x', tvgName: 'AR: Channel ${i % 25000} HD'),
            2 => channel('k$i', 'قناة ${i % 25000} FHD'),
            _ => channel('k$i', 'Unknown $i'),
          },
      ];
      final sw = Stopwatch()..start();
      final m = matchChannels(channels, guides);
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
      // i % 25000 < 20000 for 4/5 of each matching group.
      expect(m.length, 30000);
      expect(m['k0'], const EpgMatch('ch0.example', MatchKind.tvgId));
      expect(m['k1'], const EpgMatch('ch1.example', MatchKind.tvgName));
      expect(m['k2'], const EpgMatch('ch2.example', MatchKind.name));
      expect(m.containsKey('k3'), isFalse);
    });
  });

  group('IncrementalMatcher', () {
    List<EpgChannel> sortedById(Iterable<EpgChannel> channels) =>
        channels.toList()..sort((a, b) => a.id.compareTo(b.id));

    test('a later channel wins by a stronger rule, then by a smaller id; '
        'add returns the changes', () {
      final channels = [
        channel('twin', 'Twin'),
        channel('up', 'Upgrade', tvgId: 'UP.tv'),
        channel('same', 'Same'),
      ];
      final matcher = IncrementalMatcher(channels);

      expect(
        matcher.add([
          guide('m.twin', ['Twin']),
          guide('name.up', ['Upgrade']),
          guide('a.same', ['Same']),
        ]),
        {
          'twin': const EpgMatch('m.twin', MatchKind.name),
          'up': const EpgMatch('name.up', MatchKind.name),
          'same': const EpgMatch('a.same', MatchKind.name),
        },
      );
      // Larger ids by the same rule do not win.
      expect(
        matcher.add([
          guide('z.twin', ['Twin']),
          guide('z.same', ['Same']),
        ]),
        isEmpty,
      );
      expect(
        matcher.add([
          guide('a.twin', ['Twin']),
          guide('up.TV', ['Other']),
        ]),
        {
          'twin': const EpgMatch('a.twin', MatchKind.name),
          'up': const EpgMatch('up.TV', MatchKind.tvgId),
        },
      );
      // A smaller id by a weaker rule does not win either.
      expect(
        matcher.add([
          guide('a.up', ['Upgrade']),
        ]),
        isEmpty,
      );
      expect(matcher.matches, {
        'twin': const EpgMatch('a.twin', MatchKind.name),
        'up': const EpgMatch('up.TV', MatchKind.tvgId),
        'same': const EpgMatch('a.same', MatchKind.name),
      });
      expect(
        matcher.matches,
        matchChannels(
          channels,
          sortedById([
            guide('m.twin', ['Twin']),
            guide('name.up', ['Upgrade']),
            guide('a.same', ['Same']),
            guide('z.twin', ['Twin']),
            guide('z.same', ['Same']),
            guide('a.twin', ['Twin']),
            guide('up.TV', ['Other']),
            guide('a.up', ['Upgrade']),
          ]),
        ),
      );
    });

    test('continues from the matches it is given', () {
      final channels = [channel('1', 'Example News'), channel('2', 'Twin')];
      final first = [
        guide('news.example', ['Example News']),
      ];
      final matcher = IncrementalMatcher(
        channels,
        matches: matchChannels(channels, first),
      );
      expect(matcher.matches, {
        '1': const EpgMatch('news.example', MatchKind.name),
      });
      expect(
        matcher.add([
          guide('z.news', ['Example News']),
        ]),
        isEmpty,
      );
      expect(
        matcher.add([
          guide('twin.example', ['Twin']),
        ]),
        {'2': const EpgMatch('twin.example', MatchKind.name)},
      );
    });

    test('equals matchChannels over everything added, sorted by id', () {
      final random = Random(7);
      const names = ['Alpha', 'Beta HD', 'الجزيرة', 'Gamma', 'HD', ''];
      const ids = ['a.tv', 'A.TV', 'b.tv', 'c.tv', 'd.tv', ' ', 'e.tv'];
      String? pick(List<String> from, {bool nullable = false}) =>
          nullable && random.nextBool()
          ? null
          : from[random.nextInt(from.length)];

      for (var round = 0; round < 200; round++) {
        final channels = [
          for (var i = 0; i < 8; i++)
            channel(
              'k$i',
              pick(names)!,
              tvgId: pick(ids, nullable: true),
              tvgName: pick(names, nullable: true),
            ),
        ];
        final matcher = IncrementalMatcher(channels);
        final added = <EpgChannel>[];
        for (var part = 0; part < 4; part++) {
          final batch = [
            for (var i = random.nextInt(4); i > 0; i--)
              guide(pick(ids)!, [
                for (var n = random.nextInt(3); n > 0; n--) pick(names)!,
              ]),
          ];
          final before = Map.of(matcher.matches);
          final changed = matcher.add(batch);
          added.addAll(batch);
          final expected = matchChannels(channels, sortedById(added));
          expect(matcher.matches, expected, reason: 'round $round');
          expect(changed, {
            for (final MapEntry(:key, :value) in expected.entries)
              if (before[key] != value) key: value,
          }, reason: 'round $round');
        }
      }
    });
  });
}
