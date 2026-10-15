import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/db/queries/settings_help_queries.dart';
import '../../core/net/redact.dart';
import '../../epg/epg_progress.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../player/engine/player_engine.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/tv_focusable.dart';
import 'providers.dart';
import 'settings_dialogs.dart';
import 'settings_format.dart';
import 'settings_widgets.dart';

/// App settings: sources, language, device and Lite mode, player engines and
/// languages, the active source's guide (URLs, offset, refresh), and links to
/// Diagnostics, Help and About.
///
/// Renders body content only. As a TV tab (inside the home shell) it shows
/// its own title and leaves the first focus to the shell; pushed as a page
/// it autofocuses its first row. Every value is picked in a dialog that
/// opens on the current value, and changes are saved at once
/// ([SettingsController], or the database for per-source guide settings).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _firstNode = FocusNode(debugLabel: 'settings:first');
  final _addEpgNode = FocusNode(debugLabel: 'settings:addEpg');
  FocusWatchdogState? _watchdog;
  bool _refreshing = false;

  /// Whether this page is a home-shell tab (not a pushed page).
  bool get _inTab => HomeBackScope.maybeOf(context) != null;

  SettingsController get _settings => ref.read(settingsProvider.notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pushed page autofocuses its first row; make that row the watchdog's
    // fallback so a racing restore lands there too. Tabs leave the first
    // focus to the shell (autofocus would pull focus off the rail).
    final watchdog = _inTab ? null : FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_firstNode);
      _watchdog = watchdog?..register(_firstNode);
    }
  }

  @override
  void dispose() {
    _watchdog?.unregister(_firstNode);
    _firstNode.dispose();
    _addEpgNode.dispose();
    super.dispose();
  }

  void _open(HomeTab tab) => unawaited(pushHomePage(context, ref, tab));

  Future<void> _pick<T extends Object>(
    String title,
    List<Choice<T>> choices,
    T current,
    Future<void> Function(T value) apply,
  ) async {
    final picked = await showChoiceDialog<T>(
      context,
      title: title,
      choices: choices,
      current: current,
    );
    if (picked == null || picked == current || !mounted) return;
    await apply(picked);
  }

  /// Runs a database write; on failure logs it and tells the user.
  Future<bool> _write(Future<void> Function() action) async {
    final log = ref.read(ringLogProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = AppLocalizations.of(context).settings_saveFailed;
    try {
      await action();
      return true;
    } on Object catch (e, st) {
      log.error('Saving a setting failed', e, st);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
  }

  /// A guide refresh (see [RefreshGuideAction]) that logs failures. Read it
  /// before awaiting anything: it keeps working after this page is gone.
  Future<void> Function(int sourceId, {required bool force}) get _refresher {
    final action = ref.read(refreshGuideActionProvider);
    final log = ref.read(ringLogProvider);
    return (sourceId, {required force}) async {
      try {
        await action(sourceId, force: force);
      } on Object catch (e, st) {
        log.error('Guide refresh failed', e, st);
      }
    };
  }

  Future<void> _refreshNow(int sourceId) async {
    if (_refreshing) return;
    final refresh = _refresher;
    setState(() => _refreshing = true);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).guideUpdating)),
      );
    await refresh(sourceId, force: true);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _toggleEpg(int sourceId, EpgSourceRow row) async {
    final enable = !row.enabled;
    final dao = ref.read(epgDaoProvider);
    final refresh = _refresher;
    final ok = await _write(() => dao.setEpgSourceEnabled(row.id, enable));
    // A guide switched on may never have been downloaded.
    if (ok && enable) unawaited(refresh(sourceId, force: false));
  }

  Future<void> _addEpgUrl(int sourceId) async {
    final refresh = _refresher;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AddEpgUrlDialog(onAdd: (url) => _storeEpgUrl(sourceId, url)),
    );
    if (added ?? false) unawaited(refresh(sourceId, force: false));
  }

  /// Saves a typed guide URL; returns an error message or null.
  Future<String?> _storeEpgUrl(int sourceId, String url) async {
    final l10n = AppLocalizations.of(context);
    final db = ref.read(databaseProvider);
    final log = ref.read(ringLogProvider);
    try {
      final masked = redact(url);
      final existing = await db.epgDao.epgSources(sourceId);
      if (existing.any((r) => r.url == masked)) {
        return l10n.settings_epgUrlExists;
      }
      await db.addManualEpgSource(sourceId, url);
      return null;
    } on Object catch (e, st) {
      log.error('Adding a guide URL failed', e, st);
      return l10n.settings_saveFailed;
    }
  }

  Future<void> _deleteEpg(EpgSourceRow row) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settings_deleteEpgUrl,
      message: l10n.settings_deleteEpgUrlBody,
      details: redact(row.url),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed || !mounted) return;
    final dao = ref.read(epgDaoProvider);
    final ok = await _write(() => dao.deleteEpgSource(row.id));
    // The row and its delete button go away: keep focus in the guide list
    // instead of letting it fall back to the top of the page.
    if (ok && mounted) _addEpgNode.requestFocus();
  }

  Future<void> _editOffset(SourceRow source) async {
    final refresh = _refresher;
    final db = ref.read(databaseProvider);
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => EpgOffsetDialog(initial: source.epgOffsetMin),
    );
    if (picked == null || picked == source.epgOffsetMin || !mounted) return;
    final ok = await _write(() => db.setSourceEpgOffset(source.id, picked));
    // Offsets are applied at import, so every guide is downloaded again.
    if (ok) unawaited(refresh(source.id, force: true));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final large = isLargeLayout(context);
    final inTab = _inTab;
    final s = ref.watch(settingsProvider);
    final detectedLite = ref.watch(deviceCapsProvider).lite;
    final android = ref.watch(targetPlatformProvider) == TargetPlatform.android;
    final source = ref.watch(activeSourceProvider);
    final version = ref.watch(appVersionProvider).value;
    final engines = [
      EngineSetting.auto,
      if (android) EngineSetting.exo,
      EngineSetting.mpv,
    ];

    final rows = <Widget>[
      if (large && inTab)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: Spacing.xs),
          child: Text(
            l10n.navSettings,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      SettingsSection(l10n.settingsGeneral, large: large),
      SettingsTile(
        key: const ValueKey('settings-sources'),
        large: large,
        focusNode: _firstNode,
        autofocus: !inTab,
        icon: Icons.playlist_play,
        title: l10n.navSources,
        value: source?.name,
        onSelect: () => _open(HomeTab.sources),
      ),
      SettingsTile(
        key: const ValueKey('settings-language'),
        large: large,
        icon: Icons.language,
        title: l10n.settingsLanguage,
        value: _localeLabel(l10n, s.locale),
        onSelect: () => _pick(
          l10n.settingsLanguage,
          [
            for (final v in AppLocaleSetting.values)
              (value: v, label: _localeLabel(l10n, v)),
          ],
          s.locale,
          _settings.setLocale,
        ),
      ),
      SettingsTile(
        key: const ValueKey('settings-deviceMode'),
        large: large,
        icon: Icons.devices_other,
        title: l10n.settingsDeviceMode,
        value: _deviceModeLabel(l10n, s.formFactor),
        onSelect: () => _pick(
          l10n.settingsDeviceMode,
          [
            for (final v in FormFactorOverride.values)
              (value: v, label: _deviceModeLabel(l10n, v)),
          ],
          s.formFactor,
          _settings.setFormFactor,
        ),
      ),
      SettingsTile(
        key: const ValueKey('settings-lite'),
        large: large,
        icon: Icons.speed,
        title: l10n.settingsLiteMode,
        subtitle: l10n.settingsLiteModeHint,
        value: _liteLabel(l10n, s.lite, detectedLite),
        onSelect: () => _pick(
          l10n.settingsLiteMode,
          [
            for (final v in LiteSetting.values)
              (value: v, label: _liteLabel(l10n, v, detectedLite)),
          ],
          s.lite,
          _settings.setLite,
        ),
      ),
      SettingsSection(l10n.settingsPlayer, large: large),
      SettingsTile(
        key: const ValueKey('settings-liveEngine'),
        large: large,
        icon: Icons.live_tv_outlined,
        title: l10n.settingsLiveEngine,
        value: _engineLabel(l10n, s.liveEngine),
        onSelect: () => _pick(
          l10n.settingsLiveEngine,
          [for (final v in engines) (value: v, label: _engineLabel(l10n, v))],
          s.liveEngine,
          _settings.setLiveEngine,
        ),
      ),
      SettingsTile(
        key: const ValueKey('settings-vodEngine'),
        large: large,
        icon: Icons.movie_outlined,
        title: l10n.settingsVodEngine,
        value: _engineLabel(l10n, s.vodEngine),
        onSelect: () => _pick(
          l10n.settingsVodEngine,
          [for (final v in engines) (value: v, label: _engineLabel(l10n, v))],
          s.vodEngine,
          _settings.setVodEngine,
        ),
      ),
      if (android)
        SettingsTile(
          key: const ValueKey('settings-exoView'),
          large: large,
          icon: Icons.layers_outlined,
          title: l10n.settingsExoViewType,
          value: _exoViewLabel(l10n, s.exoView),
          onSelect: () => _pick(
            l10n.settingsExoViewType,
            [
              for (final v in ExoViewType.values)
                (value: v, label: _exoViewLabel(l10n, v)),
            ],
            s.exoView,
            _settings.setExoView,
          ),
        ),
      SettingsTile(
        key: const ValueKey('settings-hwdec'),
        large: large,
        icon: Icons.memory,
        title: l10n.settingsHardwareDecoding,
        value: s.hwdec ? l10n.commonOn : l10n.commonOff,
        trailing: _switch(large, s.hwdec, (v) => _settings.setHwdec(v)),
        onSelect: () => _settings.setHwdec(!s.hwdec),
      ),
      SettingsTile(
        key: const ValueKey('settings-audioLang'),
        large: large,
        icon: Icons.audiotrack_outlined,
        title: l10n.settingsPreferredAudioLanguage,
        value: _languageName(l10n, s.preferredAudioLang),
        onSelect: () => _pick(
          l10n.settingsPreferredAudioLanguage,
          [
            for (final code in languageChoicesWith(s.preferredAudioLang))
              (value: code, label: _languageName(l10n, code)),
          ],
          s.preferredAudioLang,
          _settings.setPreferredAudioLang,
        ),
      ),
      SettingsTile(
        key: const ValueKey('settings-subLang'),
        large: large,
        icon: Icons.subtitles_outlined,
        title: l10n.settings_preferredSubtitleLanguage,
        value: _languageName(l10n, s.preferredSubLang),
        onSelect: () => _pick(
          l10n.settings_preferredSubtitleLanguage,
          [
            for (final code in languageChoicesWith(s.preferredSubLang))
              (value: code, label: _languageName(l10n, code)),
          ],
          s.preferredSubLang,
          _settings.setPreferredSubLang,
        ),
      ),
      SettingsTile(
        key: const ValueKey('settings-aspect'),
        large: large,
        icon: Icons.aspect_ratio,
        title: l10n.settings_defaultAspect,
        value: _aspectLabel(l10n, s.defaultAspect),
        onSelect: () => _pick(
          l10n.settings_defaultAspect,
          [
            for (final v in AspectMode.values)
              (value: v, label: _aspectLabel(l10n, v)),
          ],
          s.defaultAspect,
          _settings.setDefaultAspect,
        ),
      ),
      if (source != null) ..._guideRows(l10n, large, source, s),
      SettingsSection(l10n.settingsAbout, large: large),
      SettingsTile(
        key: const ValueKey('settings-diagnostics'),
        large: large,
        icon: Icons.monitor_heart_outlined,
        title: l10n.settingsDiagnostics,
        onSelect: () => _open(HomeTab.diagnostics),
      ),
      SettingsTile(
        key: const ValueKey('settings-help'),
        large: large,
        icon: Icons.help_outline,
        title: l10n.settingsHelpLegal,
        onSelect: () => _open(HomeTab.help),
      ),
      SettingsTile(
        key: const ValueKey('settings-about'),
        large: large,
        icon: Icons.info_outline,
        title: l10n.appTitle,
        value: version == null ? null : l10n.settingsVersion(version),
      ),
      SettingsTile(
        key: const ValueKey('settings-licenses'),
        large: large,
        icon: Icons.description_outlined,
        title: l10n.settingsLicenses,
        onSelect: () => showLicensePage(
          context: context,
          applicationName: l10n.appTitle,
          applicationVersion: version,
        ),
      ),
    ];

    if (!large) {
      return ListView(
        padding: const EdgeInsets.only(bottom: Spacing.xl),
        children: rows,
      );
    }
    // Pushed on a TV, the page has no shell margins: keep clear of overscan.
    final pushedOnTv = !inTab && FormFactorScope.isTv(context);
    return SingleChildScrollView(
      padding: pushedOnTv
          ? const EdgeInsets.fromLTRB(
              TvLayout.overscanHorizontal,
              Spacing.sm,
              TvLayout.overscanHorizontal,
              TvLayout.overscanVertical,
            )
          : const EdgeInsets.all(Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Spacing.xs,
        children: rows,
      ),
    );
  }

  List<Widget> _guideRows(
    AppLocalizations l10n,
    bool large,
    SourceRow source,
    AppSettings s,
  ) {
    final epg = ref.watch(epgSourcesProvider(source.id));
    final guides = epg.value;
    final lastEpgAt = source.lastEpgAt;
    final offset = source.epgOffsetMin;
    return [
      SettingsSection(
        l10n.settingsGuide,
        large: large,
        subtitle: l10n.settings_guideFor(source.name),
      ),
      if (guides == null)
        epg.hasError
            ? _Note(
                key: const ValueKey('settings-epg-error'),
                large: large,
                icon: Icons.error_outline,
                text: l10n.commonErrorGeneric,
              )
            : const LinearProgressIndicator(minHeight: 2)
      else if (guides.isEmpty)
        _Note(
          key: const ValueKey('settings-epg-empty'),
          large: large,
          icon: Icons.info_outline,
          text: l10n.settings_epgNoUrls,
        )
      else
        for (final row in guides)
          _EpgSourceTile(
            key: ValueKey('epg-${row.id}'),
            row: row,
            large: large,
            onToggle: () => _toggleEpg(source.id, row),
            onDelete: row.origin == EpgOrigin.manual
                ? () => _deleteEpg(row)
                : null,
          ),
      SettingsTile(
        key: const ValueKey('settings-epgAdd'),
        large: large,
        focusNode: _addEpgNode,
        icon: Icons.add_link,
        title: l10n.settings_addEpgUrl,
        onSelect: () => _addEpgUrl(source.id),
      ),
      SettingsTile(
        key: const ValueKey('settings-epgOffset'),
        large: large,
        icon: Icons.schedule,
        title: l10n.settingsEpgOffset,
        value: offset == 0
            ? l10n.settings_epgOffsetNone
            : formatEpgOffset(offset),
        valueDirection: offset == 0 ? null : TextDirection.ltr,
        onSelect: () => _editOffset(source),
      ),
      SettingsTile(
        key: const ValueKey('settings-epgRefresh'),
        large: large,
        icon: Icons.refresh,
        title: l10n.guideRefresh,
        subtitle: lastEpgAt == null
            ? l10n.settings_epgRefreshNow
            : l10n.guideUpdated(lastEpgAt.toLocal()),
        trailing: _refreshing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onSelect: _refreshing ? null : () => _refreshNow(source.id),
      ),
      SettingsTile(
        key: const ValueKey('settings-epgInterval'),
        large: large,
        icon: Icons.update,
        title: l10n.settings_epgRefreshInterval,
        value: l10n.settings_everyHours(s.epgRefreshHours),
        onSelect: () => _pick(
          l10n.settings_epgRefreshInterval,
          [
            for (final h in epgRefreshChoicesWith(s.epgRefreshHours))
              (value: h, label: l10n.settings_everyHours(h)),
          ],
          s.epgRefreshHours,
          _settings.setEpgRefreshHours,
        ),
      ),
    ];
  }
}

/// A switch that shows a boolean row's state. On the large layout OK on the
/// row toggles it, so the switch itself takes no focus.
Widget _switch(bool large, bool value, ValueChanged<bool> onChanged) {
  final control = Switch(value: value, onChanged: onChanged);
  return large ? ExcludeFocus(child: control) : control;
}

/// One guide URL: origin, status, programme count and last import, an
/// on/off switch (OK toggles) and, for URLs the user added, a delete button
/// on the end side.
class _EpgSourceTile extends StatelessWidget {
  const _EpgSourceTile({
    super.key,
    required this.row,
    required this.large,
    required this.onToggle,
    this.onDelete,
  });

  final EpgSourceRow row;
  final bool large;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = EpgSourceStatus.parse(row.status);
    final lastFetch = row.lastFetchAt;
    final subtitle = [
      _originLabel(l10n, row.origin),
      row.enabled ? _statusLabel(l10n, status) : l10n.commonOff,
      l10n.settings_programmeCount(row.programmeCount),
      if (lastFetch != null) l10n.settings_epgLastImport(lastFetch.toLocal()),
    ].join(' · ');
    final error = row.enabled && status?.kind == EpgStatusKind.error
        ? status?.message
        : null;
    final onDelete = this.onDelete;
    final delete = onDelete == null
        ? null
        : large
        ? TvFocusable(
            key: ValueKey('settings-epg-${row.id}-delete'),
            focusScale: 1.04,
            semanticLabel: l10n.settings_deleteEpgUrl,
            onSelect: onDelete,
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: Radii.mdAll,
              ),
              child: const Icon(Icons.delete_outline, size: 22),
            ),
          )
        : IconButton(
            key: ValueKey('settings-epg-${row.id}-delete'),
            tooltip: l10n.settings_deleteEpgUrl,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          );
    final toggle = _switch(large, row.enabled, (_) => onToggle());
    final tile = SettingsTile(
      key: ValueKey('settings-epg-${row.id}'),
      large: large,
      icon: _originIcon(row.origin),
      title: redact(row.url),
      titleDirection: TextDirection.ltr,
      subtitle: subtitle,
      detail: error == null || error.isEmpty ? null : redact(error),
      detailColor: AppColors.error,
      trailing: !large && delete != null
          ? Row(mainAxisSize: MainAxisSize.min, children: [toggle, delete])
          : toggle,
      onSelect: onToggle,
    );
    if (!large || delete == null) return tile;
    return Row(
      children: [
        Expanded(child: tile),
        const SizedBox(width: Spacing.sm),
        delete,
      ],
    );
  }
}

/// A short inline message inside the list (empty or failed guide list).
class _Note extends StatelessWidget {
  const _Note({
    super.key,
    required this.large,
    required this.icon,
    required this.text,
  });

  final bool large;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: large ? Spacing.lg : Spacing.xl,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

String _localeLabel(AppLocalizations l10n, AppLocaleSetting v) => switch (v) {
  AppLocaleSetting.auto => l10n.languageAuto,
  AppLocaleSetting.ar => l10n.languageArabic,
  AppLocaleSetting.en => l10n.languageEnglish,
};

String _deviceModeLabel(AppLocalizations l10n, FormFactorOverride v) =>
    switch (v) {
      FormFactorOverride.auto => l10n.deviceModeAuto,
      FormFactorOverride.tv => l10n.deviceModeTv,
      FormFactorOverride.phone => l10n.deviceModePhone,
    };

String _liteLabel(AppLocalizations l10n, LiteSetting v, bool detected) =>
    switch (v) {
      LiteSetting.auto => l10n.settings_liteAuto(
        detected ? l10n.commonOn : l10n.commonOff,
      ),
      LiteSetting.on => l10n.commonOn,
      LiteSetting.off => l10n.commonOff,
    };

String _engineLabel(AppLocalizations l10n, EngineSetting v) => switch (v) {
  EngineSetting.auto => l10n.engineAuto,
  EngineSetting.exo => l10n.engineExo,
  EngineSetting.mpv => l10n.engineMpv,
};

String _exoViewLabel(AppLocalizations l10n, ExoViewType v) => switch (v) {
  ExoViewType.texture => l10n.viewTypeTexture,
  ExoViewType.platform => l10n.viewTypePlatform,
};

String _aspectLabel(AppLocalizations l10n, AspectMode v) => switch (v) {
  AspectMode.fit => l10n.aspectFit,
  AspectMode.fill => l10n.aspectFill,
  AspectMode.stretch => l10n.aspectStretch,
  AspectMode.ratio16x9 => l10n.aspect16x9,
  AspectMode.ratio4x3 => l10n.aspect4x3,
};

String _languageName(AppLocalizations l10n, String code) => switch (code) {
  'ar' => l10n.settings_langArabic,
  'en' => l10n.settings_langEnglish,
  'fr' => l10n.settings_langFrench,
  'tr' => l10n.settings_langTurkish,
  _ => code.toUpperCase(),
};

String _originLabel(AppLocalizations l10n, EpgOrigin v) => switch (v) {
  EpgOrigin.xtream => l10n.settings_epgOriginXtream,
  EpgOrigin.m3uHeader => l10n.settings_epgOriginPlaylist,
  EpgOrigin.manual => l10n.settings_epgOriginManual,
};

IconData _originIcon(EpgOrigin v) => switch (v) {
  EpgOrigin.xtream => Icons.cloud_outlined,
  EpgOrigin.m3uHeader => Icons.playlist_play,
  EpgOrigin.manual => Icons.link,
};

String _statusLabel(AppLocalizations l10n, EpgSourceStatus? status) =>
    switch (status?.kind) {
      null => l10n.settings_epgStatusNever,
      EpgStatusKind.ok => l10n.settings_epgStatusOk,
      EpgStatusKind.notModified => l10n.settings_epgStatusNotModified,
      EpgStatusKind.error => l10n.settings_epgStatusFailed,
      EpgStatusKind.cancelled => l10n.settings_epgStatusCancelled,
    };
