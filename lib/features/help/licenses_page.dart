import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/key_repeat.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/states.dart';

/// Opens the licences of the app and its packages (and the fonts added by
/// `registerFontLicenses`).
///
/// On TV this is [TvLicensePage], whose text a remote can scroll; Flutter's
/// own licence page shows the text in a pane with nothing to focus. Touch,
/// mouse and phone layouts keep Flutter's page.
Future<void> showAppLicenses(
  BuildContext context, {
  required String applicationName,
  String? applicationVersion,
}) async {
  if (!FormFactorScope.isTv(context)) {
    showLicensePage(
      context: context,
      applicationName: applicationName,
      applicationVersion: applicationVersion,
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/licenses'),
      builder: (_) => TvLicensePage(
        applicationName: applicationName,
        applicationVersion: applicationVersion,
      ),
    ),
  );
}

/// The registered licences grouped by package.
@immutable
class LicenseCatalog {
  const LicenseCatalog(this.packages, this.entries);

  /// Package names, sorted case-insensitively.
  final List<String> packages;

  /// Licence entries of each package, in registry order.
  final Map<String, List<LicenseEntry>> entries;

  /// Collects [licenses] (default [LicenseRegistry.licenses]).
  static Future<LicenseCatalog> load([Stream<LicenseEntry>? licenses]) async {
    final entries = <String, List<LicenseEntry>>{};
    await for (final entry in licenses ?? LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        (entries[package] ??= []).add(entry);
      }
    }
    final packages = entries.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return LicenseCatalog(packages, entries);
  }
}

/// One line of the licence text pane: a paragraph, or (null) the divider
/// between two licences of a package.
typedef _LicenseLine = LicenseParagraph?;

/// The licences page on TV.
///
/// The package list is on the start side and the text of the focused
/// package on the end side. OK (or the arrow toward the end) moves focus
/// into the text, which is one focus stop: Up/Down scroll it by a few
/// lines (held keys speed up), Page Up/Page Down by a screen, and the arrow
/// toward the start or Back returns to the list. Back on the list closes
/// the page.
class TvLicensePage extends ConsumerStatefulWidget {
  const TvLicensePage({
    super.key,
    required this.applicationName,
    this.applicationVersion,
    this.licenses,
  });

  final String applicationName;
  final String? applicationVersion;

  /// Source of the licences; [LicenseRegistry.licenses] by default.
  final Stream<LicenseEntry> Function()? licenses;

  @override
  ConsumerState<TvLicensePage> createState() => _TvLicensePageState();
}

class _TvLicensePageState extends ConsumerState<TvLicensePage> {
  /// Delay before the text follows a package that got focus, so a held
  /// arrow does not lay out every licence it passes.
  static const _followDelay = Duration(milliseconds: 150);
  static const _rowExtent = 64.0;

  final _rowNodes = <int, FocusNode>{};
  final _textNode = FocusNode(debugLabel: 'licences:text');
  final _textScroll = ScrollController();
  final _listScroll = ScrollController();
  FocusWatchdogState? _watchdog;
  LicenseCatalog? _catalog;
  bool _failed = false;
  int _selected = 0;
  int? _pendingSelection;
  Timer? _followTimer;
  List<_LicenseLine> _lines = const [];
  bool _textFocused = false;

  FocusNode _rowNode(int index) => _rowNodes.putIfAbsent(
    index,
    () => FocusNode(debugLabel: 'licences:package $index'),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchdog = FocusWatchdog.maybeOf(context);
  }

  @override
  void dispose() {
    _followTimer?.cancel();
    final first = _rowNodes[0];
    if (first != null) _watchdog?.unregister(first);
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    _textNode.dispose();
    _textScroll.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final log = ref.read(ringLogProvider);
    if (_failed) setState(() => _failed = false);
    try {
      final catalog = await LicenseCatalog.load(widget.licenses?.call());
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _selected = 0;
        _lines = _linesOf(catalog, 0);
      });
      // The first package is autofocused; make it the watchdog's fallback
      // once it is in the tree.
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          if (mounted && catalog.packages.isNotEmpty) {
            _watchdog?.register(_rowNode(0));
          }
        })
        ..ensureVisualUpdate();
    } on Object catch (e, st) {
      log.error('Loading the licences failed', e, st);
      if (mounted) setState(() => _failed = true);
    }
  }

  static List<_LicenseLine> _linesOf(LicenseCatalog catalog, int index) {
    if (index >= catalog.packages.length) return const [];
    final entries = catalog.entries[catalog.packages[index]] ?? const [];
    return [
      for (final (i, entry) in entries.indexed) ...[
        if (i > 0) null,
        ...entry.paragraphs,
      ],
    ];
  }

  void _select(int index) {
    _followTimer?.cancel();
    _pendingSelection = null;
    final catalog = _catalog;
    if (catalog == null || index == _selected) return;
    setState(() {
      _selected = index;
      _lines = _linesOf(catalog, index);
    });
    if (_textScroll.hasClients) _textScroll.jumpTo(0);
  }

  void _onRowFocus(int index, bool focused) {
    if (!focused) return;
    _followTimer?.cancel();
    _pendingSelection = index;
    _followTimer = Timer(_followDelay, () {
      if (mounted) _select(index);
    });
  }

  void _openText(int index) {
    _select(index);
    _textNode.requestFocus();
  }

  void _onTextFocus(bool focused) {
    // Arrived before the text followed the focused package: catch up.
    final pending = _pendingSelection;
    if (focused && pending != null) _select(pending);
    setState(() => _textFocused = focused);
  }

  /// Puts focus back on the package whose text is shown, scrolling the
  /// list to it first when its row is not built (e.g. after the list was
  /// scrolled with a mouse wheel).
  bool _focusSelectedRow() {
    final node = _rowNode(_selected);
    if (node.context != null) {
      node.requestFocus();
      return true;
    }
    if (!_listScroll.hasClients) return false;
    final position = _listScroll.position;
    position.jumpTo(
      (_selected * _rowExtent).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      })
      ..ensureVisualUpdate();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final version = widget.applicationVersion;
    final catalog = _catalog;
    final Widget body;
    if (catalog == null) {
      body = _failed
          ? ErrorView(onRetry: () => unawaited(_load()))
          : const LoadingView();
    } else if (catalog.packages.isEmpty) {
      body = const EmptyView(icon: Icons.description_outlined);
    } else {
      body = _content(catalog);
    }
    return PopScope<void>(
      // Back in the text returns to the list first.
      canPop: !_textFocused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _focusSelectedRow();
      },
      child: Scaffold(
        body: Padding(
          padding: TvLayout.overscan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.settingsLicenses, style: theme.headlineSmall),
              const SizedBox(height: Spacing.xxs),
              BidiText(
                version == null
                    ? widget.applicationName
                    : '${widget.applicationName} · $version',
                style: theme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(LicenseCatalog catalog) {
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final packages = catalog.packages;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: ListView.builder(
            key: const ValueKey('licenses-packages'),
            controller: _listScroll,
            itemExtent: _rowExtent,
            itemCount: packages.length,
            itemBuilder: (context, i) {
              final name = packages[i];
              final count = catalog.entries[name]?.length ?? 0;
              final selected = i == _selected;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: TvFocusable(
                  key: ValueKey('license-package-$name'),
                  focusNode: _rowNode(i),
                  autofocus: i == 0,
                  focusScale: 1.02,
                  semanticLabel: name,
                  onFocusChange: (f) => _onRowFocus(i, f),
                  onSelect: () => _openText(i),
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: Spacing.lg,
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.surfaceHigh
                          : AppColors.surface,
                      borderRadius: Radii.mdAll,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BidiText(name, style: theme.titleSmall),
                        BidiText(
                          material.licensesPackageDetailText(count),
                          style: theme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: Spacing.lg),
        Expanded(
          child: LicenseTextPane(
            key: const ValueKey('licenses-text'),
            focusNode: _textNode,
            controller: _textScroll,
            title: packages[_selected],
            lines: _lines,
            onFocusChange: _onTextFocus,
            onExitStart: _focusSelectedRow,
          ),
        ),
      ],
    );
  }
}

/// The text of one package's licences as a single focus stop that the
/// arrow keys scroll (see [TvLicensePage]). Licence texts are English, so
/// they are laid out left to right in every language.
class LicenseTextPane extends StatefulWidget {
  const LicenseTextPane({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.title,
    required this.lines,
    this.onFocusChange,
    this.onExitStart,
  });

  final FocusNode focusNode;
  final ScrollController controller;
  final String title;

  /// Paragraphs; null marks the divider between two licences.
  final List<LicenseParagraph?> lines;
  final ValueChanged<bool>? onFocusChange;

  /// The arrow toward the reading start; returns whether focus moved.
  final bool Function()? onExitStart;

  /// Distance of one arrow press, about three lines.
  static const double lineStep = 72;

  @override
  State<LicenseTextPane> createState() => _LicenseTextPaneState();
}

class _LicenseTextPaneState extends State<LicenseTextPane> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final direction = arrowDirection(key);
    if (direction == TraversalDirection.left ||
        direction == TraversalDirection.right) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final towardStart = (direction == TraversalDirection.left) != rtl;
      if (!towardStart) return KeyEventResult.handled;
      return widget.onExitStart?.call() ?? false
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    final double? delta;
    if (direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      final steps = KeyRepeatThrottle.instance.stepFor(event);
      final sign = direction == TraversalDirection.up ? -1 : 1;
      delta = sign * steps * LicenseTextPane.lineStep;
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.channelDown) {
      final controller = widget.controller;
      final page = controller.hasClients
          ? controller.position.viewportDimension * 0.9
          : 0.0;
      final up =
          key == LogicalKeyboardKey.pageUp ||
          key == LogicalKeyboardKey.channelUp;
      delta = up ? -page : page;
    } else {
      delta = null;
    }
    if (delta == null) return KeyEventResult.ignored;
    _scrollBy(delta, animate: event is KeyDownEvent);
    // Up and Down always stay here: there is nothing above or below.
    return KeyEventResult.handled;
  }

  void _scrollBy(double delta, {required bool animate}) {
    final controller = widget.controller;
    if (delta == 0 || !controller.hasClients) return;
    final position = controller.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    final duration = FocusTokens.scrollOf(context);
    if (animate && duration > Duration.zero) {
      unawaited(
        position.animateTo(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      position.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = theme.bodyMedium?.copyWith(height: 1.45);
    final lines = widget.lines;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocusChange?.call(f);
      },
      child: AnimatedContainer(
        duration: FocusTokens.animationOf(context),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: Radii.mdAll,
          border: Border.all(
            color: _focused ? FocusTokens.borderColor : AppColors.outline,
            width: _focused ? FocusTokens.borderWidth : 1,
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Scrollbar(
            controller: widget.controller,
            thumbVisibility: true,
            child: ListView.builder(
              controller: widget.controller,
              padding: const EdgeInsets.all(Spacing.lg),
              itemCount: lines.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(widget.title, style: theme.titleMedium);
                }
                final line = lines[i - 1];
                if (line == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                    child: Divider(height: 1),
                  );
                }
                if (line.indent == LicenseParagraph.centeredIndent) {
                  return Padding(
                    padding: const EdgeInsets.only(top: Spacing.lg),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                      style: body?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  );
                }
                return Padding(
                  padding: EdgeInsetsDirectional.only(
                    top: Spacing.sm,
                    start: Spacing.lg * line.indent,
                  ),
                  child: Text(line.text, style: body),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
