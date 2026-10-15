import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../app/providers.dart';
import '../../core/net/lan_input_server.dart' show deleteTempUpload;
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import 'providers.dart';

/// "Type on your phone": shows a QR code for a one-time page on the local
/// network and returns what the phone sent, or null when the dialog was
/// closed first. A [LanSubmissionKind.m3uFile] result points at a temporary
/// file the caller must delete (`deleteTempUpload`) once imported.
Future<LanSubmission?> showLanInputDialog(
  BuildContext context, {
  LanForm form = LanForm.source,
}) => showDialog<LanSubmission>(
  context: context,
  builder: (_) => LanInputDialog(form: form),
);

enum _Phase { starting, waiting, received, expired, noNetwork, failed }

/// The dialog behind [showLanInputDialog]. It starts the server when shown
/// and stops it when closed.
class LanInputDialog extends ConsumerStatefulWidget {
  const LanInputDialog({super.key, this.form = LanForm.source});

  final LanForm form;

  @override
  ConsumerState<LanInputDialog> createState() => _LanInputDialogState();
}

class _LanInputDialogState extends ConsumerState<LanInputDialog> {
  final _closeNode = FocusNode(debugLabel: 'lan-close');
  LanInputServer? _server;
  StreamSubscription<LanInputStatus>? _statusSub;
  _Phase _phase = _Phase.starting;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_statusSub?.cancel());
    unawaited(_server?.close());
    _closeNode.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    unawaited(_statusSub?.cancel());
    _statusSub = null;
    unawaited(_server?.close());
    _server = null;
    if (_phase != _Phase.starting) setState(() => _phase = _Phase.starting);
    final LanInputServer server;
    try {
      server = await ref.read(lanServerStarterProvider)(widget.form);
    } on LanNoNetworkException {
      if (mounted && generation == _generation) {
        setState(() => _phase = _Phase.noNetwork);
      }
      return;
    } on Object catch (e) {
      ref.read(ringLogProvider).warn('Phone input page failed: $e');
      if (mounted && generation == _generation) {
        setState(() => _phase = _Phase.failed);
      }
      return;
    }
    if (!mounted || generation != _generation) {
      await server.close();
      return;
    }
    _server = server;
    _statusSub = server.statusChanges.listen((status) {
      if (!mounted || generation != _generation) return;
      if (status == LanInputStatus.expired) {
        setState(() => _phase = _Phase.expired);
      }
    });
    unawaited(
      server.result.then((submission) => _onResult(generation, submission)),
    );
    setState(() => _phase = _Phase.waiting);
  }

  void _onResult(int generation, LanSubmission? submission) {
    if (submission == null) return;
    final route = mounted ? ModalRoute.of(context) : null;
    if (generation != _generation || route == null || !route.isCurrent) {
      // Closed in the meantime: nobody will import the upload.
      unawaited(deleteTempUpload(submission.filePath));
      return;
    }
    setState(() => _phase = _Phase.received);
    Navigator.of(context).pop(submission);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final large = isLargeLayout(context);
    final server = _server;
    final showCode = server != null && _phase == _Phase.waiting;
    final qr = SizedBox.square(
      dimension: large ? 168 : 200,
      child: showCode
          ? Semantics(
              image: true,
              label: l10n.lanScanWithPhone,
              child: ExcludeSemantics(
                child: PrettyQrView.data(
                  key: ValueKey(server.url),
                  data: server.url,
                  decoration: const PrettyQrDecoration(
                    background: Colors.white,
                    quietZone: PrettyQrQuietZone.standard,
                    shape: PrettyQrSquaresSymbol(color: Colors.black),
                  ),
                ),
              ),
            )
          : DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: Radii.mdAll,
              ),
              child: Center(
                child: _phase == _Phase.starting
                    ? const CircularProgressIndicator()
                    : const Icon(
                        Icons.qr_code_2,
                        size: 64,
                        color: AppColors.textDisabled,
                      ),
              ),
            ),
    );
    final info = _Info(phase: _phase, url: showCode ? server.url : null);
    return AlertDialog(
      key: const ValueKey('lan-dialog'),
      title: Text(l10n.typeOnYourPhone),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: large ? 560 : 360),
        child: SingleChildScrollView(
          child: large
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    qr,
                    const SizedBox(width: Spacing.xl),
                    Expanded(child: info),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    qr,
                    const SizedBox(height: Spacing.lg),
                    info,
                  ],
                ),
        ),
      ),
      actions: [
        if (_phase == _Phase.expired ||
            _phase == _Phase.failed ||
            _phase == _Phase.noNetwork)
          TextButton(
            key: const ValueKey('lan-new-code'),
            onPressed: () => unawaited(_start()),
            child: Text(l10n.lanNewCode),
          ),
        TextButton(
          key: const ValueKey('lan-close'),
          focusNode: _closeNode,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.phase, required this.url});

  final _Phase phase;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final url = this.url;
    final (IconData? icon, Color color, String text) = switch (phase) {
      _Phase.starting => (null, AppColors.textSecondary, l10n.commonLoading),
      _Phase.waiting => (
        null,
        AppColors.textSecondary,
        l10n.lanWaitingForInput,
      ),
      _Phase.received => (
        Icons.check_circle,
        AppColors.success,
        l10n.lanReceived,
      ),
      _Phase.expired => (
        Icons.timer_off_outlined,
        AppColors.error,
        l10n.lanCodeExpired,
      ),
      _Phase.noNetwork => (Icons.wifi_off, AppColors.error, l10n.lanNoNetwork),
      _Phase.failed => (
        Icons.error_outline,
        AppColors.error,
        l10n.commonErrorGeneric,
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.lanScanWithPhone, style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        Text(l10n.lanSameNetwork, style: theme.textTheme.bodyMedium),
        if (url != null) ...[
          const SizedBox(height: Spacing.md),
          Text(
            l10n.lanOrOpen(url),
            key: const ValueKey('lan-url'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        Semantics(
          liveRegion: true,
          child: Row(
            key: const ValueKey('lan-status'),
            children: [
              if (icon == null)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 18, color: color),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
