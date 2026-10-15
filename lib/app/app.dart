import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../epg/epg_providers.dart';
import '../l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';
import '../tv/dpad_shortcuts.dart';
import '../tv/focus_watchdog.dart';
import 'form_factor.dart';
import 'providers.dart';
import 'root_gate.dart';

/// The root navigator (also used by the Escape-means-Back action).
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => GlobalKey<NavigatorState>(debugLabel: 'root navigator'),
);

/// The app: dark theme, Arabic/English with RTL, remote-friendly shortcuts,
/// and [RootGate] as home.
///
/// The locale follows Settings (Auto uses the device language when it is
/// Arabic or English, else English). The builder installs [AppFrame].
///
/// Keeps the background guide schedule ([epgAutoRefreshProvider]) running
/// for the app's lifetime: guides are refreshed after every successful
/// catalog sync (the first import included), on launch when due, and
/// periodically.
class IptvApp extends ConsumerWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(epgAutoRefreshProvider, (_, _) {});
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final tv = ref.watch(tvModeProvider);
    return MaterialApp(
      navigatorKey: ref.watch(navigatorKeyProvider),
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(tv: tv),
      locale: locale.locale,
      localeListResolutionCallback: resolveAppLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      shortcuts: appShortcuts,
      builder: (context, child) =>
          AppFrame(child: child ?? const SizedBox.shrink()),
      home: const RootGate(),
    );
  }
}

/// Picks the first preferred locale whose language the app supports
/// (Arabic or English), else English.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  final languages = {for (final l in supported) l.languageCode};
  for (final l in preferred ?? const <Locale>[]) {
    if (languages.contains(l.languageCode)) return Locale(l.languageCode);
  }
  return const Locale('en');
}

/// Wraps the navigator: resolves the [FormFactor] from the screen
/// ([FormFactorScope]), lays TV out on the 960 dp canvas ([TvViewport]),
/// keeps remote focus alive ([FocusWatchdog]) and handles [BackIntent]
/// (Escape, the browser Back key) like the system back button: `maybePop`
/// on the root navigator, so every route's `PopScope` still decides. Page
/// Up and Page Down move focus ([PageFocusAction]).
///
/// The navigator has a global key, so switching TV mode on or off keeps
/// the route stack.
class AppFrame extends ConsumerStatefulWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends ConsumerState<AppFrame> {
  bool? _highlightTv;

  void _applyHighlight(bool tv) {
    if (_highlightTv == tv) return;
    _highlightTv = tv;
    // Changing the highlight mode notifies focus widgets: not during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) applyFocusHighlightStrategy(tv: tv);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final formFactor = ref.watch(formFactorProvider(size));
    final tv = formFactor == FormFactor.tv;
    _applyHighlight(tv);
    final navigator = ref.watch(navigatorKeyProvider);

    Widget body = FocusWatchdog(enabled: tv, child: widget.child);
    if (tv) body = TvViewport(child: body);
    return Actions(
      actions: {
        BackIntent: CallbackAction<BackIntent>(
          onInvoke: (_) => navigator.currentState?.maybePop(),
        ),
        PageFocusIntent: PageFocusAction(),
      },
      child: FormFactorScope(formFactor: formFactor, child: body),
    );
  }
}
