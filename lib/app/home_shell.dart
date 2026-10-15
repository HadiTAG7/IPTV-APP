import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/diagnostics/diagnostics_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/guide/guide_screen.dart';
import '../features/help/help_screen.dart';
import '../features/live/live_screen.dart';
import '../features/movies/movies_screen.dart';
import '../features/search/search_screen.dart';
import '../features/series/series_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sources/sources_screen.dart';
import '../l10n/gen/app_localizations.dart';
import '../sources/source_repository.dart';
import '../sources/sync/sync_progress.dart';
import '../theme/tokens.dart';
import '../tv/tv_focusable.dart';
import '../widgets/bidi_text.dart';
import 'form_factor.dart';
import 'providers.dart';
import 'shell_phone.dart';
import 'shell_tv.dart';

/// Destinations of the home shells.
///
/// TV / large layout rail: [tvTabs]. Phone bottom bar: [phoneTabs], where
/// [more] opens a list of [phoneMoreItems].
enum HomeTab {
  live,
  guide,
  movies,
  series,
  search,
  favorites,
  settings,
  sources,
  help,
  diagnostics,
  more;

  static const tvTabs = [
    live,
    guide,
    movies,
    series,
    search,
    favorites,
    settings,
  ];
  static const phoneTabs = [live, guide, movies, series, more];
  static const phoneMoreItems = [search, favorites, sources, settings, help];

  String label(AppLocalizations l10n) => switch (this) {
    live => l10n.navLive,
    guide => l10n.navGuide,
    movies => l10n.navMovies,
    series => l10n.navSeries,
    search => l10n.navSearch,
    favorites => l10n.navFavorites,
    settings => l10n.navSettings,
    sources => l10n.navSources,
    help => l10n.helpTitle,
    diagnostics => l10n.diagTitle,
    more => l10n.navMore,
  };

  IconData get icon => switch (this) {
    live => Icons.live_tv_outlined,
    guide => Icons.view_timeline_outlined,
    movies => Icons.movie_outlined,
    series => Icons.video_library_outlined,
    search => Icons.search,
    favorites => Icons.star_outline,
    settings => Icons.settings_outlined,
    sources => Icons.playlist_play,
    help => Icons.help_outline,
    diagnostics => Icons.monitor_heart_outlined,
    more => Icons.more_horiz,
  };
}

/// The screen for a destination (feature screens render body content only).
Widget defaultHomePage(HomeTab tab) => switch (tab) {
  HomeTab.live => const LiveScreen(),
  HomeTab.guide => const GuideScreen(),
  HomeTab.movies => const MoviesScreen(),
  HomeTab.series => const SeriesScreen(),
  HomeTab.search => const SearchScreen(),
  HomeTab.favorites => const FavoritesScreen(),
  HomeTab.settings => const SettingsScreen(),
  HomeTab.sources => const SourcesScreen(),
  HomeTab.help => const HelpScreen(),
  HomeTab.diagnostics => const DiagnosticsScreen(),
  HomeTab.more => const SizedBox.shrink(),
};

/// Builds the page of each destination; tests swap in simple pages.
final homePageBuilderProvider = Provider<Widget Function(HomeTab tab)>(
  (ref) => defaultHomePage,
);

/// Pushes [tab]'s screen as a page with an app bar (phone "More" items and
/// any screen opened from another one).
///
/// On TV the app bar keeps clear of the overscan margins and has no Back
/// arrow: the remote's Back key (Escape on a keyboard) closes the page, and
/// a focusable arrow in the corner would sit where TVs crop the picture.
/// The pages add the side and bottom margins to their own content.
Future<void> pushHomePage(BuildContext context, WidgetRef ref, HomeTab tab) {
  final page = ref.read(homePageBuilderProvider)(tab);
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: '/${tab.name}'),
      builder: (context) {
        final tv = FormFactorScope.isTv(context);
        final scaffold = Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !tv,
            titleSpacing: tv ? TvLayout.overscanHorizontal : null,
            title: Text(tab.label(AppLocalizations.of(context))),
          ),
          body: SafeArea(top: false, child: page),
        );
        if (!tv) return scaffold;
        return ColoredBox(
          color: AppColors.background,
          child: Padding(
            padding: const EdgeInsets.only(top: TvLayout.overscanVertical),
            child: scaffold,
          ),
        );
      },
    ),
  );
}

/// Back handlers of one home tab, newest first. The shells keep one per tab.
class HomeBackRegistry {
  final _handlers = <bool Function()>[];

  void add(bool Function() handler) => _handlers.add(handler);

  void remove(bool Function() handler) => _handlers.remove(handler);

  /// Asks the handlers, newest first; true when one handled Back.
  bool handle() {
    for (final handler in _handlers.reversed.toList()) {
      if (handler()) return true;
    }
    return false;
  }
}

/// Tab state shared by [TvShell] and [PhoneShell], owned by [HomeShell].
///
/// [HomeShell] swaps the shells when the layout changes (rotating a tablet
/// or a large phone, split screen, resizing a window). The selected
/// destination, the visited pages and their back handlers live here, and
/// every page subtree has a [GlobalKey], so the visited pages move into the
/// new shell in the same frame with their state (scroll positions, typed
/// text, inner selection). Pages the new shell has no slot for (Search,
/// Favorites and Settings live under More on the phone) are rebuilt when
/// the large layout comes back.
class HomePages {
  /// The destination picked last, in either shell.
  HomeTab selected = HomeTab.live;

  /// Destinations whose page has been built.
  final visited = <HomeTab>{HomeTab.live};

  final _keys = <HomeTab, GlobalKey>{};
  final _backs = <HomeTab, HomeBackRegistry>{};

  /// The key of [tab]'s page subtree.
  GlobalKey keyOf(HomeTab tab) =>
      _keys.putIfAbsent(tab, () => GlobalKey(debugLabel: 'home:${tab.name}'));

  /// The back handlers of [tab]'s page.
  HomeBackRegistry backsOf(HomeTab tab) =>
      _backs.putIfAbsent(tab, HomeBackRegistry.new);

  /// Marks [tab] as selected and visited.
  void show(HomeTab tab) {
    selected = tab;
    visited.add(tab);
  }
}

/// Gives a tab page access to its [HomeBackRegistry] (installed by the
/// shells around every page).
class HomeBackScope extends InheritedWidget {
  const HomeBackScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final HomeBackRegistry registry;

  static HomeBackRegistry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeBackScope>()?.registry;

  @override
  bool updateShouldNotify(HomeBackScope oldWidget) =>
      oldWidget.registry != registry;
}

/// Lets a home tab page handle Back before the shell (for example to move
/// from a channel list back to its categories). [onBack] returns true when
/// it handled the press. Use this instead of a `PopScope` inside a tab page:
/// every `PopScope` of a route is told about each Back press, so a nested one
/// would fire together with the shell's.
class HomeTabBackHandler extends StatefulWidget {
  const HomeTabBackHandler({
    super.key,
    required this.onBack,
    required this.child,
  });

  final bool Function() onBack;
  final Widget child;

  @override
  State<HomeTabBackHandler> createState() => _HomeTabBackHandlerState();
}

class _HomeTabBackHandlerState extends State<HomeTabBackHandler> {
  HomeBackRegistry? _registry;

  bool _handle() => widget.onBack();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = HomeBackScope.maybeOf(context);
    if (registry != _registry) {
      _registry?.remove(_handle);
      _registry = registry?..add(_handle);
    }
  }

  @override
  void dispose() {
    _registry?.remove(_handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The signed-in home: the TV / large-layout rail shell or the phone shell.
///
/// * The shells share one [HomePages], so switching layouts keeps the
///   selected tab and the visited pages' state.
/// * Back: the current tab's [HomeTabBackHandler]s first (on TV only while
///   focus is in the page), then the shell (TV: page -> rail; phone: other
///   tab -> Live), then "press back again to exit" within 2 s.
/// * Starts a sync of the active source when its catalog is older than
///   [autoSyncMaxAge] or was never synced (once per source per launch).
/// * Shows a snack bar when a sync of the active source fails.
/// * [HomeShellState.showTab] switches tabs from outside the shells (the
///   player's Guide button).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  /// How long a second Back press exits the app.
  static const exitWindow = Duration(seconds: 2);

  /// The home shell [context] is in (a tab page), or null for a pushed
  /// page or a dialog (their routes sit above the shell).
  static HomeShellState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<HomeShellState>();

  @override
  ConsumerState<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends ConsumerState<HomeShell> {
  final _tvKey = GlobalKey<TvShellState>();
  final _phoneKey = GlobalKey<PhoneShellState>();
  final _pages = HomePages();
  final _autoSynced = <int>{};
  DateTime? _lastBack;

  @override
  void initState() {
    super.initState();
    ref.listenManual<SourceView?>(
      activeSourceProvider,
      (_, source) => _scheduleAutoSync(source),
      fireImmediately: true,
    );
  }

  void _scheduleAutoSync(SourceView? source) {
    if (source == null || _autoSynced.contains(source.id)) return;
    if (!ref.read(autoSyncOnStartProvider)) return;
    if (!needsAutoSync(source, ref.read(clockProvider).now())) return;
    _autoSynced.add(source.id);
    // Not during build: starting a sync updates providers.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => unawaited(_autoSync(source.id)))
      ..ensureVisualUpdate();
  }

  /// Syncs [sourceId] unless a sync of it is running or its saved row says
  /// it is fresh. The row the shell was built with can be older than the
  /// database: the import that just added the source (onboarding, the
  /// source editor) saves its sync time right before the shell appears, and
  /// must not be followed by a second full import.
  Future<void> _autoSync(int sourceId) async {
    if (!mounted) return;
    final sync = ref.read(syncServiceProvider);
    final dao = ref.read(sourcesDaoProvider);
    final clock = ref.read(clockProvider);
    final log = ref.read(ringLogProvider);
    if (sync.isRunning(sourceId)) return;
    final SourceView? saved;
    try {
      saved = await dao.byId(sourceId);
    } on Object catch (e, st) {
      log.error('Reading the source failed', e, st);
      return;
    }
    if (!mounted || saved == null || sync.isRunning(sourceId)) return;
    if (needsAutoSync(saved, clock.now())) sync.sync(sourceId);
  }

  /// Shows [tab] in the shell on screen now (the TV / large-layout rail or
  /// the phone bar); with [enter], focus moves into its page (large
  /// layout). The choice is kept in [HomePages], so it survives the shells
  /// being swapped (a phone turning back to portrait after the player).
  /// A destination the shell on screen has no slot for is ignored.
  void showTab(HomeTab tab, {bool enter = false}) {
    if (!mounted) return;
    final tv = _tvKey.currentState;
    final phone = _phoneKey.currentState;
    if (tv != null) {
      tv.select(tab, enter: enter);
    } else if (phone != null) {
      phone.select(tab);
    } else {
      setState(() => _pages.show(tab));
    }
  }

  void _onBack() {
    final handled =
        _tvKey.currentState?.handleBack() ??
        _phoneKey.currentState?.handleBack() ??
        false;
    if (handled) return;
    final now = ref.read(clockProvider).now();
    final last = _lastBack;
    if (last != null && now.difference(last) <= HomeShell.exitWindow) {
      _lastBack = null;
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      ref.read(appExitProvider)();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).commonPressBackAgainToExit,
          ),
          duration: HomeShell.exitWindow,
        ),
      );
  }

  void _onSyncStatus(SyncStatus? previous, SyncStatus next) {
    if (previous is! SyncRunning || next is! SyncFailed) return;
    final error = next.error;
    if (next.cancelled || error == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(describeSourceError(l10n, error))));
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeSourceIdProvider);
    if (activeId != null) {
      ref.listen(syncStatusProvider(activeId), _onSyncStatus);
    }
    final large = isLargeLayout(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: large
          ? TvShell(key: _tvKey, pages: _pages)
          : PhoneShell(key: _phoneKey, pages: _pages),
    );
  }
}

/// A thin progress bar while the active source is syncing.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(activeSourceIdProvider);
    if (id == null) return const SizedBox.shrink();
    final status = ref.watch(syncStatusProvider(id));
    if (status is! SyncRunning) return const SizedBox.shrink();
    return Semantics(
      label: AppLocalizations.of(context).importTitle,
      child: const LinearProgressIndicator(minHeight: 2),
    );
  }
}

/// Lets the user pick the active source from a dialog.
Future<void> showSourceSwitcher(BuildContext context, WidgetRef ref) async {
  final sources = ref.read(sourcesProvider).value ?? const <SourceView>[];
  if (sources.isEmpty) return;
  final active = ref.read(activeSourceIdProvider);
  final picked = await showDialog<int>(
    context: context,
    builder: (_) => SourceSwitcherDialog(sources: sources, activeId: active),
  );
  if (picked != null && picked != active) {
    await ref.read(activeSourceIdProvider.notifier).select(picked);
  }
}

/// The list behind [showSourceSwitcher]; pops the picked source id.
class SourceSwitcherDialog extends StatelessWidget {
  const SourceSwitcherDialog({
    super.key,
    required this.sources,
    required this.activeId,
  });

  final List<SourceView> sources;
  final int? activeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasActive = sources.any((s) => s.id == activeId);
    return AlertDialog(
      title: Text(l10n.navSwitchSource),
      contentPadding: const EdgeInsets.symmetric(vertical: Spacing.md),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, s) in sources.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xxs,
                  ),
                  child: TvFocusable(
                    key: ValueKey('source-${s.id}'),
                    autofocus: hasActive ? s.id == activeId : i == 0,
                    focusScale: 1.02,
                    onSelect: () => Navigator.of(context).pop(s.id),
                    child: ListTile(
                      leading: Icon(
                        s.id == activeId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: s.id == activeId
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      title: BidiText(s.name),
                      subtitle: s.id == activeId
                          ? Text(l10n.settingsActive)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

/// A localized, user-facing message for a source or sync failure.
String describeSourceError(AppLocalizations l10n, VerifyError error) =>
    switch (error.reason) {
      VerifyErrorReason.invalidUrl => l10n.errorInvalidUrl,
      VerifyErrorReason.unreachable => switch (error.statusCode) {
        final code? => l10n.errorHttpStatus(code),
        null => l10n.errorUnreachable,
      },
      VerifyErrorReason.timeout => l10n.errorTimeout,
      VerifyErrorReason.authFailed => l10n.errorAuthFailed,
      VerifyErrorReason.expired => switch (error.expiresAt) {
        final date? => l10n.errorExpired(date.toLocal()),
        null => l10n.errorExpiredNoDate,
      },
      VerifyErrorReason.banned => l10n.errorBanned,
      VerifyErrorReason.disabled => l10n.errorDisabled,
      VerifyErrorReason.notM3u => l10n.errorNotM3u,
      VerifyErrorReason.fileUnreadable => l10n.errorFileRead,
      VerifyErrorReason.incomplete => l10n.errorCatalogIncomplete,
      VerifyErrorReason.unknown => l10n.commonErrorGeneric,
    };
