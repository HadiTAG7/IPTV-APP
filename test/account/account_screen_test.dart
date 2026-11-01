import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/account/account_controller.dart';
import 'package:iptv_player/account/account_screen.dart';
import 'package:iptv_player/account/firebase_api.dart';
import 'package:iptv_player/app/form_factor.dart';
import 'package:iptv_player/core/db/app_db.dart';
import 'package:iptv_player/features/sources/sources_screen.dart';
import 'package:iptv_player/features/sources/widgets/tv_buttons.dart';
import 'package:iptv_player/l10n/gen/app_localizations.dart';
import 'package:iptv_player/sources/models.dart';
import 'package:iptv_player/theme/app_theme.dart';
import 'package:iptv_player/tv/dpad_shortcuts.dart';
import 'package:iptv_player/tv/tv_text_field.dart';

import '../support/text_entry.dart';
import '../unit/db/db_test_utils.dart';
import 'account_sync_test.dart' show Cloud, CountingApi, FakeApi;

/// Signing in fails with [code]; a password reset fails with it when set.
class FailingApi extends FirebaseAccountApi {
  FailingApi(this.code) : super(projectId: 'test', apiKey: 'test');
  String? code;
  int resets = 0;

  @override
  Future<AccountSession> signIn(
    String email,
    String password, {
    bool create = false,
  }) async => throw AccountException(code ?? 'INVALID_LOGIN_CREDENTIALS');

  @override
  Future<void> resetPassword(String email) async {
    resets++;
    if (code case final code?) throw AccountException(code);
  }
}

class MemoryVault implements SessionVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? value) async => this.value = value;
}

/// Signs in, syncs and sends password resets locally.
class LocalApi extends FakeApi {
  LocalApi(super.cloud);
  @override
  Future<void> resetPassword(String email) async {}
}

void main() {
  Future<AppLocalizations> pumpAccount(
    WidgetTester tester, {
    required String lang,
    required bool tv,
    required Override account,
    Size? size,
    Key? boundary,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        size ?? (tv ? const Size(1280, 720) : const Size(390, 844));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [account],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.dark(tv: tv),
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
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
    return AppLocalizations.of(tester.element(find.byType(AccountScreen)));
  }

  Override view(AccountView view) =>
      accountViewProvider.overrideWith((ref) => Stream.value(view));

  /// A real controller whose sign-in and reset go to [api].
  Override controller(FirebaseAccountApi api, AppDatabase db) =>
      accountControllerProvider.overrideWith((ref) {
        final c = AccountController(db: db, api: api, vault: MemoryVault());
        ref.onDispose(c.dispose);
        return c;
      });

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String password = 'sample'}) async {
    await typeText(
      tester,
      find.byKey(const ValueKey('account-email')),
      'viewer@example.test',
    );
    await typeText(
      tester,
      find.byKey(const ValueKey('account-password')),
      password,
    );
    await tester.pumpAndSettle();
  }

  for (final lang in ['ar', 'en']) {
    for (final tv in [false, true]) {
      testWidgets(
        '$lang ${tv ? 'TV' : 'phone'}: account form, password privacy and validation',
        (tester) async {
          final boundary = GlobalKey();
          final l = await pumpAccount(
            tester,
            lang: lang,
            tv: tv,
            account: view(const AccountView()),
            boundary: boundary,
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
          await tapKey(tester, 'account-submit');
          // Signing in asks for no new-password rules.
          expect(find.text(l.accountInvalidSignIn), findsOneWidget);
          await tapKey(tester, 'account-toggle');
          expect(find.byType(TvTextField), findsNWidgets(3));
          expect(
            tester
                .widget<TvTextField>(
                  find.byKey(const ValueKey('account-confirm')),
                )
                .obscureText,
            true,
          );
          await tapKey(tester, 'account-submit');
          expect(find.text(l.accountInvalidForm), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$lang TV: feedback shows under the pressed button, and the toggle '
      'keeps focus',
      (tester) async {
        final l = await pumpAccount(
          tester,
          lang: lang,
          tv: true,
          account: view(const AccountView()),
          size: const Size(960, 540),
        );
        bool focusedIn(String key) {
          var found = false;
          FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
            e,
          ) {
            found = e.widget.key == ValueKey(key);
            return !found;
          });
          return found;
        }

        Future<void> press(String key) async {
          Focus.of(
            tester.element(
              find
                  .descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(Text),
                  )
                  .first,
            ),
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
        }

        await press('account-submit');
        final error = tester.getRect(find.text(l.accountInvalidSignIn));
        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        expect(
          error.top,
          greaterThan(
            tester.getRect(find.byKey(const ValueKey('account-submit'))).bottom,
          ),
        );
        expect(
          error.bottom,
          lessThan(
            tester.getRect(find.byKey(const ValueKey('account-toggle'))).top,
          ),
        );
        expect(error.bottom, lessThanOrEqualTo(viewport.bottom));
        await press('account-toggle');
        expect(find.byKey(const ValueKey('account-confirm')), findsOneWidget);
        expect(focusedIn('account-toggle'), isTrue);
      },
    );

    testWidgets(
      '$lang phone: a failed sign-in clears on reset, on toggle and on '
      'reopening',
      (tester) async {
        final db = openTestDb();
        addTearDown(db.close);
        final api = FailingApi('INVALID_LOGIN_CREDENTIALS');
        final l = await pumpAccount(
          tester,
          lang: lang,
          tv: false,
          account: controller(api, db),
        );
        Future<void> failSignIn() async {
          api.code = 'INVALID_LOGIN_CREDENTIALS';
          await fill(tester);
          await tapKey(tester, 'account-submit');
          expect(find.text(l.accountAuthFailed), findsOneWidget);
        }

        await failSignIn();
        api.code = null;
        await tapKey(tester, 'account-reset');
        expect(api.resets, 1);
        expect(find.text(l.accountResetSent), findsOneWidget);
        expect(find.text(l.accountAuthFailed), findsNothing);
        await failSignIn();
        await tapKey(tester, 'account-toggle');
        expect(find.byKey(const ValueKey('account-confirm')), findsOneWidget);
        expect(find.text(l.accountAuthFailed), findsNothing);
        await tapKey(tester, 'account-toggle');
        await failSignIn();
        unawaited(
          Navigator.of(tester.element(find.byType(AccountScreen)))
              .pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
              ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.accountAuthFailed), findsNothing);
      },
    );

    testWidgets('$lang phone: sign-in and reset failures never mention sync', (
      tester,
    ) async {
      final db = openTestDb();
      addTearDown(db.close);
      final api = FailingApi(null);
      final l = await pumpAccount(
        tester,
        lang: lang,
        tv: false,
        account: controller(api, db),
      );
      await fill(tester);
      for (final (code, text) in [
        ('TOO_MANY_ATTEMPTS_TRY_LATER', l.accountTooManyAttempts),
        ('NETWORK_ERROR', l.accountServiceUnavailable),
        ('UNAVAILABLE', l.accountServiceUnavailable),
      ]) {
        api.code = code;
        await tapKey(tester, 'account-submit');
        expect(find.text(text), findsOneWidget, reason: code);
        expect(find.text(l.accountSyncFailed), findsNothing, reason: code);
      }
      api.code = 'NETWORK_ERROR';
      await tapKey(tester, 'account-reset');
      expect(find.text(l.accountServiceUnavailable), findsOneWidget);
      // A reset needs the email only.
      await tester.enterText(find.byKey(const ValueKey('account-email')), '');
      await tapKey(tester, 'account-reset');
      expect(find.text(l.accountInvalidEmail), findsOneWidget);
      expect(api.resets, 1);
    });

    testWidgets('$lang TV: feedback above the focused button keeps that '
        'button in view', (tester) async {
      applyFocusHighlightStrategy(tv: true);
      addTearDown(() => applyFocusHighlightStrategy(tv: false));
      final db = openTestDb();
      addTearDown(db.close);
      await db.sourcesDao.create(
        const SourceConfig(
          kind: SourceKind.xtream,
          name: 'Sports',
          url: 'https://provider.example',
          username: 'sample',
          password: 'private-password',
        ),
      );
      final cloud = Cloud();
      late AccountController account;
      final l = await pumpAccount(
        tester,
        lang: lang,
        tv: true,
        size: const Size(960, 540),
        account: accountControllerProvider.overrideWith((ref) {
          account = AccountController(
            db: db,
            api: LocalApi(cloud),
            vault: MemoryVault(),
          );
          ref.onDispose(account.dispose);
          return account;
        }),
      );
      Future<void> focus(String key) async {
        Focus.of(
          tester.element(
            find
                .descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(Text),
                )
                .first,
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
      }

      void expectInView(String key) {
        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        final button = tester.getRect(find.byKey(ValueKey(key)));
        expect(button.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<TvButton>()
              ?.key,
          ValueKey(key),
        );
      }

      // The reset confirmation shows above Reset password.
      await typeText(
        tester,
        find.byKey(const ValueKey('account-email')),
        'viewer@example.test',
      );
      await focus('account-reset');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(l.accountResetSent), findsOneWidget);
      expectInView('account-reset');
      // A failed poll shows its error above Sign out.
      await tester.runAsync(
        () => account.authenticate('viewer@example.test', 'sample-password'),
      );
      await tester.pumpAndSettle();
      await focus('account-sign-out');
      cloud.offline = true;
      await tester.runAsync(() => account.sync(force: true));
      await tester.pumpAndSettle();
      expect(find.text(l.accountSyncFailed), findsOneWidget);
      expectInView('account-sign-out');
    });

    testWidgets('$lang: deleting a source on a device linked to an account '
        'says the other devices lose it too', (tester) async {
      final l = lookupAppLocalizations(Locale(lang));
      for (final (i, (account, synced)) in [
        (const AccountView(), false),
        (const AccountView(email: 'viewer@example.test', linked: true), true),
        // Signed out: the deletion still syncs at the next sign-in.
        (const AccountView(linked: true), true),
      ].indexed) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(i),
            overrides: [view(account)],
            child: MaterialApp(
              locale: Locale(lang),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: DeleteSourceDialog(name: 'Home')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            synced
                ? l.settingsDeleteSourceConfirmSynced('Home')
                : l.settingsDeleteSourceConfirm('Home'),
          ),
          findsOneWidget,
          reason: '$i',
        );
      }
    });

    test('$lang: the account intro says language settings sync', () {
      final l = lookupAppLocalizations(Locale(lang));
      expect(l.accountIntro, contains(lang == 'ar' ? 'اللغة' : 'language'));
    });

    testWidgets('$lang phone: an expired sign-in explains the sign-in form', (
      tester,
    ) async {
      final l = await pumpAccount(
        tester,
        lang: lang,
        tv: false,
        account: view(const AccountView(error: 'SESSION_EXPIRED')),
      );
      expect(find.byKey(const ValueKey('account-email')), findsOneWidget);
      expect(find.text(l.accountSessionExpired), findsOneWidget);
    });

    testWidgets('$lang phone: the signed-in email lines up with the text '
        'below it', (tester) async {
      const email = 'viewer@example.test';
      final l = await pumpAccount(
        tester,
        lang: lang,
        tv: false,
        account: view(AccountView(email: email, lastSync: DateTime(2026))),
      );
      Rect glyphs(String text) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find
              .descendant(of: find.text(text), matching: find.byType(RichText))
              .first,
        );
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        return boxes
            .map((b) => b.toRect())
            .reduce((a, b) => a.expandToInclude(b))
            .shift(paragraph.localToGlobal(Offset.zero));
      }

      final address = glyphs(email);
      final status = glyphs(l.accountSynced);
      if (lang == 'ar') {
        expect(address.right, moreOrLessEquals(status.right, epsilon: 2));
      } else {
        expect(address.left, moreOrLessEquals(status.left, epsilon: 2));
      }
    });

    /// Lets the controller's database and account calls run.
    Future<void> work(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    for (final tv in [false, true]) {
      testWidgets('$lang ${tv ? 'TV' : 'phone'}: Done on the last field '
          'submits, and the keyboard stays closed over the result', (
        tester,
      ) async {
        applyFocusHighlightStrategy(tv: tv);
        addTearDown(() => applyFocusHighlightStrategy(tv: false));
        final db = openTestDb();
        addTearDown(db.close);
        final l = await pumpAccount(
          tester,
          lang: lang,
          tv: tv,
          size: tv ? const Size(960, 540) : null,
          account: controller(FailingApi('INVALID_LOGIN_CREDENTIALS'), db),
        );
        for (final create in [false, true]) {
          if (create) await tapKey(tester, 'account-toggle');
          await typeText(
            tester,
            find.byKey(const ValueKey('account-email')),
            'viewer@example.test',
          );
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('account-password')),
            'sample-password',
          );
          if (create) {
            await tester.testTextInput.receiveAction(TextInputAction.next);
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const ValueKey('account-confirm')),
              'sample-password',
            );
          }
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await work(tester);
          expect(find.text(l.accountAuthFailed), findsOneWidget);
          expect(tester.testTextInput.isVisible, isFalse, reason: '$create');
        }
      });
    }

    testWidgets('$lang TV: signing in with another account offers to move '
        'this device to it, after saying what happens to its data', (
      tester,
    ) async {
      applyFocusHighlightStrategy(tv: true);
      addTearDown(() => applyFocusHighlightStrategy(tv: false));
      final db = openTestDb();
      addTearDown(db.close);
      final cloud = Cloud();
      await tester.runAsync(() async {
        await db.sourcesDao.create(
          const SourceConfig(
            kind: SourceKind.xtream,
            name: 'Sports',
            url: 'https://provider.example',
            username: 'sample',
            password: 'private-password',
          ),
        );
        final first = AccountController(
          db: db,
          api: LocalApi(cloud),
          vault: MemoryVault(),
        );
        await first.authenticate('owner@example.test', 'sample-password');
        await first.signOut();
        first.dispose();
      });
      late AccountController account;
      final l = await pumpAccount(
        tester,
        lang: lang,
        tv: true,
        size: const Size(960, 540),
        account: accountControllerProvider.overrideWith((ref) {
          account = AccountController(
            db: db,
            api: LocalApi(cloud),
            vault: MemoryVault(),
          );
          ref.onDispose(account.dispose);
          return account;
        }),
      );
      await typeText(
        tester,
        find.byKey(const ValueKey('account-email')),
        'other@example.test',
      );
      await typeText(
        tester,
        find.byKey(const ValueKey('account-password')),
        'sample-password',
      );
      await tapKey(tester, 'account-submit');
      await work(tester);
      const owner = 'owner@example.test';
      final message = l.accountOtherOwnerNamed(owner);
      expect(message, contains('\u2068$owner\u2069'));
      expect(find.text(message), findsOneWidget);
      // Cancel keeps the device as it was.
      await tapKey(tester, 'account-switch');
      expect(find.text(l.accountSwitchBody(owner)), findsOneWidget);
      await tapKey(tester, 'account-switch-cancel');
      expect(find.byType(SwitchAccountDialog), findsNothing);
      expect(account.view.linked, isTrue);
      await tapKey(tester, 'account-switch');
      await tapKey(tester, 'account-switch-confirm');
      await work(tester);
      expect(account.view.email, 'other@example.test');
      expect(find.byKey(const ValueKey('account-sync')), findsOneWidget);
      // The remote keeps a focused control.
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TvButton>()
            ?.key,
        const ValueKey('account-sync'),
      );
      await tester.runAsync(() async {
        expect(await db.sourcesDao.all(), hasLength(1));
      });
    });

    testWidgets('$lang phone: Create account with the email this device '
        'belongs to says to sign in, and offers no switch', (tester) async {
      final db = openTestDb();
      addTearDown(db.close);
      final api = CountingApi(Cloud())..taken.add('owner@example.test');
      await tester.runAsync(() async {
        final first = AccountController(db: db, api: api, vault: MemoryVault());
        await first.authenticate('owner@example.test', 'sample-password');
        await first.signOut();
        first.dispose();
      });
      late AccountController account;
      final l = await pumpAccount(
        tester,
        lang: lang,
        tv: false,
        account: accountControllerProvider.overrideWith((ref) {
          account = AccountController(db: db, api: api, vault: MemoryVault());
          ref.onDispose(account.dispose);
          return account;
        }),
      );
      await tapKey(tester, 'account-toggle');
      for (final (key, text) in [
        ('account-email', 'owner@example.test'),
        ('account-password', 'sample-password'),
        ('account-confirm', 'sample-password'),
      ]) {
        await typeText(tester, find.byKey(ValueKey(key)), text);
      }
      await tester.pumpAndSettle();
      await tapKey(tester, 'account-submit');
      await work(tester);
      expect(find.text(l.accountExists), findsOneWidget);
      expect(find.byKey(const ValueKey('account-switch')), findsNothing);
      expect(api.signUps, 1);
      expect(account.view.email, isNull);
      await tester.runAsync(() async {
        expect(
          await db.settingsDao.getString(AccountController.ownerEmailKey),
          'owner@example.test',
        );
      });
    });

    testWidgets('$lang phone: the switch confirmation scrolls at the largest '
        'font size rather than lose its end', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      const owner = 'owner.family.account@example.test';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(tv: false),
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: SwitchAccountDialog(owner: owner)),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(SwitchAccountDialog)),
      );
      final body = find.text(l.accountSwitchBody(owner));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: body, matching: find.byType(RichText)),
      );
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 1,
        ),
      );
      expect(tester.takeException(), isNull);
      final confirm = find.byKey(const ValueKey('account-switch-confirm'));
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(844));
    });

    test('$lang: a sync stopped for a reason that does not clear by itself '
        'never reads like a dropped connection', () {
      final l = lookupAppLocalizations(Locale(lang));
      final dropped = accountErrorText(l, 'NETWORK_ERROR');
      expect(dropped, l.accountSyncFailed);
      expect(accountErrorText(l, 'PERMISSION_DENIED'), l.accountSyncDenied);
      for (final code in [
        'RECORD_TOO_LARGE',
        'SYNC_ERROR',
        'INVALID_PLAYLIST',
      ]) {
        expect(accountErrorPasses(code), isFalse, reason: code);
        expect(accountErrorText(l, code), l.accountSyncBlocked, reason: code);
      }
      for (final text in [l.accountSyncDenied, l.accountSyncBlocked]) {
        expect(text, isNot(dropped));
        expect(text, contains(l.accountSyncNow));
      }
      // Signed out, the account service could not be reached.
      expect(
        accountErrorText(l, 'SYNC_ERROR', signedOut: true),
        l.accountServiceUnavailable,
      );
    });

    test('$lang: switching a device linked by an earlier version explains '
        'it without the email', () {
      final l = lookupAppLocalizations(Locale(lang));
      expect(l.accountSwitchBodyUnnamed, isNot(contains('\u2068')));
      expect(l.accountSwitchBody('a@example.test'), contains('\u2068'));
    });

    testWidgets('$lang TV: Sign out answers during a background poll', (
      tester,
    ) async {
      applyFocusHighlightStrategy(tv: true);
      addTearDown(() => applyFocusHighlightStrategy(tv: false));
      final db = openTestDb();
      addTearDown(db.close);
      final api = GatedApi(Cloud());
      late AccountController account;
      await pumpAccount(
        tester,
        lang: lang,
        tv: true,
        size: const Size(960, 540),
        account: accountControllerProvider.overrideWith((ref) {
          account = AccountController(db: db, api: api, vault: MemoryVault());
          ref.onDispose(account.dispose);
          return account;
        }),
      );
      await tester.runAsync(
        () => account.authenticate('viewer@example.test', 'sample-password'),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TvButton>()
            ?.key,
        const ValueKey('account-sign-out'),
      );
      // The 30 s poll, its revision check slow to answer.
      final gate = api.gate = Completer<void>();
      final poll = account.sync();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      Finder spinner(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(CircularProgressIndicator),
      );
      expect(spinner('account-sync'), findsOneWidget);
      expect(spinner('account-sign-out'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      api.gate = null;
      gate.complete();
      await tester.runAsync(() => poll);
      await work(tester);
      expect(account.view.email, isNull);
    });

    testWidgets('$lang phone: the reset confirmation is announced', (
      tester,
    ) async {
      final db = openTestDb();
      addTearDown(db.close);
      final l = await pumpAccount(
        tester,
        lang: lang,
        tv: false,
        account: controller(FailingApi(null), db),
      );
      await fill(tester);
      await tapKey(tester, 'account-reset');
      expect(find.text(l.accountResetSent), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('account-message')))
            .properties
            .liveRegion,
        isTrue,
      );
    });
  }

  test('English copy spells favorites as the Favorites tab does', () {
    expect(
      File('lib/l10n/app_en.arb').readAsStringSync(),
      isNot(contains('avourite')),
    );
  });
}

/// A background poll whose revision check waits for [gate].
class GatedApi extends LocalApi {
  GatedApi(super.cloud);
  Completer<void>? gate;
  @override
  Future<String?> revision(AccountSession session) async {
    await gate?.future;
    return super.revision(session);
  }
}
