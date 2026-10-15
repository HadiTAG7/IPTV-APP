import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/time/clock.dart';
import '../../epg/epg_models.dart';
import '../../epg/epg_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../player/ui/play_request.dart';
import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/channel_tile.dart';
import '../../widgets/states.dart';
import 'guide_data.dart';
import 'guide_format.dart';
import 'guide_widgets.dart';
import 'providers.dart';

/// The phone guide: the filter's channels with what is on now; tapping one
/// opens its day schedule ([GuideSchedulePage]).
///
/// Rows come from the database in pages; now/next of the visible rows is
/// read with one query once scrolling has settled.
class GuidePhoneList extends ConsumerStatefulWidget {
  const GuidePhoneList({
    super.key,
    required this.sourceId,
    required this.filter,
    this.favoriteKeys = const [],
    this.catalogVersion = 0,
  });

  final int sourceId;
  final GuideFilter filter;
  final List<String> favoriteKeys;
  final int catalogVersion;

  static const rowExtent = TvLayout.channelExtentPhone;

  @override
  ConsumerState<GuidePhoneList> createState() => _GuidePhoneListState();
}

class _GuidePhoneListState extends ConsumerState<GuidePhoneList> {
  final _scroll = ScrollController();
  late final GuideChannelPager _pager;
  late final Clock _clock;
  Map<String, NowNext> _nowNext = const {};
  Set<String> _nowNextKeys = const {};
  Timer? _debounce;
  Timer? _tick;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _clock = ref.read(clockProvider);
    _pager = _newPager();
    _scroll.addListener(_scheduleNowNext);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _loadNowNext());
  }

  @override
  void didUpdateWidget(GuidePhoneList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    final favorites = widget.filter.kind == GuideFilterKind.favorites;
    // Reloaded in place, so a focused grid stays mounted.
    if (favorites && !listEquals(old.favoriteKeys, widget.favoriteKeys)) {
      unawaited(_pager.reload());
    } else if (old.catalogVersion != widget.catalogVersion) {
      unawaited(_pager.reload());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tick?.cancel();
    _pager.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GuideChannelPager _newPager() {
    final pager = GuideChannelPager.forFilter(
      ref.read(databaseProvider),
      widget.sourceId,
      widget.filter,
      favoriteKeys: () => widget.favoriteKeys,
    )..addListener(_onPager);
    unawaited(pager.init());
    return pager;
  }

  void _onPager() {
    if (!mounted) return;
    setState(() {});
    _scheduleNowNext();
  }

  void _scheduleNowNext() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _loadNowNext);
  }

  List<String> _visibleKeys() {
    if (!_scroll.hasClients || !_scroll.position.hasViewportDimension) {
      return _pager.keysIn(0, 15);
    }
    final p = _scroll.position;
    final first = (p.pixels / GuidePhoneList.rowExtent).floor();
    final last =
        first + (p.viewportDimension / GuidePhoneList.rowExtent).ceil();
    _pager.ensure(first - 10, last + 10);
    return _pager.keysIn(first, last);
  }

  Future<void> _loadNowNext() async {
    final keys = _visibleKeys();
    if (keys.isEmpty) return;
    final id = ++_request;
    try {
      final data = await ref
          .read(epgDaoProvider)
          .nowNext(widget.sourceId, keys, _clock.now());
      if (!mounted || id != _request) return;
      setState(() {
        _nowNext = data;
        _nowNextKeys = keys.toSet();
      });
    } on Object {
      // Rows just show "No programme info".
    }
  }

  void _open(ChannelRow channel) {
    final request = guidePlayRequest(
      sourceId: widget.sourceId,
      channel: channel,
      filter: widget.filter,
      favoriteKeys: widget.favoriteKeys,
    );
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: GuideSchedulePage.routeName),
          builder: (_) => GuideSchedulePage(
            sourceId: widget.sourceId,
            channel: channel,
            request: request,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GuideRefreshStatus>(guideRefreshProvider(widget.sourceId), (
      previous,
      next,
    ) {
      if (next is GuideRefreshDone && previous is! GuideRefreshDone) {
        unawaited(_loadNowNext());
      }
    });
    final l10n = AppLocalizations.of(context);
    final n = _pager.length;
    if (n == null) {
      return _pager.error != null
          ? ErrorView(onRetry: () => unawaited(_pager.reload()))
          : const LoadingView();
    }
    if (n == 0) {
      return EmptyView(
        icon: Icons.live_tv_outlined,
        message: widget.filter.kind == GuideFilterKind.favorites
            ? l10n.favoritesEmpty
            : l10n.liveNoChannels,
      );
    }
    final now = _clock.now();
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemExtent: GuidePhoneList.rowExtent,
      itemCount: n,
      itemBuilder: (context, i) {
        final channel = _pager.rowAt(i);
        if (channel == null) return const SizedBox.shrink();
        final current = _nowNextKeys.contains(channel.key)
            ? _nowNext[channel.key]?.now
            : null;
        return ChannelTile(
          key: ValueKey('guide-channel-${channel.key}'),
          name: channel.name,
          number: channel.num,
          logoUrl: channel.logo,
          nowTitle: current?.title,
          progress: current == null ? null : guideProgress(current, now),
          autofocus: i == 0,
          onSelect: () => _open(channel),
        );
      },
    );
  }
}

/// One channel's programmes for today or tomorrow (local time), with the
/// programme on air highlighted (kept current while the page is open).
/// Tapping it plays the channel; tapping another programme shows its
/// details.
class GuideSchedulePage extends ConsumerStatefulWidget {
  const GuideSchedulePage({
    super.key,
    required this.sourceId,
    required this.channel,
    required this.request,
  });

  static const routeName = '/guide/schedule';
  static const rowExtent = 72.0;

  final int sourceId;
  final ChannelRow channel;

  /// What playing the channel opens (zap list of the guide's channels).
  final PlayRequest request;

  @override
  ConsumerState<GuideSchedulePage> createState() => _GuideSchedulePageState();
}

class _GuideSchedulePageState extends ConsumerState<GuideSchedulePage> {
  late final Clock _clock = ref.read(clockProvider);
  int _day = 0;
  List<EpgProgramme>? _programmes;
  Object? _error;
  int _request = 0;
  ScrollController? _scroll;

  /// Rebuilds, so "now" (highlight, minutes left) follows the clock.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(_load(first: true));
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll?.dispose();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    final id = ++_request;
    final range = localDayOf(_clock.now(), offset: _day);
    if (!first) {
      setState(() {
        _programmes = null;
        _error = null;
      });
    }
    try {
      final data = await ref
          .read(epgDaoProvider)
          .programmesForChannels(
            widget.sourceId,
            [widget.channel.key],
            range.start,
            range.end,
          );
      if (!mounted || id != _request) return;
      final list = data[widget.channel.key] ?? const <EpgProgramme>[];
      final now = _clock.now();
      final current = list.indexWhere((p) => p.isOnAt(now));
      _scroll?.dispose();
      _scroll = ScrollController(
        initialScrollOffset: current <= 1
            ? 0
            : (current - 1) * GuideSchedulePage.rowExtent,
      );
      setState(() => _programmes = list);
    } on Object catch (e) {
      if (!mounted || id != _request) return;
      setState(() => _error = e);
    }
  }

  void _play() {
    if (!mounted) return;
    unawaited(ref.read(guidePlayerProvider)(context, widget.request));
  }

  /// Plays the programme on air (at the time of the tap); shows the
  /// details of any other.
  void _select(EpgProgramme p, DateFormat format) {
    final now = _clock.now();
    if (p.isOnAt(now)) {
      _play();
      return;
    }
    unawaited(
      showGuideProgrammeInfo(
        context,
        channel: widget.channel,
        programme: p,
        now: now,
        timeFormat: format,
        onWatch: _play,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = guideTimeFormat(context);
    final now = _clock.now();
    final programmes = _programmes;
    final Widget body;
    if (_error != null) {
      body = ErrorView(onRetry: () => unawaited(_load()));
    } else if (programmes == null) {
      body = const LoadingView();
    } else if (programmes.isEmpty) {
      body = EmptyView(
        icon: Icons.view_timeline_outlined,
        message: l10n.liveNoProgrammeInfo,
        action: FilledButton.icon(
          key: const ValueKey('guide-schedule-watch'),
          autofocus: true,
          onPressed: _play,
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.guideWatchChannel),
        ),
      );
    } else {
      final current = programmes.indexWhere((p) => p.isOnAt(now));
      body = ListView.builder(
        controller: _scroll,
        itemExtent: GuideSchedulePage.rowExtent,
        itemCount: programmes.length,
        itemBuilder: (context, i) => _ScheduleRow(
          key: ValueKey('guide-schedule-$i'),
          programme: programmes[i],
          now: now,
          format: format,
          autofocus: current < 0 ? i == 0 : i == current,
          onSelect: () => _select(programmes[i], format),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: BidiText(widget.channel.name),
        actions: [
          IconButton(
            key: const ValueKey('guide-schedule-play'),
            tooltip: l10n.guideWatchChannel,
            onPressed: _play,
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: SegmentedButton<int>(
                key: const ValueKey('guide-day-picker'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, label: Text(l10n.guideToday)),
                  ButtonSegment(value: 1, label: Text(l10n.guideTomorrow)),
                ],
                selected: {_day},
                onSelectionChanged: (s) {
                  if (s.first == _day) return;
                  _day = s.first;
                  unawaited(_load());
                },
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    super.key,
    required this.programme,
    required this.now,
    required this.format,
    required this.autofocus,
    required this.onSelect,
  });

  final EpgProgramme programme;
  final DateTime now;
  final DateFormat format;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final onAir = programme.isOnAt(now);
    final past = !programme.stop.isAfter(now);
    final subtitle = programme.subTitle ?? programme.desc;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xxs,
      ),
      child: TvFocusable(
        autofocus: autofocus,
        focusScale: 1.02,
        semanticLabel: programme.title,
        onSelect: onSelect,
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: onAir ? AppColors.surfaceHigh : null,
            borderRadius: Radii.mdAll,
            border: onAir
                ? const BorderDirectional(
                    start: BorderSide(color: AppColors.accent, width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  format.format(programme.start.toLocal()),
                  maxLines: 1,
                  style: theme.labelLarge?.copyWith(
                    color: past ? AppColors.textDisabled : null,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BidiText(
                      programme.title,
                      style: theme.titleMedium?.copyWith(
                        color: past ? AppColors.textSecondary : null,
                      ),
                    ),
                    if (onAir) ...[
                      Text(
                        '${l10n.guideNow} · '
                        '${l10n.guideMinutesLeft(programme.stop.difference(now).inMinutes)}',
                        maxLines: 1,
                        style: theme.labelMedium?.copyWith(
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      ProgressLine(value: guideProgress(programme, now)),
                    ] else if (subtitle != null && subtitle.isNotEmpty)
                      BidiText(subtitle, style: theme.bodySmall),
                  ],
                ),
              ),
              if (onAir)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: Spacing.sm),
                  child: Icon(Icons.play_circle_outline, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
