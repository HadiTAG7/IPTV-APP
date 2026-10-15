import '../../app/form_factor.dart';
import '../../app/settings.dart';
import '../../core/db/app_db.dart';
import '../../core/net/redact.dart';
import '../../core/platform/device_caps.dart';
import '../../player/ui/player_format.dart';
import 'engine_ab_test.dart';

/// Everything the Diagnostics report shows, gathered once.
class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.caps,
    required this.formFactor,
    required this.lite,
    required this.settings,
    this.appVersion,
    this.sources = const [],
    this.results = const [],
    this.streams = const [],
    this.logLines = const [],
    this.secrets = const [],
    this.generatedAt,
  });

  final DeviceCaps caps;
  final String? appVersion;
  final FormFactor formFactor;
  final bool lite;
  final AppSettings settings;
  final List<SourceRow> sources;
  final List<EngineTestResult> results;
  final List<DiagnosticsTestStream> streams;

  /// Recent log lines (already redacted by the log).
  final List<String> logLines;

  /// Extra strings to mask (source credentials known to the caller).
  final Iterable<String> secrets;
  final DateTime? generatedAt;
}

/// Maximum characters of [buildDiagnosticsSummary] (a QR code a TV screen
/// shows and a phone camera reads reliably).
const kDiagnosticsQrMaxChars = 1000;

/// The chipset as known: the hardware name, the SoC maker and "Amlogic"
/// when the device was detected as one and neither part says so already.
List<String> chipsetParts(DeviceCaps caps) {
  final parts = [
    caps.hardware,
    ?caps.socManufacturer,
  ].where((p) => p.trim().isNotEmpty).toList();
  final named = parts.any((p) => p.toLowerCase().contains('amlogic'));
  return [...parts, if (caps.isAmlogic && !named) 'Amlogic'];
}

/// The full plain-text report for "Copy report": device, app, settings,
/// sources (no URLs or names), engine test and the last [logLines] lines.
/// Every line is redacted, and URLs keep only their host and extension
/// ([hideUrlPaths]): an imported Xtream playlist carries the account in
/// the stream path, which [redact] cannot recognise.
String buildDiagnosticsReport(DiagnosticsSnapshot s, {int logLines = 200}) {
  final b = StringBuffer()
    ..writeln('IPTV Player diagnostics')
    ..write(_summaryBody(s))
    ..writeln()
    ..writeln('Sources: ${s.sources.length}');
  for (final src in s.sources) {
    b.writeln(
      '- ${src.kind.name}, account ${src.accountStatus.name}'
      '${src.maxConnections == null ? '' : ', max connections ${src.maxConnections}'}'
      '${src.allowedFormats.isEmpty ? '' : ', formats ${src.allowedFormats.join('/')}'}'
      ', catalog generation ${src.generation}'
      '${src.lastSyncAt == null ? '' : ', synced ${src.lastSyncAt!.toUtc().toIso8601String()}'}',
    );
  }
  final lines = s.logLines.length > logLines
      ? s.logLines.sublist(s.logLines.length - logLines)
      : s.logLines;
  b
    ..writeln()
    ..writeln('Recent log (${lines.length} lines):');
  for (final l in lines) {
    b.writeln(l);
  }
  return hideUrlPaths(redact(b.toString(), secrets: s.secrets));
}

/// A short summary for the QR code: device, app, settings and engine test,
/// at most [maxChars] characters.
String buildDiagnosticsSummary(
  DiagnosticsSnapshot s, {
  int maxChars = kDiagnosticsQrMaxChars,
}) {
  final text = hideUrlPaths(
    redact('IPTV Player diagnostics\n${_summaryBody(s)}', secrets: s.secrets),
  ).trimRight();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars - 1)}…';
}

String _summaryBody(DiagnosticsSnapshot s) {
  final c = s.caps;
  final b = StringBuffer();
  final at = s.generatedAt;
  if (at != null) b.writeln('Time: ${at.toUtc().toIso8601String()}');
  b
    ..writeln('App: ${s.appVersion ?? 'unknown'}')
    ..writeln(
      'Device: ${c.platform.name}'
      '${c.sdkInt > 0 ? ' SDK ${c.sdkInt}' : ''}'
      '${_join([c.manufacturer, c.model]).isEmpty ? '' : ', ${_join([c.manufacturer, c.model])}'}',
    )
    ..writeln(
      'TV: ${c.isTv} (uiModeTv ${c.uiModeTv}, leanback ${c.leanback}, '
      'fireTv ${c.fireTv}, touch ${c.touch}); layout ${s.formFactor.name}',
    )
    ..writeln(
      'SoC: ${_join(chipsetParts(c)).isEmpty ? '-' : _join(chipsetParts(c))}'
      ', cores ${c.cpuCount}',
    )
    ..writeln(
      'RAM: ${c.totalRamMb > 0 ? '${c.totalRamMb} MB' : 'unknown'}'
      '${c.isLowRamDevice ? ' (low-RAM device)' : ''}, lite ${s.lite}',
    )
    ..writeln(
      'ABIs: ${c.supportedAbis.isEmpty ? '-' : c.supportedAbis.join(', ')}',
    )
    ..writeln(
      'Decoders: ${[for (final k in DeviceCaps.decoderKeys) '$k ${c.hasDecoder(k) ? 'yes' : 'no'}'].join(', ')}',
    );
  final st = s.settings;
  b.writeln(
    'Settings: live ${st.liveEngine.name}, vod ${st.vodEngine.name}, '
    'exo ${st.exoView.name}, hwdec ${st.hwdec}, audio ${st.preferredAudioLang}, '
    'subs ${st.preferredSubLang}, aspect ${st.defaultAspect.name}, '
    'device ${st.formFactor.name}, lite ${st.lite.name}',
  );
  if (s.results.any((r) => r.status != EngineTestStatus.pending)) {
    b.writeln('Engine test:');
    for (final r in s.results) {
      final name = r.stream < s.streams.length
          ? s.streams[r.stream].name
          : '#${r.stream + 1}';
      final ms = r.firstFrame?.inMilliseconds;
      b.writeln(
        '- ${r.engine.name} $name: ${r.status.name}'
        '${ms == null ? '' : ' $ms ms'}'
        '${r.message == null ? '' : ' (${r.message})'}',
      );
    }
  }
  return b.toString();
}

String _join(List<String> parts) =>
    parts.where((p) => p.trim().isNotEmpty).join(' ').trim();
