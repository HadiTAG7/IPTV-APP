import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../widgets/bidi_text.dart';
import 'home_shell.dart';
import 'providers.dart';

/// Phone home: a bottom [NavigationBar] with Live, Guide, Movies, Series and
/// More (Search, Favorites, Sources, Settings, Help as pushed pages).
///
/// Tabs are built on first visit and keep their state in an [IndexedStack].
class PhoneShell extends ConsumerStatefulWidget {
  const PhoneShell({super.key, this.pages});

  /// Tab state shared with [TvShell] (see [HomePages]); a private one when
  /// null.
  final HomePages? pages;

  @override
  ConsumerState<PhoneShell> createState() => PhoneShellState();
}

class PhoneShellState extends ConsumerState<PhoneShell> {
  static const tabs = HomeTab.phoneTabs;

  late final HomePages _pages = widget.pages ?? HomePages();
  int _index = 0;

  /// The selected tab.
  HomeTab get current => tabs[_index];

  @override
  void initState() {
    super.initState();
    // A large-layout destination without a bar slot (Search, Favorites,
    // Settings) is reached through More here.
    final i = tabs.indexOf(_pages.selected);
    _index = i >= 0 ? i : tabs.indexOf(HomeTab.more);
    _pages.visited.add(tabs[_index]);
  }

  /// Back: the tab's [HomeTabBackHandler]s, else another tab returns to
  /// Live. Returns whether it was used.
  bool handleBack() {
    if (_pages.backsOf(current).handle()) return true;
    if (_index == 0) return false;
    select(tabs.first);
    return true;
  }

  void select(HomeTab tab) {
    final i = tabs.indexOf(tab);
    if (i < 0 || (i == _index && _pages.visited.contains(tab))) return;
    setState(() {
      _index = i;
      _pages.show(tab);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pageFor = ref.watch(homePageBuilderProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: _index,
                sizing: StackFit.expand,
                children: [
                  for (final tab in tabs)
                    HomeBackScope(
                      registry: _pages.backsOf(tab),
                      child: _pages.visited.contains(tab)
                          ? KeyedSubtree(
                              key: _pages.keyOf(tab),
                              child: tab == HomeTab.more
                                  ? const MorePage()
                                  : pageFor(tab),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            const PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: SyncIndicator(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => select(tabs[i]),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              key: ValueKey('nav-${tab.name}'),
              icon: Icon(tab.icon),
              label: tab.label(l10n),
            ),
        ],
      ),
    );
  }
}

/// The phone "More" tab: the active source (tap to switch) and the
/// destinations without a bottom-bar slot.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final source = ref.watch(activeSourceProvider);
    final count = ref.watch(sourcesProvider).value?.length ?? 0;
    return ListView(
      children: [
        ListTile(
          key: const ValueKey('more-source'),
          leading: const Icon(Icons.playlist_play),
          title: BidiText(source?.name ?? l10n.settingsNoSources),
          subtitle: Text(l10n.navSwitchSource),
          trailing: count > 1 ? const Icon(Icons.unfold_more) : null,
          onTap: count > 0 ? () => showSourceSwitcher(context, ref) : null,
        ),
        const Divider(),
        for (final item in HomeTab.phoneMoreItems)
          ListTile(
            key: ValueKey('more-${item.name}'),
            leading: Icon(item.icon),
            title: Text(item.label(l10n)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pushHomePage(context, ref, item),
          ),
      ],
    );
  }
}
