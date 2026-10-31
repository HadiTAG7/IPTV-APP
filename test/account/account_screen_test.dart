import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/account/account_controller.dart';
import 'package:iptv_player/account/account_screen.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/theme/app_theme.dart';
import 'package:iptv_player/tv/tv_text_field.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    for (final tv in [false, true]) {
      testWidgets(
        '$lang ${tv ? 'TV' : 'phone'}: account form, password privacy and validation',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = tv
              ? const Size(1280, 720)
              : const Size(390, 844);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                accountViewProvider.overrideWith(
                  (ref) => Stream.value(const AccountView()),
                ),
              ],
              child: RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  theme: AppTheme.dark(tv: tv),
                  locale: Locale(lang),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => FormFactorScope(
                    formFactor: tv ? FormFactor.tv : FormFactor.phone,
                    child: child!,
                  ),
                  home: const AccountScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(AccountScreen)),
          );
          expect(find.byType(TvTextField), findsNWidgets(2));
          expect(
            tester
                .widget<TvTextField>(
                  find.byKey(const ValueKey('account-password')),
                )
                .obscureText,
            true,
          );
          expect(tester.takeException(), isNull);
          final preview = Platform.environment['IPTV_ACCOUNT_PREVIEW'];
          if (preview != null && lang == 'ar') {
            final box =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final img = await box.toImage();
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('$preview/account-${tv ? 'tv' : 'phone'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('account-submit')),
          );
          await tester.tap(find.byKey(const ValueKey('account-submit')));
          await tester.pumpAndSettle();
          expect(find.text(l.accountInvalidForm), findsOneWidget);
          await tester.ensureVisible(find.text(l.accountNeedAccount));
          await tester.tap(find.text(l.accountNeedAccount));
          await tester.pumpAndSettle();
          expect(find.byType(TvTextField), findsNWidgets(3));
          expect(
            tester
                .widget<TvTextField>(
                  find.byKey(const ValueKey('account-confirm')),
                )
                .obscureText,
            true,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
