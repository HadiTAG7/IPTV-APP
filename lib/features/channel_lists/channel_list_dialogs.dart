// Dialogs of the user's own channel lists, shared by Live, Favorites,
// Search and the player: "Add to list…", naming a list, deleting one.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/app_db.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../tv/tv_focusable.dart';
import '../../tv/tv_text_field.dart';
import '../../widgets/bidi_text.dart';
import '../settings/settings_dialogs.dart' show PrimaryBelowTraversalPolicy;

/// Longest list name the name dialog accepts.
const maxChannelListNameLength = 60;

/// "Add to list…" for the live channel [channelKey] of [sourceId]: lists the
/// source's channel lists, checked where the channel is in them. Picking a
/// list adds the channel to it, or removes it when it was there; "New
/// list…" asks for a name and creates a list holding the channel. A snack
/// bar tells what happened. Completes once everything is done or
/// dismissed.
Future<void> showAddToListDialog(
  BuildContext context,
  WidgetRef ref, {
  required int sourceId,
  required String channelKey,
}) async {
  // Read before the awaits: the caller may be gone when the dialogs close.
  final dao = ref.read(channelListsDaoProvider);
  final log = ref.read(ringLogProvider);
  final List<ChannelListRow> lists;
  final Set<int> member;
  try {
    lists = await dao.lists(sourceId);
    member = await dao.listsWithChannel(sourceId, channelKey);
  } on Object catch (e, st) {
    log.error('Reading the channel lists failed', e, st);
    if (context.mounted) _showSnack(context, null);
    return;
  }
  if (!context.mounted) return;
  final choice = await showDialog<AddToListChoice>(
    context: context,
    builder: (_) => AddToListDialog(lists: lists, member: member),
  );
  if (choice == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final list = choice.list;
  if (list == null) {
    final name = await showChannelListNameDialog(
      context,
      title: l10n.liveNewListTitle,
      confirmLabel: l10n.liveListCreate,
      save: (name) => dao.createList(sourceId, name, channels: [channelKey]),
    );
    if (name != null && context.mounted) {
      _showSnack(context, l10n.liveListAdded(name));
    }
    return;
  }
  try {
    final added = await dao.toggleChannel(list.id, channelKey);
    if (!context.mounted) return;
    _showSnack(
      context,
      added ? l10n.liveListAdded(list.name) : l10n.liveListRemoved(list.name),
    );
  } on Object catch (e, st) {
    log.error('Changing a channel list failed', e, st);
    if (context.mounted) _showSnack(context, null);
  }
}

/// Shows [message] (null: the generic error) in a short snack bar.
void _showSnack(BuildContext context, String? message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message ?? AppLocalizations.of(context).commonErrorGeneric,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
}

/// What [AddToListDialog] returns: a list to add the channel to (or remove
/// it from), or a new list ([list] null).
class AddToListChoice {
  const AddToListChoice.list(ChannelListRow this.list);
  const AddToListChoice.newList() : list = null;

  final ChannelListRow? list;
}

/// The list picker of [showAddToListDialog]: the source's [lists], checked
/// when in [member], then "New list…". The first entry has focus.
class AddToListDialog extends StatelessWidget {
  const AddToListDialog({super.key, required this.lists, required this.member});

  final List<ChannelListRow> lists;

  /// Ids of the lists holding the channel.
  final Set<int> member;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    Widget entry({
      required Key key,
      required bool autofocus,
      required String label,
      required Widget leading,
      required AddToListChoice choice,
      bool? checked,
      Widget? trailing,
    }) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xxs,
      ),
      child: TvFocusable(
        key: key,
        autofocus: autofocus,
        focusScale: 1.02,
        semanticLabel: label,
        onSelect: () => Navigator.of(context).pop(choice),
        child: Semantics(
          checked: checked,
          child: ListTile(
            leading: leading,
            title: BidiText(label),
            trailing: trailing,
          ),
        ),
      ),
    );
    return AlertDialog(
      title: Text(l10n.liveAddToListTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: Spacing.md),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, list) in lists.indexed)
                entry(
                  key: ValueKey('add-to-list-${list.id}'),
                  autofocus: i == 0,
                  label: list.name,
                  checked: member.contains(list.id),
                  leading: member.contains(list.id)
                      ? const Icon(
                          Icons.check_box_rounded,
                          color: AppColors.accent,
                        )
                      : const Icon(Icons.check_box_outline_blank_rounded),
                  trailing: Text(
                    '${list.count}',
                    textDirection: TextDirection.ltr,
                    style: theme.labelMedium,
                  ),
                  choice: AddToListChoice.list(list),
                ),
              entry(
                key: const ValueKey('add-to-list-new'),
                autofocus: lists.isEmpty,
                label: l10n.liveNewList,
                leading: const Icon(Icons.add_rounded),
                choice: const AddToListChoice.newList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('add-to-list-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}

/// Asks for a channel list name (starting with [initial]) and runs [save]
/// with it; completes with the trimmed name once saved, or null when
/// cancelled. A [ChannelListNameException] from [save] is shown under the
/// field and the dialog stays open.
Future<String?> showChannelListNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<void> Function(String name) save,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => ChannelListNameDialog(
    title: title,
    confirmLabel: confirmLabel,
    initial: initial,
    save: save,
  ),
);

/// The body of [showChannelListNameDialog]: a [TvTextField] (so the remote
/// reaches it without forcing the soft keyboard open), Cancel and
/// [confirmLabel]. Down from the field goes to [confirmLabel].
class ChannelListNameDialog extends ConsumerStatefulWidget {
  const ChannelListNameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.save,
    this.initial = '',
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final Future<void> Function(String name) save;

  @override
  ConsumerState<ChannelListNameDialog> createState() =>
      _ChannelListNameDialogState();
}

class _ChannelListNameDialogState extends ConsumerState<ChannelListNameDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection.collapsed(offset: widget.initial.length);
  final _fieldNode = FocusNode(debugLabel: 'channel list name');
  final _saveNode = FocusNode(debugLabel: 'channel list save');
  late final _policy = PrimaryBelowTraversalPolicy(
    from: [_fieldNode],
    primary: _saveNode,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _fieldNode.dispose();
    _saveNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.liveListNameEmpty);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await widget.save(name);
    } on ChannelListNameException catch (e) {
      error = switch (e.error) {
        ChannelListNameError.empty => l10n.liveListNameEmpty,
        ChannelListNameError.taken => l10n.liveListNameTaken,
      };
    } on Object catch (e, st) {
      if (mounted) {
        ref.read(ringLogProvider).error('Saving a channel list failed', e, st);
      }
      error = l10n.commonErrorGeneric;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(name);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialog = AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TvTextField(
          key: const ValueKey('channel-list-name-field'),
          controller: _controller,
          focusNode: _fieldNode,
          autofocus: true,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            LengthLimitingTextInputFormatter(maxChannelListNameLength),
          ],
          decoration: InputDecoration(
            labelText: l10n.liveListName,
            hintText: l10n.liveListNameHint,
            errorText: _error,
            errorMaxLines: 2,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('channel-list-name-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        // Stays enabled while saving (_submit ignores the press): a
        // disabled button gives up focus, which falls back to the field.
        FilledButton(
          key: const ValueKey('channel-list-name-save'),
          focusNode: _saveNode,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
    return FocusTraversalGroup(policy: _policy, child: dialog);
  }
}

/// Creates a channel list for [sourceId] after asking for its name; the new
/// list's id, or null when cancelled.
Future<int?> createChannelList(
  BuildContext context,
  WidgetRef ref,
  int sourceId,
) async {
  final dao = ref.read(channelListsDaoProvider);
  final l10n = AppLocalizations.of(context);
  int? id;
  await showChannelListNameDialog(
    context,
    title: l10n.liveNewListTitle,
    confirmLabel: l10n.liveListCreate,
    save: (name) async => id = await dao.createList(sourceId, name),
  );
  return id;
}

/// Renames [list] after asking for the new name; whether it was renamed.
Future<bool> renameChannelList(
  BuildContext context,
  WidgetRef ref,
  ChannelListRow list,
) async {
  final dao = ref.read(channelListsDaoProvider);
  final l10n = AppLocalizations.of(context);
  final name = await showChannelListNameDialog(
    context,
    title: l10n.liveRenameList,
    confirmLabel: l10n.commonSave,
    initial: list.name,
    save: (name) => dao.renameList(list.id, name),
  );
  return name != null;
}

/// Asks to confirm deleting [list] (Cancel has focus); true when confirmed.
/// The caller moves focus off the list's widgets, then deletes it.
Future<bool> confirmDeleteChannelList(
  BuildContext context,
  ChannelListRow list,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.liveDeleteList),
        content: Text(l10n.liveDeleteListConfirm(list.name)),
        actions: [
          TextButton(
            key: const ValueKey('delete-list-cancel'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const ValueKey('delete-list-confirm'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
