import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/form_factor.dart';
import '../features/sources/widgets/tv_buttons.dart';
import '../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';
import '../tv/tv_text_field.dart';
import 'account_controller.dart';
import 'firebase_api.dart';
import 'firebase_config.dart';

Future<void> openAccountScreen(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute<void>(builder: (_) => const AccountScreen()));

/// While [signedOut], a failure comes from signing in or resetting the
/// password, never from sync, so unknown codes mean the account service
/// could not be reached; signed in, they stopped sync unless they clear by
/// themselves (see [accountErrorPasses]). [owner] is the email of the
/// account this device's data belongs to, when known.
String accountErrorText(
  AppLocalizations l,
  String code, {
  bool signedOut = false,
  String? owner,
}) => switch (code) {
  'FORM' => l.accountInvalidForm,
  'FORM_SIGN_IN' => l.accountInvalidSignIn,
  'FORM_EMAIL' => l.accountInvalidEmail,
  'EMAIL_EXISTS' => l.accountExists,
  'OTHER_ACCOUNT' when owner != null => l.accountOtherOwnerNamed(owner),
  'OTHER_ACCOUNT' => l.accountOtherOwner,
  'SESSION_STORAGE' => l.accountStorageFailed,
  'SESSION_EXPIRED' => l.accountSessionExpired,
  'PLAYLIST_FILE_MISSING' || 'PLAYLIST_FILE_TOO_LARGE' => l.accountFileError,
  'TOO_MANY_ATTEMPTS_TRY_LATER' ||
  'RESET_PASSWORD_EXCEED_LIMIT' => l.accountTooManyAttempts,
  'INVALID_LOGIN_CREDENTIALS' ||
  'INVALID_PASSWORD' ||
  'EMAIL_NOT_FOUND' ||
  'INVALID_EMAIL' ||
  'USER_DISABLED' ||
  'WEAK_PASSWORD' => l.accountAuthFailed,
  _ when signedOut => l.accountServiceUnavailable,
  'PERMISSION_DENIED' => l.accountSyncDenied,
  _ when !accountErrorPasses(code) => l.accountSyncBlocked,
  _ => l.accountSyncFailed,
};

/// Whether sync failed with [code] for a reason that clears by itself (the
/// connection, the service, another device writing at the same time); any
/// other failure stops sync until it is dealt with.
bool accountErrorPasses(String code) => const {
  'NETWORK_ERROR',
  'UNAVAILABLE',
  'DEADLINE_EXCEEDED',
  'INTERNAL',
  'RESOURCE_EXHAUSTED',
  'CONFLICT',
}.contains(code);

/// Asks before [AccountController.switchAccount]; pops true to switch.
/// Cancel has the focus, so a stray OK never switches.
class SwitchAccountDialog extends StatelessWidget {
  const SwitchAccountDialog({super.key, this.owner});

  /// The email of the account this device's data belongs to, when known.
  final String? owner;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final owner = this.owner;
    // The longest text of the app's dialogs: at a large font size it
    // scrolls rather than lose its end.
    return AlertDialog(
      scrollable: true,
      title: Text(l.accountSwitchTitle),
      content: Text(
        owner == null ? l.accountSwitchBodyUnnamed : l.accountSwitchBody(owner),
      ),
      actions: [
        TextButton(
          key: const ValueKey('account-switch-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.commonCancel),
        ),
        TextButton(
          key: const ValueKey('account-switch-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.accountSwitchConfirm),
        ),
      ],
    );
  }
}

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _submitNode = FocusNode(debugLabel: 'account-submit');
  bool _create = false;
  bool _busy = false;
  String? _error;
  String? _message;

  /// The feedback last shown, to notice when it changes.
  (String?, String?) _shown = (null, null);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _submitNode.dispose();
    super.dispose();
  }

  bool get _validEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());

  /// The email of the account this device's data belongs to, but not when
  /// it is the one entered: another account has it now (the first one was
  /// deleted), and naming it would contradict the message.
  String? _ownerOf(AccountView account) {
    final owner = account.owner;
    return owner?.toLowerCase() == _email.text.trim().toLowerCase()
        ? null
        : owner;
  }

  /// Feedback appears above the buttons after the one pressed, so a focused
  /// button there moves down: scroll it back into view, as nothing else
  /// does while the focus stays put.
  void _keepFocusVisible() {
    if (!mounted ||
        FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null || !focused.mounted) return;
    if (Scrollable.maybeOf(focused) == null) return;
    unawaited(
      Scrollable.ensureVisible(
        focused,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: FocusTokens.scrollOf(context),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } on Object {
      if (mounted) setState(() => _error = 'SYNC_ERROR');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Signs in, or with [move] moves this device to the account entered
  /// (see [AccountController.switchAccount]).
  void _authenticate({bool move = false}) {
    if (!_validEmail ||
        _password.text.length < (_create ? 8 : 1) ||
        (_create && _confirm.text != _password.text)) {
      setState(() => _error = _create ? 'FORM' : 'FORM_SIGN_IN');
      return;
    }
    unawaited(
      _run(() async {
        final account = ref.read(accountControllerProvider);
        final authenticate = move
            ? account.switchAccount
            : account.authenticate;
        await authenticate(_email.text, _password.text, create: _create);
        _password.clear();
        _confirm.clear();
      }),
    );
  }

  /// After a confirmation, moves this device to the account entered, from
  /// the submit button, where its progress and result show.
  Future<void> _switchAccount(String? owner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SwitchAccountDialog(owner: owner),
    );
    if (confirmed != true || !mounted) return;
    _submitNode.requestFocus();
    _authenticate(move: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final account = ref.watch(accountViewProvider).value ?? const AccountView();
    final busy = _busy || account.busy;
    final error = _error ?? account.error;
    final tv = FormFactorScope.isTv(context);
    if ((error, _message) != _shown) {
      _shown = (error, _message);
      WidgetsBinding.instance.addPostFrameCallback((_) => _keepFocusVisible());
    }
    // Right under the button just pressed: on a TV the remote cannot scroll
    // to text below the last control.
    final feedback = [
      if (error != null) ...[
        const SizedBox(height: Spacing.md),
        Semantics(
          key: const ValueKey('account-error'),
          liveRegion: true,
          child: Text(
            accountErrorText(
              l,
              error,
              signedOut: account.email == null,
              owner: _ownerOf(account),
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        // Signing in with another account: the way to move this device to
        // it, after saying what happens to its data.
        if (error == 'OTHER_ACCOUNT' && account.email == null) ...[
          const SizedBox(height: Spacing.sm),
          TvButton(
            key: const ValueKey('account-switch'),
            label: l.accountSwitch,
            busy: busy,
            onSelect: () => unawaited(_switchAccount(_ownerOf(account))),
          ),
        ],
      ],
      if (_message != null) ...[
        const SizedBox(height: Spacing.md),
        Semantics(
          key: const ValueKey('account-message'),
          liveRegion: true,
          child: Text(_message!),
        ),
      ],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountTitle),
        automaticallyImplyLeading: !tv,
        titleSpacing: tv ? TvLayout.overscanHorizontal : null,
        toolbarHeight: tv
            ? kToolbarHeight + TvLayout.overscanVertical * 2
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: overscanPadding(FormFactorScope.of(context)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.lg),
                child: FocusTraversalGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.cloud_sync_outlined,
                        size: 40,
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(l.accountIntro),
                      const SizedBox(height: Spacing.lg),
                      if (!FirebaseConfig.enabled)
                        Text(l.accountNotConfigured)
                      else if (account.email == null) ...[
                        TvTextField(
                          key: const ValueKey('account-email'),
                          controller: _email,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: l.accountEmail,
                          ),
                        ),
                        const SizedBox(height: Spacing.md),
                        TvTextField(
                          key: const ValueKey('account-password'),
                          controller: _password,
                          obscureText: true,
                          textDirection: TextDirection.ltr,
                          autofillHints: [
                            _create
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          textInputAction: _create
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_create) _authenticate();
                          },
                          decoration: InputDecoration(
                            labelText: l.accountPassword,
                          ),
                        ),
                        if (_create) ...[
                          const SizedBox(height: Spacing.md),
                          TvTextField(
                            key: const ValueKey('account-confirm'),
                            controller: _confirm,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _authenticate(),
                            decoration: InputDecoration(
                              labelText: l.accountConfirmPassword,
                            ),
                          ),
                        ],
                        const SizedBox(height: Spacing.lg),
                        TvButton(
                          key: const ValueKey('account-submit'),
                          focusNode: _submitNode,
                          label: _create ? l.accountCreate : l.accountSignIn,
                          onSelect: _authenticate,
                          primary: true,
                          busy: busy,
                          expand: true,
                        ),
                        ...feedback,
                        const SizedBox(height: Spacing.sm),
                        TvButton(
                          key: const ValueKey('account-toggle'),
                          label: _create
                              ? l.accountHaveAccount
                              : l.accountNeedAccount,
                          onSelect: () {
                            if (!busy) {
                              setState(() {
                                _create = !_create;
                                _error = null;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: Spacing.sm),
                        TvButton(
                          key: const ValueKey('account-reset'),
                          label: l.accountReset,
                          busy: busy,
                          onSelect: () {
                            if (!_validEmail) {
                              setState(() {
                                _error = 'FORM_EMAIL';
                                _message = null;
                              });
                              return;
                            }
                            unawaited(
                              _run(() async {
                                await ref
                                    .read(accountControllerProvider)
                                    .api
                                    .resetPassword(_email.text);
                                if (mounted) {
                                  setState(() => _message = l.accountResetSent);
                                }
                              }),
                            );
                          },
                        ),
                      ] else ...[
                        Text(
                          account.email!,
                          textDirection: TextDirection.ltr,
                          // Aligned to the start edge like the lines below.
                          textAlign:
                              Directionality.of(context) == TextDirection.rtl
                              ? TextAlign.right
                              : TextAlign.left,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          account.busy
                              ? l.accountSyncing
                              : account.lastSync != null && error == null
                              ? l.accountSynced
                              : l.accountWaiting,
                        ),
                        const SizedBox(height: Spacing.lg),
                        TvButton(
                          key: const ValueKey('account-sync'),
                          label: l.accountSyncNow,
                          icon: Icons.sync,
                          primary: true,
                          autofocus: true,
                          busy: busy,
                          onSelect: () => unawaited(
                            _run(
                              () => ref
                                  .read(accountControllerProvider)
                                  .sync(force: true),
                            ),
                          ),
                        ),
                        ...feedback,
                        const SizedBox(height: Spacing.lg),
                        Text(
                          l.accountLocalData,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: Spacing.sm),
                        TvButton(
                          key: const ValueKey('account-sign-out'),
                          label: l.accountSignOut,
                          // Not while a poll runs: signing out waits for it.
                          busy: _busy,
                          onSelect: () => unawaited(
                            _run(
                              () =>
                                  ref.read(accountControllerProvider).signOut(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
