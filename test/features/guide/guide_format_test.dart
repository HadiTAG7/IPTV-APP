import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:iptv_player/epg/epg_models.dart';
import 'package:iptv_player/features/guide/guide_format.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

DateTime at(int hour, [int minute = 0, int day = 15]) =>
    DateTime(2026, 10, day, hour, minute).toUtc();

Future<DateFormat> _formatIn(
  WidgetTester tester,
  Locale locale, {
  required bool use24,
}) async {
  late DateFormat format;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(alwaysUse24HourFormat: use24),
      child: Localizations(
        locale: locale,
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            format = guideTimeFormat(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return format;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  testWidgets('clock times: 24-hour on request, else the locale default', (
    tester,
  ) async {
    final t = at(20, 5);
    expect(
      (await _formatIn(
        tester,
        const Locale('en'),
        use24: true,
      )).format(t.toLocal()),
      '20:05',
    );
    expect(
      (await _formatIn(
        tester,
        const Locale('en'),
        use24: false,
      )).format(t.toLocal()),
      '8:05\u202fPM',
    );
    // Arabic keeps Western digits (the intl `ar` default).
    final ar24 = (await _formatIn(
      tester,
      const Locale('ar'),
      use24: true,
    )).format(t.toLocal());
    expect(ar24, '20:05');
    final ar12 = (await _formatIn(
      tester,
      const Locale('ar'),
      use24: false,
    )).format(t.toLocal());
    expect(ar12, contains('8:05'));
    expect(ar12, contains('م'));
    expect(ar12, isNot(contains('\u0668')));

    // Flutter's `ar` date symbols (now loaded) default to Arabic-Indic
    // digits; with `useWesternDigits` (bootstrap, flutter_test_config) the
    // dates and the generated "Guide updated" message keep Western ones.
    final eastern = RegExp('[\u0660-\u0669]');
    final date = guideDayLabel(ar, 'ar', at(9, 0, 17), at(18, 47));
    expect(date, contains('17'));
    expect(date, isNot(matches(eastern)));
    expect(ar.guideUpdated(at(9, 0, 17)), isNot(matches(eastern)));
    final updated = guideUpdatedText(ar, at(9, 0, 17));
    expect(updated, contains('2026'));
    expect(updated, isNot(matches(eastern)));
  });

  test('day labels', () {
    final now = at(18, 47);
    expect(guideDayLabel(en, 'en', at(23, 59), now), en.guideToday);
    expect(guideDayLabel(ar, 'ar', at(0, 30, 16), now), ar.guideTomorrow);
    expect(guideDayLabel(en, 'en', at(9, 0, 17), now), 'Sat, Oct 17');
    expect(guideDayLabel(en, 'en', at(17, 0, 14), now), 'Wed, Oct 14');
  });

  test('local day boundaries', () {
    final today = localDayOf(at(18, 47));
    expect(today.start, at(0));
    expect(today.end, at(0, 0, 16));
    final tomorrow = localDayOf(at(18, 47), offset: 1);
    expect(tomorrow.start, at(0, 0, 16));
    expect(tomorrow.end, at(0, 0, 17));
  });

  test('programme times, day and minutes left', () {
    final format = DateFormat.Hm('en');
    final now = at(18, 47);
    final onAir = EpgProgramme(
      channelId: 'x',
      start: at(18),
      stop: at(19),
      title: 'A',
    );
    expect(guideTimeRange(format, onAir.start, onAir.stop), '18:00 – 19:00');
    expect(
      guideProgrammeTimes(en, 'en', format, onAir, now),
      '18:00 – 19:00 · ${en.guideMinutesLeft(13)}',
    );
    final tomorrow = EpgProgramme(
      channelId: 'x',
      start: at(9, 0, 16),
      stop: at(10, 0, 16),
      title: 'B',
    );
    expect(
      guideProgrammeTimes(en, 'en', format, tomorrow, now),
      '09:00 – 10:00 · ${en.guideTomorrow}',
    );
    expect(guideProgress(onAir, now), closeTo(47 / 60, 1e-9));
    expect(guideProgress(tomorrow, now), 0);
    expect(
      guideProgress(
        EpgProgramme(channelId: 'x', start: now, stop: now, title: 'C'),
        now,
      ),
      0,
    );
  });

  test('minutes left in both languages', () {
    expect(en.guideMinutesLeft(0), 'Ending now');
    expect(en.guideMinutesLeft(1), '1 min left');
    expect(en.guideMinutesLeft(13), '13 min left');
    expect(ar.guideMinutesLeft(1), 'تبقّت دقيقة واحدة');
    expect(ar.guideMinutesLeft(2), 'تبقّت دقيقتان');
    expect(ar.guideMinutesLeft(5), 'تبقّت 5 دقائق');
    expect(ar.guideMinutesLeft(13), 'تبقّت 13 دقيقة');
  });
}
