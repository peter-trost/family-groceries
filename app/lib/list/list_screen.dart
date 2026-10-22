import 'dart:async';

import 'package:family_groceries/household/invite_dialog.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The whole app for day-to-day use: add field on top, list beneath.
class const ListScreen({
  super.key,

  /// Overrides the Supabase repository, for tests.
  final ListRepository? repository,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final household = session.household;
    return BlocProvider(
      key: ValueKey(household.id),
      create: (_) => ListCubit(
        repository ??
            SupabaseListRepository(Supabase.instance.client, household.id),
      )..start(),
      child: ShoppingList(household: household),
    );
  }
}

class const ShoppingList({required final Household household, super.key})
    extends StatefulWidget {
  @override
  State<ShoppingList> createState() => _ShoppingListState();
}

class _ShoppingListState() extends State<ShoppingList> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<Rejected> _rejections;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ListCubit>();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(cubit.resync()),
    );
    _rejections = cubit.rejections.listen((r) {
      if (mounted) {
        _snack(AppLocalizations.of(context).syncFailed(r.itemName));
      }
    });
  }

  @override
  void dispose() {
    unawaited(_rejections.cancel());
    _lifecycle.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _snack(String text, {VoidCallback? undo}) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          persist: false,
          action: undo == null
              ? null
              : SnackBarAction(label: l10n.undo, onPressed: undo),
        ),
      );
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    switch (context.read<ListCubit>().add(_input.text)) {
      case Added():
        _input.clear();
      case AlreadyOnList(:final item):
        _input.clear();
        _snack(l10n.alreadyOnList(item.name));
      case NothingToAdd():
        break;
    }
    _inputFocus.requestFocus();
  }

  /// Acting on the list ends typing, which also drops the soft keyboard
  /// while ticking things off in the store.
  void _leaveField() => _inputFocus.unfocus();

  void _tick(Item item) {
    _leaveField();
    final cubit = context.read<ListCubit>()..tick(item.id);
    _snack(
      AppLocalizations.of(context).itemTicked(item.name),
      undo: () => cubit.untick(item.id),
    );
  }

  void _delete(Item item) {
    _leaveField();
    final cubit = context.read<ListCubit>()..delete(item.id);
    _snack(
      AppLocalizations.of(context).itemDeleted(item.name),
      undo: () => cubit.restore(item),
    );
  }

  void _readd(Item item) {
    _leaveField();
    context.read<ListCubit>().untick(item.id);
    _snack(AppLocalizations.of(context).itemReadded(item.name));
  }

  Future<void> _edit(Item item) async {
    _leaveField();
    final cubit = context.read<ListCubit>();
    final result = await showEditItemSheet(
      context,
      item: item,
      categories: cubit.state.categories,
    );
    switch (result) {
      case EditSaved(:final name, :final quantity, :final categoryId):
        cubit.edit(
          item.id,
          name: name,
          quantity: quantity,
          categoryId: categoryId,
        );
      case EditDeleted():
        _delete(item);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.household.name),
        actions: [
          const _SyncIndicator(),
          _Menu(household: widget.household),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Focus(
              // Hardware Enter (web, desktop): handled here, because Flutter
              // web's text-input action path blurs the field and leaves it
              // dead for the next Enter. Soft keyboards still submit below.
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                  _submit();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                autofocus: true,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.addFieldHint,
                  prefixIcon: const Icon(Icons.add_shopping_cart),
                  suffixIcon: IconButton(
                    tooltip: l10n.addButton,
                    icon: const Icon(Icons.send),
                    onPressed: _submit,
                  ),
                  border: const OutlineInputBorder(),
                ),
                // Keeps the soft keyboard up after submitting.
                onEditingComplete: () {},
                onTapOutside: (_) => _leaveField(),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<ListCubit, ListState>(
              builder: (context, state) => _ListBody(
                state: state,
                onTick: _tick,
                onEdit: (item) => unawaited(_edit(item)),
                onDelete: _delete,
                onReadd: _readd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _ListBody({
  required final ListState state,
  required final ValueChanged<Item> onTick,
  required final ValueChanged<Item> onEdit,
  required final ValueChanged<Item> onDelete,
  required final ValueChanged<Item> onReadd,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = state.items.values;
    final groups = groupActive(items, state.categories);
    final bought = recentlyBought(items);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              l10n.emptyList,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        for (final group in groups) ...[
          _GroupHeader(group.category?.name ?? l10n.sortingItem),
          for (final item in group.items)
            _ItemTile(
              key: ValueKey(item.id),
              item: item,
              onTick: () => onTick(item),
              onEdit: () => onEdit(item),
              onDelete: () => onDelete(item),
            ),
        ],
        if (bought.isNotEmpty)
          ExpansionTile(
            title: Text(l10n.recentlyBought),
            children: [
              for (final item in bought)
                ListTile(
                  key: ValueKey('bought-${item.id}'),
                  dense: true,
                  title: Text(
                    item.name,
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                  trailing: IconButton(
                    tooltip: l10n.readd,
                    icon: const Icon(Icons.add),
                    onPressed: () => onReadd(item),
                  ),
                  onTap: () => onReadd(item),
                ),
            ],
          ),
      ],
    );
  }
}

class const _GroupHeader(final String title) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class const _ItemTile({
  required final Item item,
  required final VoidCallback onTick,
  required final VoidCallback onEdit,
  required final VoidCallback onDelete,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quantity = item.quantity;
    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline),
          ),
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        // Unfocusable: on web a focused element that vanishes with its row
        // leaves the add field unable to take text on the next tap.
        leading: ExcludeFocus(
          child: Checkbox(
            value: false,
            semanticLabel: l10n.tickItem(item.name),
            onChanged: (_) => onTick(),
          ),
        ),
        title: Text(item.name),
        trailing: quantity == null ? null : Text(quantity),
        onTap: onEdit,
      ),
    );
  }
}

class const _SyncIndicator() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (connection, pending) = context
        .select<ListCubit, (ConnectionStatus, int)>(
          (c) => (c.state.connection, c.state.pending.length),
        );
    final message = switch ((connection, pending)) {
      (ConnectionStatus.offline, _) => l10n.offline,
      (_, > 0) => l10n.pendingChanges(pending),
      _ => null,
    };
    if (message != null) {
      return Tooltip(
        message: message,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            connection == ConnectionStatus.offline
                ? Icons.cloud_off
                : Icons.cloud_upload_outlined,
            semanticLabel: message,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

enum _MenuAction() {
  invite,
  join,
  signOut,
}

class const _Menu({required final Household household})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_MenuAction>(
      tooltip: l10n.menu,
      onSelected: (action) => unawaited(switch (action) {
        _MenuAction.invite => showInviteDialog(context, household),
        _MenuAction.join => showJoinCodeDialog(context),
        _MenuAction.signOut => context.read<SessionCubit>().signOut(),
      }),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _MenuAction.invite,
          child: Text(l10n.inviteMember),
        ),
        PopupMenuItem(
          value: _MenuAction.join,
          child: Text(l10n.joinOtherHousehold),
        ),
        PopupMenuItem(value: _MenuAction.signOut, child: Text(l10n.signOut)),
      ],
    );
  }
}
