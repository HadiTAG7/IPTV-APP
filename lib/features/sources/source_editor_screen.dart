import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/form_factor.dart';
import '../../app/home_shell.dart' show describeSourceError;
import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../core/net/http.dart';
import '../../core/net/lan_input_server.dart'
    show deleteTempUpload, writeTempUpload;
import '../../core/secure/secret_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../sources/models.dart';
import '../../sources/source_repository.dart';
import '../../sources/sync/sync_progress.dart';
import '../../theme/tokens.dart';
import '../../tv/focus_watchdog.dart';
import '../../tv/tv_text_field.dart';
import '../../widgets/bidi_text.dart';
import '../../widgets/states.dart';
import '../lan_input/lan_input_dialog.dart';
import '../lan_input/providers.dart';
import 'import_progress_screen.dart';
import 'providers.dart';
import 'source_form.dart';
import 'widgets/row_traversal.dart';
import 'widgets/tv_buttons.dart';

/// Opens the source editor as a full-screen route: a new source, or the
/// saved source [sourceId]. With [onboarding] the first-run flow keeps
/// onboarding on screen (see [onboardingHoldProvider]) until the import is
/// over. A new source can start as an M3U link with [initialUrl] and
/// [initialName] filled in (Help's "Add as source"); the user still reviews
/// and saves it.
Future<void> openSourceEditor(
  BuildContext context, {
  int? sourceId,
  bool onboarding = false,
  String? initialUrl,
  String? initialName,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/source-editor'),
    builder: (_) => SourceEditorScreen(
      sourceId: sourceId,
      onboarding: onboarding,
      initialUrl: initialUrl,
      initialName: initialName,
    ),
  ),
);

/// Adds or edits a source: type (M3U link, M3U file, Xtream Codes), its
/// fields, advanced options (User-Agent, Referer, extra guide URL, live
/// format), "Type on your phone", and Test & save.
///
/// Test & save validates the fields, checks the source with
/// [SourceRepository.verify] (localized errors, never credentials), saves
/// it, imports its catalog on [ImportProgressScreen], makes it the active
/// source and returns to the home screen (the route stack is cleared).
class SourceEditorScreen extends ConsumerStatefulWidget {
  const SourceEditorScreen({
    super.key,
    this.sourceId,
    this.onboarding = false,
    this.initialUrl,
    this.initialName,
  });

  /// The saved source to edit; null adds a new one.
  final int? sourceId;

  /// Opened from the first-run flow.
  final bool onboarding;

  /// A new source: the M3U link to start with (nothing is saved until Test
  /// & save). Ignored when editing [sourceId].
  final String? initialUrl;

  /// A new source: the name to start with.
  final String? initialName;

  @override
  ConsumerState<SourceEditorScreen> createState() => _SourceEditorScreenState();
}

const _kinds = [SourceKind.m3uUrl, SourceKind.m3uFile, SourceKind.xtream];

/// The User-Agent chips: the presets, then Custom (null).
final List<String?> _uaChoices = [...kUserAgentPresets.keys, null];

class _SourceEditorScreenState extends ConsumerState<SourceEditorScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _customUa = TextEditingController();
  final _referer = TextEditingController();
  final _epg = TextEditingController();

  late final Map<SourceKind, FocusNode> _typeNodes = {
    for (final k in _kinds) k: FocusNode(debugLabel: 'type-${k.name}'),
  };
  late final Map<String?, FocusNode> _uaNodes = {
    for (final k in _uaChoices) k: FocusNode(debugLabel: 'ua-${k ?? 'custom'}'),
  };
  late final Map<LiveFormat, FocusNode> _formatNodes = {
    for (final f in LiveFormat.values) f: FocusNode(debugLabel: 'fmt-$f'),
  };
  final _nameNode = FocusNode(debugLabel: 'field-name');
  final _urlNode = FocusNode(debugLabel: 'field-url');
  final _fileNode = FocusNode(debugLabel: 'pick-file');
  final _serverNode = FocusNode(debugLabel: 'field-server');
  final _usernameNode = FocusNode(debugLabel: 'field-username');
  final _passwordNode = FocusNode(debugLabel: 'field-password');
  final _revealNode = FocusNode(debugLabel: 'toggle-password');
  final _convertNode = FocusNode(debugLabel: 'convert-xtream');
  final _phoneNode = FocusNode(debugLabel: 'type-on-phone');
  final _advancedNode = FocusNode(debugLabel: 'advanced');
  final _customUaNode = FocusNode(debugLabel: 'field-ua');
  final _refererNode = FocusNode(debugLabel: 'field-referer');
  final _epgNode = FocusNode(debugLabel: 'field-epg');
  final _saveNode = FocusNode(debugLabel: 'save');

  SourceKind _kind = SourceKind.m3uUrl;
  LiveFormat _liveFormat = LiveFormat.ts;
  String? _uaPreset = kDefaultUserAgentPreset;
  var _obscure = true;
  var _advanced = false;
  var _busy = false;
  var _showErrors = false;
  late var _loading = widget.sourceId != null;
  var _loadFailed = false;

  /// A localized failure (verify, import) or info line below the form.
  String? _error;
  String? _info;

  /// The id once saved (the edited source, or the new one after its first
  /// save, so a second Test & save updates it).
  late int? _savedId = widget.sourceId;
  SourceView? _row;
  SourceConfig? _saved;
  EpgSourceRow? _manualEpg;
  PickedPlaylist? _picked;
  String? _importedFileName;
  XtreamLink? _link;
  FocusWatchdogState? _watchdog;

  SourceRepository get _repo => ref.read(sourceRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (_loading) {
      unawaited(_load());
    } else {
      _prefill();
    }
  }

  /// A new source offered by Help: an M3U link with its suggested name.
  void _prefill() {
    final url = widget.initialUrl?.trim() ?? '';
    final name = widget.initialName?.trim() ?? '';
    if (url.isEmpty && name.isEmpty) return;
    _kind = SourceKind.m3uUrl;
    _url.text = url;
    _name.text = name;
    _link = _detectLink();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchdog = FocusWatchdog.maybeOf(context);
    if (watchdog != _watchdog) {
      _watchdog?.unregister(_typeNodes[_kind]!);
      _watchdog = watchdog?..register(_typeNodes[_kind]!);
    }
  }

  @override
  void dispose() {
    final picked = _picked;
    if (picked != null && picked.isTemporary) {
      unawaited(deleteTempUpload(picked.path));
    }
    for (final node in _typeNodes.values) {
      _watchdog?.unregister(node);
    }
    _watchdog?.unregister(_saveNode);
    for (final c in [
      _name,
      _url,
      _server,
      _username,
      _password,
      _customUa,
      _referer,
      _epg,
    ]) {
      c.dispose();
    }
    for (final n in [
      ..._typeNodes.values,
      ..._uaNodes.values,
      ..._formatNodes.values,
      _nameNode,
      _urlNode,
      _fileNode,
      _serverNode,
      _usernameNode,
      _passwordNode,
      _revealNode,
      _convertNode,
      _phoneNode,
      _advancedNode,
      _customUaNode,
      _refererNode,
      _epgNode,
      _saveNode,
    ]) {
      n.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Loading and values.

  Future<void> _load() async {
    final id = widget.sourceId!;
    // Read before the first await: `ref` is unusable once the page closed.
    final log = ref.read(ringLogProvider);
    final epg = ref.read(epgDaoProvider);
    try {
      await _reloadSaved(id, _repo, epg);
      if (!mounted) return;
      final row = _row;
      final saved = _saved;
      if (row == null || saved == null) throw StateError('Unknown source');
      _name.text = row.name;
      _kind = row.kind;
      switch (row.kind) {
        case SourceKind.xtream:
          _server.text = saved.url;
          _username.text = saved.username ?? '';
        case SourceKind.m3uUrl:
          // The masked copy: credentials in the link are never shown.
          _url.text = row.url;
        case SourceKind.m3uFile:
          break;
      }
      _liveFormat = row.liveFormat;
      _uaPreset = userAgentPresetFor(row.userAgent);
      if (_uaPreset == null) _customUa.text = row.userAgent ?? '';
      _referer.text = row.referer ?? '';
      _epg.text = _manualEpg?.url ?? '';
      _advanced =
          _uaPreset != kDefaultUserAgentPreset ||
          _referer.text.isNotEmpty ||
          _epg.text.isNotEmpty;
      _link = _detectLink();
    } on Object catch (e) {
      log.warn('Opening source $id failed: $e');
      _loadFailed = true;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _registerWatchdog(_typeNodes[_kind]!);
  }

  Future<void> _reloadSaved(int id, SourceRepository repo, EpgDao epg) async {
    _row = await repo.byId(id);
    _saved = await repo.configFor(id);
    final guides = await epg.epgSources(id);
    _manualEpg = guides.where((g) => g.origin == EpgOrigin.manual).firstOrNull;
  }

  void _registerWatchdog(FocusNode node) => _watchdog?.register(node);

  bool get _hasSavedPassword =>
      _row?.kind == SourceKind.xtream && (_saved?.password ?? '').isNotEmpty;

  String? get _savedMaskedUrl =>
      _row?.kind == SourceKind.m3uUrl ? _row?.url : null;

  /// The playlist URL to use: the saved full URL while the field still
  /// shows its masked copy.
  String _effectiveUrl() {
    final text = _url.text.trim();
    final masked = _savedMaskedUrl;
    if (masked != null && text == masked) return _saved?.url ?? text;
    return text;
  }

  XtreamLink? _detectLink() => _kind == SourceKind.m3uUrl
      ? _repo.detectXtreamLink(_effectiveUrl())
      : null;

  /// The picked playlist's name; for a saved one (stored under a random
  /// name) the name it was imported with, else the source's name.
  String? get _fileName {
    final picked = _picked;
    if (picked != null) return picked.name;
    final row = _row;
    if (row?.kind == SourceKind.m3uFile) return _importedFileName ?? row!.name;
    return null;
  }

  SourceFormValues _values() => SourceFormValues(
    kind: _kind,
    name: _name.text,
    url: _url.text,
    savedMaskedUrl: _savedMaskedUrl,
    hasFile: _fileName != null,
    server: _server.text,
    username: _username.text,
    password: _password.text,
    hasSavedPassword: _hasSavedPassword,
    userAgentPreset: _uaPreset,
    customUserAgent: _customUa.text,
    referer: _referer.text,
    epgUrl: _epg.text,
    savedEpgUrl: _manualEpg?.url,
  );

  /// The config to check and save. [forSaving] keeps a saved password
  /// (null) instead of filling it in.
  SourceConfig _config({required bool forSaving}) {
    final name = _name.text.trim();
    final common = (
      name: name,
      userAgent: userAgentFor(_uaPreset, _customUa.text),
      referer: _referer.text.trim(),
      offset: _saved?.epgOffsetMin ?? 0,
    );
    switch (_kind) {
      case SourceKind.xtream:
        final typed = _password.text;
        final password = typed.isNotEmpty
            ? typed
            : (forSaving || !_hasSavedPassword ? null : _saved?.password);
        return SourceConfig(
          id: _savedId,
          kind: SourceKind.xtream,
          url: _server.text.trim(),
          name: common.name,
          username: _username.text.trim(),
          password: password,
          userAgent: common.userAgent,
          referer: common.referer,
          liveFormat: _liveFormat,
          epgOffsetMin: common.offset,
        );
      case SourceKind.m3uUrl:
        return SourceConfig(
          id: _savedId,
          kind: SourceKind.m3uUrl,
          url: _effectiveUrl(),
          name: common.name,
          userAgent: common.userAgent,
          referer: common.referer,
          liveFormat: _liveFormat,
          epgOffsetMin: common.offset,
        );
      case SourceKind.m3uFile:
        final picked = _picked;
        return SourceConfig(
          id: _savedId,
          kind: SourceKind.m3uFile,
          url: picked?.path ?? (_saved?.url ?? ''),
          name: name.isEmpty && picked != null
              ? SourceRepository.defaultName(SourceKind.m3uFile, picked.name)
              : common.name,
          userAgent: common.userAgent,
          referer: common.referer,
          liveFormat: _liveFormat,
          epgOffsetMin: common.offset,
        );
    }
  }

  // -------------------------------------------------------------------------
  // Actions.

  void _focusAfterBuild(FocusNode node) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  void _setKind(SourceKind kind) {
    if (_busy || kind == _kind) return;
    _watchdog?.unregister(_typeNodes[_kind]!);
    setState(() {
      _kind = kind;
      _error = null;
      _info = null;
      _link = _detectLink();
    });
    _registerWatchdog(_typeNodes[kind]!);
  }

  void _onUrlChanged(String _) {
    final link = _detectLink();
    final changed =
        (link == null) != (_link == null) ||
        (link != null && _link != null && link.base != _link!.base);
    _link = link;
    if (changed || _showErrors) setState(() {});
  }

  void _convertToXtream() {
    final link = _link;
    if (link == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _kind = SourceKind.xtream;
      _server.text = link.base;
      _username.text = link.username;
      _password.text = link.password;
      _obscure = true;
      _liveFormat = link.liveFormat;
      _link = null;
      _error = null;
      _info = l10n.sourcesXtreamLinkConverted;
    });
    _focusAfterBuild(_saveNode);
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final log = ref.read(ringLogProvider);
    PickedPlaylist? picked;
    try {
      picked = await ref.read(playlistPickerProvider)();
    } on Object catch (e) {
      log.warn('File picker failed: ${e.runtimeType}');
      if (mounted) setState(() => _error = l10n.errorFileRead);
      return;
    }
    if (picked == null || !mounted) return;
    _replacePicked(picked);
  }

  void _replacePicked(PickedPlaylist? picked) {
    final old = _picked;
    if (old != null && old.isTemporary && old.path != picked?.path) {
      unawaited(deleteTempUpload(old.path));
    }
    setState(() {
      _picked = picked;
      _error = null;
    });
  }

  Future<void> _typeOnPhone() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final submission = await showLanInputDialog(context);
    if (submission == null) return;
    if (!mounted) {
      unawaited(deleteTempUpload(submission.filePath));
      return;
    }
    switch (submission.kind) {
      case LanSubmissionKind.xtream:
        _setKind(SourceKind.xtream);
        _server.text = submission['server'] ?? '';
        _username.text = submission['username'] ?? '';
        _password.text = submission['password'] ?? '';
        _obscure = true;
      case LanSubmissionKind.m3uUrl:
        _setKind(SourceKind.m3uUrl);
        _url.text = submission['url'] ?? '';
      case LanSubmissionKind.m3uFile:
        _setKind(SourceKind.m3uFile);
        _replacePicked(
          PickedPlaylist(
            name: submission.fileName ?? 'playlist.m3u',
            path: submission.filePath,
            isTemporary: true,
          ),
        );
      case LanSubmissionKind.search:
        return;
    }
    setState(() {
      _link = _detectLink();
      _error = null;
      _info = l10n.sourcesReceivedFromPhone;
    });
  }

  FocusNode _nodeFor(SourceField field) => switch (field) {
    SourceField.name => _nameNode,
    SourceField.url => _urlNode,
    SourceField.file => _fileNode,
    SourceField.server => _serverNode,
    SourceField.username => _usernameNode,
    SourceField.password => _passwordNode,
    SourceField.userAgent => _customUaNode,
    SourceField.referer => _refererNode,
    SourceField.epgUrl => _epgNode,
  };

  Future<void> _testAndSave() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final errors = validateSourceForm(_values());
    setState(() {
      _showErrors = true;
      _error = null;
      _info = null;
    });
    if (errors.isNotEmpty) {
      final first = errors.keys.first;
      const advanced = {
        SourceField.userAgent,
        SourceField.referer,
        SourceField.epgUrl,
      };
      if (advanced.contains(first) && !_advanced) {
        setState(() => _advanced = true);
      }
      _focusAfterBuild(_nodeFor(first));
      return;
    }
    // One snapshot of the form: the fields stay editable while the check
    // runs, and only what was checked is saved. Providers are read now too,
    // as `ref` cannot be used once the page has closed.
    final kind = _kind;
    final picked = _picked;
    var draft = _config(forSaving: false);
    var config = _config(forSaving: true);
    final guideUrl = _epg.text.trim();
    final savedId = _savedId;
    final previous = _saved;
    final previousGuide = _manualEpg;
    final repo = _repo;
    final log = ref.read(ringLogProvider);
    final sync = ref.read(syncServiceProvider);
    final epg = ref.read(epgDaoProvider);
    final secrets = ref.read(secretStoreProvider);
    final hold = ref.read(onboardingHoldProvider.notifier);
    setState(() => _busy = true);
    String? tempCopy;
    // A playlist copy made for this save, until the source owns it.
    String? newCopy;
    try {
      if (kind == SourceKind.m3uFile && picked != null) {
        final open = picked.openRead;
        if (picked.path == null && open != null) {
          tempCopy = await writeTempUpload(open());
          draft = draft.copyWith(url: tempCopy);
        }
      }
      final result = await repo.verify(draft);
      if (!mounted) return;
      if (result is VerifyError) {
        setState(() {
          _busy = false;
          _error = describeSourceError(l10n, result);
        });
        return;
      }
      if (kind == SourceKind.m3uFile && picked != null) {
        newCopy = await repo.importM3uFile(draft.url);
        config = config.copyWith(url: newCopy);
      }
      if (widget.onboarding) hold.set(true);
      final int id;
      if (savedId == null) {
        id = await repo.add(config);
        _savedId = id;
      } else {
        id = savedId;
        await repo.update(id, config);
      }
      newCopy = null;
      if (kind == SourceKind.m3uFile && picked != null) {
        if (picked.isTemporary) await deleteTempUpload(picked.path);
        _importedFileName = picked.name;
        _picked = null;
      }
      // A sync already running for this source (startup auto-sync, Refresh)
      // uses the settings it started with: stop it so the import below
      // starts again with the saved ones.
      await sync.cancelAndWait(id);
      // The playlist copy the source no longer uses (replaced by a new
      // file, or the source is no longer a file).
      if (previous != null &&
          previous.kind == SourceKind.m3uFile &&
          (config.kind != SourceKind.m3uFile || config.url != previous.url)) {
        await repo.deleteImportedFile(previous.url);
      }
      await _saveGuideUrl(id, guideUrl, previousGuide, epg, secrets);
      await _reloadSaved(id, repo, epg);
      if (!mounted) {
        // Saved, but the page closed: import in the background (Sources
        // shows the progress).
        sync.sync(id);
        return;
      }
      _url.text = _row?.kind == SourceKind.m3uUrl ? _row!.url : _url.text;
      _password.clear();
      setState(() => _busy = false);
      final outcome = await showImportProgress(context, id);
      if (!mounted) return;
      switch (outcome) {
        case ImportOutcome.done:
          await _finish(id);
        case ImportOutcome.cancelled:
          setState(() => _info = l10n.sourcesImportCancelled);
        case ImportOutcome.edit:
          final status = sync.statusOf(id);
          setState(() {
            _error = switch (status) {
              SyncFailed(:final error?) => describeSourceError(l10n, error),
              _ => l10n.importFailed,
            };
          });
        case null:
          break;
      }
    } on Object catch (e) {
      log.warn('Saving the source failed: $e');
      if (newCopy != null) await repo.deleteImportedFile(newCopy);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.commonErrorGeneric;
        });
      }
    } finally {
      if (tempCopy != null) unawaited(deleteTempUpload(tempCopy));
    }
  }

  /// Saves the manual guide URL [text] when it changed from [previous] (the
  /// masked saved copy left as is keeps the saved one).
  Future<void> _saveGuideUrl(
    int id,
    String text,
    EpgSourceRow? previous,
    EpgDao epg,
    SecretStore secrets,
  ) async {
    if (previous != null && text == previous.url) return;
    if (previous != null) {
      await epg.deleteEpgSource(previous.id, secrets: secrets);
    }
    if (text.isNotEmpty) {
      await epg.addEpgSource(
        id,
        text,
        EpgOrigin.manual,
        priority: 100,
        secrets: secrets,
      );
    }
  }

  /// Makes the imported source active and returns to the home screen.
  Future<void> _finish(int id) async {
    final hold = ref.read(onboardingHoldProvider.notifier);
    await ref.read(activeSourceIdProvider.notifier).select(id);
    if (widget.onboarding) hold.set(false);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // -------------------------------------------------------------------------
  // UI.

  String? _errorText(
    AppLocalizations l10n,
    Map<SourceField, SourceFieldError> errors,
    SourceField field,
  ) {
    if (!_showErrors) return null;
    return switch (errors[field]) {
      null => null,
      SourceFieldError.required => l10n.fieldRequired,
      SourceFieldError.invalidUrl => l10n.errorInvalidUrl,
      SourceFieldError.maskedUrl => l10n.sourcesReenterUrl,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tv = FormFactorScope.isTv(context);
    final editing = widget.sourceId != null;
    Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (_loadFailed) {
      body = ErrorView(
        onRetry: () {
          setState(() {
            _loadFailed = false;
            _loading = true;
          });
          unawaited(_load());
        },
      );
    } else {
      body = _form(context, l10n);
    }
    Widget page = Scaffold(
      appBar: AppBar(
        // The remote's Back key closes the page on TV; a focusable arrow in
        // the corner would only be a detour for Left/Up.
        automaticallyImplyLeading: !tv,
        title: Text(editing ? l10n.settingsEditSource : l10n.settingsAddSource),
      ),
      body: SafeArea(top: false, child: body),
    );
    if (tv) {
      // Overscan-safe on TV, app bar included.
      page = ColoredBox(
        color: AppColors.background,
        child: Padding(padding: overscanPadding(FormFactor.tv), child: page),
      );
    }
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && widget.onboarding) {
          ref.read(onboardingHoldProvider.notifier).set(false);
        }
      },
      child: page,
    );
  }

  Widget _form(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final large = isLargeLayout(context);
    final errors = validateSourceForm(_values());
    String? err(SourceField f) => _errorText(l10n, errors, f);
    const gap = SizedBox(height: Spacing.md);
    const ltr = TextDirection.ltr;

    final children = <Widget>[
      _SectionLabel(l10n.sourcesEditorType),
      _TypeChooser(
        large: large,
        children: [
          for (final kind in _kinds)
            TvChoiceChip(
              key: ValueKey('type-${kind.name}'),
              focusNode: _typeNodes[kind],
              autofocus: kind == _kind,
              selected: kind == _kind,
              label: _kindLabel(l10n, kind),
              subtitle: _kindHint(l10n, kind),
              onSelect: () => _setKind(kind),
            ),
        ],
      ),
      const SizedBox(height: Spacing.lg),
      TvTextField(
        key: const ValueKey('field-name'),
        controller: _name,
        focusNode: _nameNode,
        decoration: InputDecoration(
          labelText: l10n.fieldName,
          hintText: l10n.fieldNameHint,
          helperText: l10n.fieldOptional,
        ),
      ),
      gap,
      ..._kindFields(l10n, theme, err, ltr),
      const SizedBox(height: Spacing.lg),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TvButton(
          key: const ValueKey('type-on-phone'),
          focusNode: _phoneNode,
          icon: Icons.phonelink_outlined,
          label: l10n.typeOnYourPhone,
          onSelect: () => unawaited(_typeOnPhone()),
        ),
      ),
      const SizedBox(height: Spacing.md),
      TvButton(
        key: const ValueKey('advanced'),
        focusNode: _advancedNode,
        expand: true,
        icon: _advanced ? Icons.expand_less : Icons.expand_more,
        label: l10n.fieldAdvancedOptions,
        onSelect: () => setState(() => _advanced = !_advanced),
      ),
      if (_advanced) ..._advancedFields(l10n, err, ltr),
      if (_error case final error?) ...[
        const SizedBox(height: Spacing.lg),
        _Message(key: const ValueKey('editor-error'), text: error, error: true),
      ],
      if (_info case final info? when _error == null) ...[
        const SizedBox(height: Spacing.lg),
        _Message(key: const ValueKey('editor-info'), text: info),
      ],
      const SizedBox(height: Spacing.lg),
      TvButton(
        key: const ValueKey('save'),
        focusNode: _saveNode,
        primary: true,
        expand: true,
        busy: _busy,
        icon: Icons.check,
        label: _busy ? l10n.validating : l10n.testAndSave,
        onSelect: () => unawaited(_testAndSave()),
      ),
    ];

    return FocusTraversalGroup(
      policy: RowTraversalPolicy(),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: large ? Spacing.xl : Spacing.lg,
          vertical: Spacing.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _kindFields(
    AppLocalizations l10n,
    ThemeData theme,
    String? Function(SourceField) err,
    TextDirection ltr,
  ) {
    const gap = SizedBox(height: Spacing.md);
    switch (_kind) {
      case SourceKind.m3uUrl:
        final link = _link;
        return [
          TvTextField(
            key: const ValueKey('field-url'),
            controller: _url,
            focusNode: _urlNode,
            keyboardType: TextInputType.url,
            textDirection: ltr,
            onChanged: _onUrlChanged,
            decoration: InputDecoration(
              labelText: l10n.fieldPlaylistUrl,
              hintText: l10n.fieldPlaylistUrlHint,
              errorText: err(SourceField.url),
              errorMaxLines: 3,
            ),
          ),
          if (link != null) ...[
            gap,
            _ConvertCard(
              key: const ValueKey('convert-card'),
              focusNode: _convertNode,
              onConvert: _convertToXtream,
            ),
          ],
        ];
      case SourceKind.m3uFile:
        final fileName = _fileName;
        final fileError = err(SourceField.file);
        return [
          Row(
            children: [
              TvButton(
                key: const ValueKey('pick-file'),
                focusNode: _fileNode,
                icon: Icons.folder_open_outlined,
                label: l10n.fieldChooseFile,
                onSelect: () => unawaited(_pickFile()),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: fileName == null
                    ? Text(
                        l10n.fieldNoFileChosen,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    : BidiText(
                        fileName,
                        key: const ValueKey('file-name'),
                        style: theme.textTheme.bodyMedium,
                      ),
              ),
            ],
          ),
          if (fileError != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Spacing.lg,
                top: Spacing.xs,
              ),
              child: Text(
                fileError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
        ];
      case SourceKind.xtream:
        return [
          TvTextField(
            key: const ValueKey('field-server'),
            controller: _server,
            focusNode: _serverNode,
            keyboardType: TextInputType.url,
            textDirection: ltr,
            onChanged: _showErrors ? (_) => setState(() {}) : null,
            decoration: InputDecoration(
              labelText: l10n.fieldServer,
              hintText: l10n.fieldServerHint,
              errorText: err(SourceField.server),
              errorMaxLines: 3,
            ),
          ),
          gap,
          TvTextField(
            key: const ValueKey('field-username'),
            controller: _username,
            focusNode: _usernameNode,
            textDirection: ltr,
            autofillHints: const [AutofillHints.username],
            onChanged: _showErrors ? (_) => setState(() {}) : null,
            decoration: InputDecoration(
              labelText: l10n.fieldUsername,
              errorText: err(SourceField.username),
            ),
          ),
          gap,
          TvTextField(
            key: const ValueKey('field-password'),
            controller: _password,
            focusNode: _passwordNode,
            textDirection: ltr,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            onChanged: _showErrors ? (_) => setState(() {}) : null,
            decoration: InputDecoration(
              labelText: l10n.fieldPassword,
              helperText: _hasSavedPassword ? l10n.sourcesKeepPassword : null,
              helperMaxLines: 2,
              errorText: err(SourceField.password),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TvButton(
              key: const ValueKey('toggle-password'),
              focusNode: _revealNode,
              height: 36,
              icon: _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: _obscure ? l10n.fieldShowPassword : l10n.fieldHidePassword,
              onSelect: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ];
    }
  }

  List<Widget> _advancedFields(
    AppLocalizations l10n,
    String? Function(SourceField) err,
    TextDirection ltr,
  ) {
    return [
      const SizedBox(height: Spacing.md),
      _SectionLabel(l10n.fieldUserAgent),
      Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final choice in _uaChoices)
            TvChoiceChip(
              key: ValueKey('ua-${choice ?? 'custom'}'),
              focusNode: _uaNodes[choice],
              selected: _uaPreset == choice,
              label: switch (choice) {
                null => l10n.fieldUserAgentCustom,
                kDefaultUserAgentPreset => l10n.sourcesUserAgentDefault,
                final name => name,
              },
              onSelect: () => setState(() => _uaPreset = choice),
            ),
        ],
      ),
      if (_uaPreset == null) ...[
        const SizedBox(height: Spacing.md),
        TvTextField(
          key: const ValueKey('field-ua'),
          controller: _customUa,
          focusNode: _customUaNode,
          textDirection: ltr,
          onChanged: _showErrors ? (_) => setState(() {}) : null,
          decoration: InputDecoration(
            labelText: l10n.fieldUserAgent,
            errorText: err(SourceField.userAgent),
          ),
        ),
      ],
      const SizedBox(height: Spacing.md),
      TvTextField(
        key: const ValueKey('field-referer'),
        controller: _referer,
        focusNode: _refererNode,
        keyboardType: TextInputType.url,
        textDirection: ltr,
        onChanged: _showErrors ? (_) => setState(() {}) : null,
        decoration: InputDecoration(
          labelText: l10n.fieldReferer,
          helperText: l10n.fieldOptional,
          errorText: err(SourceField.referer),
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: Spacing.md),
      TvTextField(
        key: const ValueKey('field-epg'),
        controller: _epg,
        focusNode: _epgNode,
        keyboardType: TextInputType.url,
        textDirection: ltr,
        onChanged: _showErrors ? (_) => setState(() {}) : null,
        decoration: InputDecoration(
          labelText: l10n.fieldEpgUrl,
          hintText: l10n.fieldEpgUrlHint,
          errorText: err(SourceField.epgUrl),
          errorMaxLines: 3,
        ),
      ),
      if (_kind == SourceKind.xtream) ...[
        const SizedBox(height: Spacing.md),
        _SectionLabel(l10n.fieldLiveFormat),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final format in LiveFormat.values)
              TvChoiceChip(
                key: ValueKey('format-${format.name}'),
                focusNode: _formatNodes[format],
                selected: _liveFormat == format,
                label: switch (format) {
                  LiveFormat.ts => l10n.liveFormatTs,
                  LiveFormat.m3u8 => l10n.liveFormatHls,
                },
                onSelect: () => setState(() => _liveFormat = format),
              ),
          ],
        ),
      ],
    ];
  }
}

String _kindLabel(AppLocalizations l10n, SourceKind kind) => switch (kind) {
  SourceKind.m3uUrl => l10n.sourceTypeM3uUrl,
  SourceKind.m3uFile => l10n.sourceTypeM3uFile,
  SourceKind.xtream => l10n.sourceTypeXtream,
};

String _kindHint(AppLocalizations l10n, SourceKind kind) => switch (kind) {
  SourceKind.m3uUrl => l10n.sourceTypeM3uUrlHint,
  SourceKind.m3uFile => l10n.sourceTypeM3uFileHint,
  SourceKind.xtream => l10n.sourceTypeXtreamHint,
};

/// The source types: one row of equal chips on large layouts (left/right
/// with the remote), a column on phones.
class _TypeChooser extends StatelessWidget {
  const _TypeChooser({required this.large, required this.children});

  final bool large;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(height: Spacing.sm),
            child,
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: Spacing.sm),
            Expanded(child: child),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: AppColors.textSecondary),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.error : AppColors.success;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: Radii.mdAll,
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              size: 20,
              color: color,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// Offers saving a pasted Xtream `get.php` link as an Xtream source.
class _ConvertCard extends StatelessWidget {
  const _ConvertCard({
    super.key,
    required this.focusNode,
    required this.onConvert,
  });

  final FocusNode focusNode;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: Radii.mdAll,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 20, color: AppColors.accent),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  l10n.sourcesXtreamLinkTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(l10n.sourcesXtreamLinkBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Spacing.md),
          TvButton(
            key: const ValueKey('convert-xtream'),
            focusNode: focusNode,
            icon: Icons.swap_horiz,
            label: l10n.sourcesXtreamLinkConvert,
            onSelect: onConvert,
          ),
        ],
      ),
    );
  }
}
