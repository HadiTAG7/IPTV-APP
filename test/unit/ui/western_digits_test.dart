// Arabic dates use Western digits app-wide (`useWesternDigits`, called by
// bootstrap and by flutter_test_config), also in the generated messages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:iptv_player/core/text/western_digits.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';

final _eastern = RegExp('[٠-٩۰-۹]');

void main() {
  final date = DateTime(2026, 10, 15, 21, 5);

  List<String> datedMessages(AppLocalizations l10n) => [
    l10n.errorExpired(date),
    l10n.guideUpdated(date),
    l10n.settingsAccountExpires(date),
    l10n.settingsLastUpdated(date),
    l10n.settings_epgLastImport(date),
  ];

  testWidgets('generated Arabic date messages keep Western digits', (
    tester,
  ) async {
    late AppLocalizations ar;
    late MaterialLocalizations material;
    // The Material localizations load Flutter's own `ar` date symbols, the
    // ones that default to Arabic-Indic digits.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) {
            ar = AppLocalizations.of(context);
            material = MaterialLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    for (final message in datedMessages(ar)) {
      expect(message, isNot(matches(_eastern)), reason: message);
      expect(message, contains('2026'), reason: message);
    }
    expect(DateFormat.yMMMd('ar').format(date), contains('15'));
    expect(DateFormat.jm('ar').format(date), contains('9:05'));
    expect(
      material.formatTimeOfDay(TimeOfDay.fromDateTime(date)),
      isNot(matches(_eastern)),
    );

    // Without the setting the same symbols print Arabic-Indic digits,
    // so the test above proves the setting is what keeps them Western.
    DateFormat.useNativeDigitsByDefaultFor('ar', true);
    addTearDown(useWesternDigits);
    expect(ar.errorExpired(date), matches(_eastern));
    useWesternDigits();
    expect(ar.errorExpired(date), isNot(matches(_eastern)));
  });
}
