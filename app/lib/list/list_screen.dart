import 'dart:async';

import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/household/invite_dialog.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/categories_screen.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/edit_item_sheet.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_layout_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The whole app for day-to-day use: add field on top, list beneath.
class const ListScreen({
  super.key,

  /// Overrides the Supabase repository, for tests.
  final ListRepository? repository,
}) extends StatelessWidget {
  /// The web build has no on-device recognizer; typing is the fallback.
  static final Dictation? _dictation = kIsWeb ? null : DeviceDictation();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! InHousehold) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final household = session.household;
    return BlocProvider(
      key: ValueKey(household.id),
      create: (context) => ListCubit(
        repository ??
            SupabaseListRepository(Supabase.instance.client, household.id),
        context.read<DeviceCache>().list(session.userId, household.id),
      )..start(),
      child: ShoppingList(household: household, dictation: _dictation),
    );
  }
}

class const ShoppingList({
  required final Household household,

  /// Null hides the microphone button.
  final Dictation? dictation,
  super.key,
}) extends StatefulWidget {
  @override
  State<ShoppingList> createState() => _ShoppingListState();
}

class _ShoppingListState() extends State<ShoppingList> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<Rejected> _rejections;
  var _listening = false;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ListCubit>();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(cubit.resync()),
    );
    _rejections = cubit.rejections.listen((rejection) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      _snack(switch (rejection) {
        ItemRejected(:final itemName) => l10n.syncFailed(itemName),
        NameTaken(:final name) => l10n.categoryNameTaken(name),
        CatalogRejected() => l10n.catalogSaveFailed,
      });
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

  /// Fills the field while the user speaks, then adds what the server's
  /// splitter makes of the sentence. On failure the text stays in the field.
  Future<void> _dictate(Dictation dictation) async {
    if (_listening) {
      await dictation.stop();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    if (!await dictation.prepare()) {
      if (mounted) {
        _snack(l10n.dictationUnavailable);
      }
      return;
    }
    setState(() => _listening = true);
    final text = await dictation.listen(
      onWords: (words) => _input.text = words,
    );
    if (!mounted) {
      return;
    }
    setState(() => _listening = false);
    if (text == null) {
      _snack(l10n.dictationNothingHeard);
      return;
    }
    try {
      final results = await cubit.addSpoken(text);
      if (!mounted) {
        return;
      }
      if (results.isEmpty) {
        _snack(l10n.dictationNothingUnderstood);
      } else {
        _input.clear();
        _snack(_dictationSummary(l10n, results));
      }
    } on Exception {
      if (mounted) {
        _snack(l10n.dictationSplitFailed);
      }
    }
    _inputFocus.requestFocus();
  }

  static String _dictationSummary(
    AppLocalizations l10n,
    List<AddResult> results,
  ) {
    final added = [
      for (final result in results)
        if (result case Added(:final item))
          [?item.quantity, item.name].join(' '),
    ];
    final existing = [
      for (final result in results)
        if (result case AlreadyOnList(:final item)) item.name,
    ];
    return [
      if (added.isNotEmpty) l10n.dictationAdded(added.join(', ')),
      if (existing.isNotEmpty) l10n.dictationAlreadyOnList(existing.join(', ')),
    ].join(' ');
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
      catalog: cubit.state.catalog,
    );
    switch (result) {
      case EditSaved(
        :final name,
        :final quantity,
        :final categoryId,
        :final storeId,
      ):
        cubit.edit(
          item.id,
          name: name,
          quantity: quantity,
          categoryId: categoryId,
          storeId: storeId,
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
                final enter =
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (!enter || event is KeyUpEvent) {
                  return KeyEventResult.ignored;
                }
                if (event is KeyDownEvent) {
                  _submit();
                }
                return KeyEventResult.handled;
              },
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                autofocus: true,
                // The server caps names at 120 characters.
                maxLength: 120,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _listening
                      ? l10n.dictationListening
                      : l10n.addFieldHint,
                  prefixIcon: const Icon(Icons.add_shopping_cart),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.dictation case final dictation?)
                        IconButton(
                          key: const ValueKey('dictation-button'),
                          tooltip: _listening
                              ? l10n.dictationStop
                              : l10n.dictationStart,
                          icon: Icon(
                            _listening ? Icons.stop_circle : Icons.mic,
                          ),
                          color: _listening
                              ? Theme.of(context).colorScheme.error
                              : null,
                          onPressed: () => unawaited(_dictate(dictation)),
                        ),
                      IconButton(
                        tooltip: l10n.addButton,
                        icon: const Icon(Icons.send),
                        onPressed: _submit,
                      ),
                    ],
                  ),
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
                // Keeps the soft keyboard up after submitting.
                onEditingComplete: () {},
                onTapOutside: (_) => _leaveField(),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const _StorePicker(),
          Expanded(
            child: BlocBuilder<ListCubit, ListState>(
              builder: (context, state) => _ListBody(
                state: state,
                onTick: _tick,
                onMove: (item, categoryId) =>
                    context.read<ListCubit>().move(item.id, categoryId),
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

/// "Alle" plus one chip per store; the list is sorted for the chosen one.
class const _StorePicker() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final (stores, filter) = context
        .select<ListCubit, (List<Store>, StoreFilter)>(
          (c) => (c.state.catalog.stores, c.state.filter),
        );
    if (stores.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = switch (filter) {
      AtStore(:final storeId) =>
        stores.where((s) => s.id == storeId).firstOrNull,
      AllStores() => null,
    };
    Widget chip(String label, StoreFilter target, {required bool selected}) =>
        ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => cubit.selectStore(target),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  chip(
                    l10n.allStores,
                    const AllStores(),
                    selected: current == null,
                  ),
                  for (final store in stores)
                    chip(
                      store.name,
                      AtStore(store.id),
                      selected: current?.id == store.id,
                    ),
                ],
              ),
            ),
          ),
          if (current != null)
            IconButton(
              tooltip: l10n.editStoreLayout,
              icon: const Icon(Icons.low_priority),
              onPressed: () => unawaited(openStoreLayout(context, current.id)),
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
  required final void Function(Item item, String categoryId) onMove,
}) extends StatefulWidget {
  @override
  State<_ListBody> createState() => _ListBodyState();
}

class _ListBodyState() extends State<_ListBody> {
  /// While an item is dragged, every category is a drop target.
  var _dragging = false;

  void _setDragging(bool dragging) {
    if (mounted && _dragging != dragging) {
      setState(() => _dragging = dragging);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = state.items.values;
    final grouping = groupActive(
      items,
      state.catalog,
      state.filter,
      showHidden: state.showHidden,
      includeEmpty: _dragging,
    );
    final storeName = switch (state.filter) {
      AtStore(:final storeId) => state.catalog.store(storeId)?.name,
      AllStores() => null,
    };
    final bought = recentlyBought(items);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (grouping.groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              storeName == null ? l10n.emptyList : l10n.emptyAtStore(storeName),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        for (final group in grouping.groups)
          _DropGroup(
            key: ValueKey(
              'group-${group.category?.id ?? group.items.first.id}',
            ),
            title: group.category?.name ?? l10n.sortingItem,
            categoryId: group.category?.id,
            onMove: widget.onMove,
            children: [
              for (final item in group.items)
                _ItemTile(
                  key: ValueKey(item.id),
                  item: item,
                  onTick: () => widget.onTick(item),
                  onEdit: () => widget.onEdit(item),
                  onDelete: () => widget.onDelete(item),
                  onDragging: _setDragging,
                ),
            ],
          ),
        if (storeName != null && grouping.hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: TextButton(
              onPressed: () => context.read<ListCubit>().toggleShowHidden(),
              child: Text(
                state.showHidden
                    ? l10n.hideHiddenItems(grouping.hiddenCount, storeName)
                    : l10n.showHiddenItems(grouping.hiddenCount, storeName),
                textAlign: TextAlign.center,
              ),
            ),
          ),
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
                    onPressed: () => widget.onReadd(item),
                  ),
                  onTap: () => widget.onReadd(item),
                ),
            ],
          ),
      ],
    );
  }
}

/// A header and its items; for a real category, also a drop target that
/// moves a dragged item into it.
class const _DropGroup({
  required final String title,
  required final String? categoryId,
  required final void Function(Item item, String categoryId) onMove,
  required final List<Widget> children,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final target = categoryId;
    Widget column({required bool hovered}) => ColoredBox(
      color: hovered
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_GroupHeader(title), ...children],
      ),
    );
    if (target == null) {
      return column(hovered: false);
    }
    return DragTarget<Item>(
      onWillAcceptWithDetails: (details) => details.data.categoryId != target,
      onAcceptWithDetails: (details) => onMove(details.data, target),
      builder: (context, candidates, _) =>
          column(hovered: candidates.isNotEmpty),
    );
  }
}

class const _GroupHeader(final String title) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Its own node: a group is one list child, and without a container the
    // header merges into the first item's button.
    return Semantics(
      container: true,
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
  required final ValueChanged<bool> onDragging,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Its own node, so a group's only item does not become the parent of
    // the group heading.
    final tile = Semantics(container: true, child: _tile(context));
    // Long press, so scrolling, tapping and swiping keep working.
    return LongPressDraggable<Item>(
      data: item,
      onDragStarted: () => onDragging(true),
      onDragEnd: (_) => onDragging(false),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(item.name, style: theme.textTheme.bodyLarge),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Widget _tile(BuildContext context) {
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
        trailing: quantity == null
            ? null
            : Text(quantity, style: Theme.of(context).textTheme.bodyMedium),
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
  categories,
  invite,
  join,
  access,
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
        _MenuAction.categories => openCategories(context),
        _MenuAction.invite => showInviteDialog(context, household),
        _MenuAction.join => showJoinCodeDialog(context),
        _MenuAction.access => context.push(settingsPath),
        _MenuAction.signOut => context.read<SessionCubit>().signOut(),
      }),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _MenuAction.categories,
          child: Text(l10n.manageCategories),
        ),
        PopupMenuItem(
          value: _MenuAction.invite,
          child: Text(l10n.inviteMember),
        ),
        PopupMenuItem(
          value: _MenuAction.join,
          child: Text(l10n.joinOtherHousehold),
        ),
        PopupMenuItem(value: _MenuAction.access, child: Text(l10n.accessTitle)),
        PopupMenuItem(value: _MenuAction.signOut, child: Text(l10n.signOut)),
      ],
    );
  }
}
