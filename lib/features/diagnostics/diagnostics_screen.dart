import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../app/form_factor.dart';
import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/platform/device_caps.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../player/engine/engine_factory.dart';
import '../../player/engine/engine_policy.dart';
import '../../player/engine/player_engine.dart';
import '../../player/player_providers.dart';
import '../../player/ui/player_format.dart';
import '../../sources/models.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/key_repeat.dart';
import '../../tv/tv_focusable.dart';
import '../../widgets/bidi_text.dart';
import 'diagnostics_report.dart';
import 'engine_ab_test.dart';
import 'providers.dart';

/// Device report, engine tests and the recent log.
///
/// * Device capabilities (TV signals, ABIs, decoders, RAM, SoC), the app
///   version, a Settings summary and the saved sources (no URLs or names).
/// * Engine A/B test: the public Apple and Mux HLS test streams on ExoPlayer
///   and mpv (Android) or mpv (desktop), with the time to the first frame;
///   the ExoPlayer view type (texture / platform view) can be switched.
/// * The last 200 log lines, "Copy report" (redacted) and "Show QR" (a short
///   summary).
///
/// Body content only: the shells (and pushed routes) provide the chrome.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  /// Log lines shown and copied.
  static const logLines = 200;

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  late final EngineAbTest _test;
  final _runNode = FocusNode(debugLabel: 'diagnostics:run');
  final _scroll = ScrollController();
  FocusWatchdogState? _watchdog;

  @override
  void initState() {
    super.initState();
    final android =
        targetPlatformKindOf(ref.read(targetPlatformProvider)) ==
        TargetPlatformKind.android;
    _test = EngineAbTest(
      buildFactory: ref.read(engineFactoryBuilderProvider),
      engines: android
          ? const [EngineKind.exo, EngineKind.mpv]
          : const [EngineKind.mpv],
      streams: ref.read(diagnosticsTestStreamsProvider),
      options: (view) {
        final base = ref.read(engineOptionsProvider);
        return EngineOptions(
          lite: base.lite,
          hardwareDecoding: base.hardwareDecoding,
          exoViewType: view,
          preferredLanguages: base.preferredLanguages,
          subtitleLanguages: base.subtitleLanguages,
        );
      },
      clock: ref.read(clockProvider),
      timeout: ref.read(diagnosticsTestTimeoutProvider),
      log: ref.read(ringLogProvider),
      exoViewType: ref.read(settingsProvider).exoView.viewType,
    )..addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The watchdog may restore focus before autofocus applies.
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_runNode);
      _watchdog = watchdog?..register(_runNode);
    }
  }

  @override
  void dispose() {
    _watchdog?.unregister(_runNode);
    _test
      ..removeListener(_rebuild)
      ..dispose();
    _runNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  DiagnosticsSnapshot _snapshot() => DiagnosticsSnapshot(
    caps: ref.read(deviceCapsProvider),
    appVersion: ref.read(appVersionProvider).value,
    formFactor: FormFactorScope.of(context),
    lite: ref.read(liteModeProvider),
    settings: ref.read(settingsProvider),
    sources: ref.read(sourcesProvider).value ?? const [],
    results: _test.results,
    streams: _test.streams,
    logLines: ref.read(ringLogProvider).lines,
    generatedAt: ref.read(clockProvider).now(),
  );

  void _runOrCancel() {
    if (_test.running) {
      _test.cancel();
    } else {
      unawaited(_test.run());
    }
  }

  Future<void> _copyReport() async {
    final report = buildDiagnosticsReport(
      _snapshot(),
      logLines: DiagnosticsScreen.logLines,
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).commonCopied)),
      );
  }

  Future<void> _showQr() async {
    final summary = buildDiagnosticsSummary(_snapshot());
    await showDialog<void>(
      context: context,
      builder: (context) => DiagnosticsQrDialog(data: summary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final caps = ref.watch(deviceCapsProvider);
    final settings = ref.watch(settingsProvider);
    final lite = ref.watch(liteModeProvider);
    final version = ref.watch(appVersionProvider);
    final sources = ref.watch(sourcesProvider).value ?? const [];
    final log = ref.watch(ringLogProvider);
    final formFactor = FormFactorScope.of(context);
    // A pushed page (not a shell tab) has no overscan margins of its own.
    final pushed = HomeBackScope.maybeOf(context) == null;
    final overscan = pushed && formFactor == FormFactor.tv
        ? const EdgeInsetsDirectional.fromSTEB(
            TvLayout.overscanHorizontal,
            0,
            TvLayout.overscanHorizontal,
            TvLayout.overscanVertical,
          )
        : EdgeInsetsDirectional.zero;
    final lines = log.lines;
    final shown = lines.length > DiagnosticsScreen.logLines
        ? lines.sublist(lines.length - DiagnosticsScreen.logLines)
        : lines;
    String yesNo(bool v) => v ? l10n.commonYes : l10n.commonNo;

    return SingleChildScrollView(
      key: const ValueKey('diagnostics'),
      controller: _scroll,
      padding: overscan.add(const EdgeInsets.all(Spacing.lg)),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  _DiagButton(
                    key: const ValueKey('diagnostics-run'),
                    focusNode: _runNode,
                    autofocus: true,
                    icon: _test.running ? Icons.stop : Icons.play_arrow,
                    label: _test.running
                        ? l10n.commonCancel
                        : _test.results.any(
                            (r) => r.status != EngineTestStatus.pending,
                          )
                        ? l10n.diagnostics_runAgain
                        : l10n.diagRunTest,
                    onSelect: _runOrCancel,
                  ),
                  if (_test.engines.contains(EngineKind.exo))
                    _DiagButton(
                      key: const ValueKey('diagnostics-exo-view'),
                      icon: Icons.layers_outlined,
                      enabled: !_test.running,
                      label:
                          '${l10n.settingsExoViewType}: '
                          '${_test.exoViewType == VideoViewType.platformView ? l10n.viewTypePlatform : l10n.viewTypeTexture}',
                      onSelect: () => _test.exoViewType =
                          _test.exoViewType == VideoViewType.platformView
                          ? VideoViewType.textureView
                          : VideoViewType.platformView,
                    ),
                  _DiagButton(
                    key: const ValueKey('diagnostics-copy'),
                    icon: Icons.copy_all_outlined,
                    label: l10n.diagCopyReport,
                    onSelect: () => unawaited(_copyReport()),
                  ),
                  _DiagButton(
                    key: const ValueKey('diagnostics-qr'),
                    icon: Icons.qr_code_2,
                    label: l10n.diagShowQr,
                    onSelect: () => unawaited(_showQr()),
                  ),
                ],
              ),
              _Section(
                key: const ValueKey('diagnostics-engine'),
                title: l10n.diagEngineTest,
                children: [
                  Text(
                    l10n.diagnostics_testStreamsNote,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: Spacing.sm),
                  _resultsWithPreview(l10n),
                ],
              ),
              _Section(
                key: const ValueKey('diagnostics-device'),
                title: l10n.diagDevice,
                children: [
                  _InfoRow(
                    label: l10n.diagnostics_platform,
                    value:
                        '${caps.platform.name}'
                        '${caps.sdkInt > 0 ? ' · SDK ${caps.sdkInt}' : ''}',
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_model,
                    value: _orUnknown(
                      l10n,
                      '${caps.manufacturer} ${caps.model}'.trim(),
                    ),
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_chipset,
                    value: _orUnknown(l10n, chipsetParts(caps).join(' · ')),
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_cpuCores,
                    value: caps.cpuCount > 0
                        ? '${caps.cpuCount}'
                        : l10n.diagnostics_unknown,
                  ),
                  _InfoRow(
                    label: l10n.diagMemory,
                    value: caps.totalRamMb > 0
                        ? l10n.diagRamMb(caps.totalRamMb)
                        : l10n.diagnostics_unknown,
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_lowRam,
                    value: yesNo(caps.isLowRamDevice),
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_detectedTv,
                    value: yesNo(caps.isTv),
                  ),
                  _InfoRow(
                    label: l10n.diagTvSignals,
                    value:
                        'uiModeTv ${_flag(caps.uiModeTv)} · '
                        'leanback ${_flag(caps.leanback)} · '
                        'fireTv ${_flag(caps.fireTv)}',
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_touch,
                    value: yesNo(caps.touch),
                  ),
                  _InfoRow(
                    label: l10n.diagAbis,
                    value: _orUnknown(l10n, caps.supportedAbis.join(', ')),
                  ),
                  for (final key in DeviceCaps.decoderKeys)
                    _InfoRow(
                      label: '${l10n.diagDecoders} · $key',
                      value: caps.hasDecoder(key)
                          ? l10n.diagSupported
                          : l10n.diagNotSupported,
                    ),
                ],
              ),
              _Section(
                key: const ValueKey('diagnostics-app'),
                title: l10n.diagnostics_app,
                children: [
                  _InfoRow(
                    label: l10n.settingsAbout,
                    value: switch (version.value) {
                      final v? => l10n.settingsVersion(v),
                      null => l10n.diagnostics_unknown,
                    },
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_layout,
                    value: switch (formFactor) {
                      FormFactor.tv => l10n.deviceModeTv,
                      FormFactor.phone => l10n.deviceModePhone,
                      FormFactor.desktop => l10n.diagnostics_desktop,
                    },
                  ),
                  _InfoRow(
                    label: l10n.settingsLiteMode,
                    value: _onOff(l10n, lite),
                  ),
                ],
              ),
              _Section(
                key: const ValueKey('diagnostics-settings'),
                title: l10n.navSettings,
                children: [
                  _InfoRow(
                    label: l10n.settingsLiveEngine,
                    value: _engineSetting(l10n, settings.liveEngine),
                  ),
                  _InfoRow(
                    label: l10n.settingsVodEngine,
                    value: _engineSetting(l10n, settings.vodEngine),
                  ),
                  _InfoRow(
                    label: l10n.settingsExoViewType,
                    value: settings.exoView == ExoViewType.platform
                        ? l10n.viewTypePlatform
                        : l10n.viewTypeTexture,
                  ),
                  _InfoRow(
                    label: l10n.settingsHardwareDecoding,
                    value: _onOff(l10n, settings.hwdec),
                  ),
                  _InfoRow(
                    label: l10n.settingsPreferredAudioLanguage,
                    value: settings.preferredAudioLang,
                  ),
                  _InfoRow(
                    label: l10n.diagnostics_subtitleLanguage,
                    value: settings.preferredSubLang,
                  ),
                  _InfoRow(
                    label: l10n.playerAspectRatio,
                    value: aspectLabel(l10n, settings.defaultAspect),
                  ),
                  _InfoRow(
                    label: l10n.settingsDeviceMode,
                    value: switch (settings.formFactor) {
                      FormFactorOverride.auto => l10n.deviceModeAuto,
                      FormFactorOverride.tv => l10n.deviceModeTv,
                      FormFactorOverride.phone => l10n.deviceModePhone,
                    },
                  ),
                ],
              ),
              _Section(
                key: const ValueKey('diagnostics-sources'),
                title: l10n.navSources,
                children: [
                  if (sources.isEmpty)
                    Text(l10n.settingsNoSources)
                  else
                    for (final s in sources)
                      _InfoRow(
                        label: switch (s.kind) {
                          SourceKind.m3uUrl => l10n.sourceTypeM3uUrl,
                          SourceKind.m3uFile => l10n.sourceTypeM3uFile,
                          SourceKind.xtream => l10n.sourceTypeXtream,
                        },
                        value:
                            '${l10n.diagnostics_maxConnections}: '
                            '${s.maxConnections ?? '-'}',
                      ),
                ],
              ),
              _Section(
                key: const ValueKey('diagnostics-log'),
                title: l10n.diagLog,
                focusable: false,
                // No URL paths on screen either (see [hideUrlPaths]).
                children: [
                  _LogView(lines: [for (final l in shown) hideUrlPaths(l)]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Results beside the preview on large layouts, above it on phones.
  Widget _resultsWithPreview(AppLocalizations l10n) {
    final results = Column(
      children: [
        for (final r in _test.results)
          _InfoRow(
            key: ValueKey('diagnostics-result-${r.engine.name}-${r.stream}'),
            label:
                '${engineLabel(l10n, r.engine)} · '
                '${l10n.diagnostics_testStream(r.stream + 1)}',
            value: _resultText(l10n, r),
          ),
      ],
    );
    final preview = _Preview(engine: _test.activeEngine);
    if (!isLargeLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          results,
          const SizedBox(height: Spacing.sm),
          preview,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: results),
        const SizedBox(width: Spacing.md),
        preview,
      ],
    );
  }

  static String _flag(bool v) => v ? 'on' : 'off';

  static String _onOff(AppLocalizations l10n, bool v) =>
      v ? l10n.commonOn : l10n.commonOff;

  static String _orUnknown(AppLocalizations l10n, String v) =>
      v.trim().isEmpty ? l10n.diagnostics_unknown : v;

  static String _engineSetting(AppLocalizations l10n, EngineSetting s) =>
      switch (s) {
        EngineSetting.auto => l10n.engineAuto,
        EngineSetting.exo => l10n.engineExo,
        EngineSetting.mpv => l10n.engineMpv,
      };

  static String _resultText(AppLocalizations l10n, EngineTestResult r) =>
      switch (r.status) {
        EngineTestStatus.pending => l10n.diagnostics_notRun,
        EngineTestStatus.running => l10n.diagnostics_testing,
        EngineTestStatus.passed => l10n.diagFirstFrameMs(
          r.firstFrame?.inMilliseconds ?? 0,
        ),
        EngineTestStatus.failed =>
          '${l10n.diagTestFailed}'
              '${r.message == null ? '' : ' · ${r.message}'}',
        EngineTestStatus.timedOut => l10n.diagTestFailed,
        EngineTestStatus.cancelled => l10n.diagnostics_notRun,
      };
}

/// The QR code of the diagnostics summary (dark modules on white).
class DiagnosticsQrDialog extends StatelessWidget {
  const DiagnosticsQrDialog({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.diagShowQr),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('diagnostics-qr-code'),
              color: Colors.white,
              padding: const EdgeInsets.all(Spacing.md),
              child: SizedBox.square(
                dimension: 240,
                child: PrettyQrView.data(
                  data: data,
                  decoration: const PrettyQrDecoration(
                    shape: PrettyQrSquaresSymbol(),
                    quietZone: PrettyQrQuietZone.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(l10n.diagnostics_qrHint, textAlign: TextAlign.center),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}

class _DiagButton extends StatelessWidget {
  const _DiagButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onSelect,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled ? AppColors.textPrimary : AppColors.textDisabled;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      focusScale: 1.04,
      semanticLabel: label,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: Radii.mdAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Spacing.sm),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled card. Focusable on its own so a remote can step through the
/// report (each section scrolls into view).
class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.children,
    this.focusable = true,
  });

  final String title;
  final List<Widget> children;
  final bool focusable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          ...children,
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.lg),
      child: focusable
          ? TvFocusable(
              focusScale: 1.0,
              ensureVisibleAlignment: 0.1,
              semanticLabel: title,
              child: card,
            )
          : card,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: math.min(220, c.maxWidth * 0.45),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: BidiText(
                value,
                maxLines: 3,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small live view of the engine under test.
class _Preview extends StatelessWidget {
  const _Preview({required this.engine});

  final PlayerEngine? engine;

  @override
  Widget build(BuildContext context) {
    final engine = this.engine;
    return ClipRRect(
      borderRadius: Radii.smAll,
      child: SizedBox(
        key: const ValueKey('diagnostics-preview'),
        width: 160,
        height: 90,
        child: ColoredBox(color: Colors.black, child: engine?.buildView()),
      ),
    );
  }
}

/// The recent log, newest at the bottom. Focusable: Up/Down (PageUp/Down)
/// scroll it; at its top Up moves focus on as usual.
class _LogView extends StatefulWidget {
  const _LogView({required this.lines});

  final List<String> lines;

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  static const _extent = 18.0;
  final _scroll = ScrollController();
  bool _focused = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final pos = _scroll.position;
    final key = event.logicalKey;
    final page = pos.viewportDimension;
    // The list is reversed: larger offsets are older lines (further up).
    double? delta;
    if (key == LogicalKeyboardKey.arrowUp) delta = _extent * 3;
    if (key == LogicalKeyboardKey.arrowDown) delta = -_extent * 3;
    if (key == LogicalKeyboardKey.pageUp) delta = page;
    if (key == LogicalKeyboardKey.pageDown) delta = -page;
    if (delta == null) return KeyEventResult.ignored;
    final atEdge = delta > 0
        ? pos.pixels >= pos.maxScrollExtent
        : pos.pixels <= pos.minScrollExtent;
    if (atEdge) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent &&
        KeyRepeatThrottle.instance.stepFor(event) == 0) {
      return KeyEventResult.handled;
    }
    _scroll.jumpTo(
      math.min(
        pos.maxScrollExtent,
        math.max(pos.minScrollExtent, pos.pixels + delta),
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lines = widget.lines;
    return Focus(
      key: const ValueKey('diagnostics-log-view'),
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          unawaited(
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: FocusTokens.scrollOf(context),
            ),
          );
        }
      },
      child: Container(
        height: 240,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: Radii.smAll,
          border: Border.all(
            color: _focused ? FocusTokens.borderColor : AppColors.outline,
            width: _focused ? FocusTokens.borderWidth : 1,
          ),
        ),
        child: lines.isEmpty
            ? Center(child: Text(l10n.commonEmpty))
            : Directionality(
                textDirection: TextDirection.ltr,
                child: ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  itemExtent: _extent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  itemCount: lines.length,
                  itemBuilder: (context, i) => Text(
                    lines[lines.length - 1 - i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
