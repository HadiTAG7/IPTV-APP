import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/core/db/queries/settings_help_queries.dart';
import 'package:iptv_player/features/settings/settings_format.dart';
import 'package:iptv_player/sources/models.dart';

void main() {
  group('guide offset', () {
    test('steps by 30 minutes', () {
      expect(stepEpgOffset(0, 1), 30);
      expect(stepEpgOffset(0, -1), -30);
      expect(stepEpgOffset(90, 5), 240);
      expect(stepEpgOffset(-90, -2), -150);
    });

    test('stays within -12 h .. +14 h', () {
      expect(stepEpgOffset(kMaxEpgOffsetMin, 1), kMaxEpgOffsetMin);
      expect(stepEpgOffset(kMinEpgOffsetMin, -1), kMinEpgOffsetMin);
      expect(stepEpgOffset(0, 1000), 14 * 60);
      expect(stepEpgOffset(0, -1000), -12 * 60);
      expect(stepEpgOffset(5000, 0), kMaxEpgOffsetMin);
      expect(stepEpgOffset(-5000, 0), kMinEpgOffsetMin);
    });

    test('snaps odd stored values to the grid', () {
      expect(stepEpgOffset(45, 0), 60);
      expect(stepEpgOffset(44, 0), 30);
      expect(stepEpgOffset(-45, 0), -60);
      expect(stepEpgOffset(10, 1), 30);
    });

    test('formats as signed H:MM', () {
      expect(formatEpgOffset(0), '0:00');
      expect(formatEpgOffset(30), '+0:30');
      expect(formatEpgOffset(-90), '-1:30');
      expect(formatEpgOffset(14 * 60), '+14:00');
      expect(formatEpgOffset(-12 * 60), '-12:00');
    });
  });

  test('refresh interval choices keep a saved odd value', () {
    expect(epgRefreshChoicesWith(12), kEpgRefreshHourChoices);
    expect(epgRefreshChoicesWith(168), [...kEpgRefreshHourChoices, 168]);
    expect(epgRefreshChoicesWith(5), [3, 5, 6, 12, 24, 48]);
  });

  test('language choices keep a saved other code', () {
    expect(languageChoicesWith('ar'), kPreferredLanguageCodes);
    expect(languageChoicesWith('de'), [...kPreferredLanguageCodes, 'de']);
  });

  test('guide URLs must be absolute http(s) URLs', () {
    expect(
      parseGuideUrl('  https://example.com/epg.xml.gz '),
      'https://example.com/epg.xml.gz',
    );
    expect(parseGuideUrl('HTTP://Example.com/x'), 'HTTP://Example.com/x');
    expect(
      parseGuideUrl('http://127.0.0.1:8080/xmltv.php?username=a&password=b'),
      isNotNull,
    );
    for (final bad in [
      '',
      '   ',
      'not a url',
      'example.com/epg.xml',
      'ftp://example.com/epg.xml',
      'file:///sdcard/epg.xml',
      'http://',
      'http:// example.com/x',
    ]) {
      expect(parseGuideUrl(bad), isNull, reason: bad);
    }
  });

  group('queries', () {
    late AppDatabase db;
    late int sourceId;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(NativeDatabase.memory());
      sourceId = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/a.m3u',
          name: 'A',
        ),
      );
    });

    tearDown(() => db.close());

    test('setSourceEpgOffset stores minutes, negative too', () async {
      await db.setSourceEpgOffset(sourceId, -90);
      expect((await db.sourcesDao.byId(sourceId))!.epgOffsetMin, -90);
      await db.setSourceEpgOffset(sourceId, 840);
      expect((await db.sourcesDao.byId(sourceId))!.epgOffsetMin, 840);
      // Unknown ids are ignored.
      await db.setSourceEpgOffset(sourceId + 1, 30);
    });

    test('addManualEpgSource appends after the existing guides', () async {
      final first = await db.addManualEpgSource(
        sourceId,
        'http://127.0.0.1:9/one.xml',
      );
      expect((await db.epgDao.epgSourceById(first))!.priority, 0);
      await db.epgDao.addEpgSource(
        sourceId,
        'http://127.0.0.1:9/xmltv.php?username=u&password=p',
        EpgOrigin.xtream,
        priority: 4,
      );
      final second = await db.addManualEpgSource(
        sourceId,
        'http://127.0.0.1:9/two.xml',
      );
      final row = (await db.epgDao.epgSourceById(second))!;
      expect(row.priority, 5);
      expect(row.origin, EpgOrigin.manual);
      // Another source's guides do not count.
      final other = await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.m3uUrl,
          url: 'http://127.0.0.1:9/b.m3u',
          name: 'B',
        ),
      );
      final third = await db.addManualEpgSource(
        other,
        'http://127.0.0.1:9/three.xml',
      );
      expect((await db.epgDao.epgSourceById(third))!.priority, 0);
    });
  });
}
