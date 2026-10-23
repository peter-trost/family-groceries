import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the category management screen on top of the list.
Future<void> openCategories(BuildContext context) {
  final cubit = context.read<ListCubit>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          BlocProvider.value(value: cubit, child: const CategoriesScreen()),
    ),
  );
}

/// The route order: reorder, rename, add and delete categories.
class const CategoriesScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final catalog = context.select<ListCubit, Catalog>((c) => c.state.catalog);
    final categories = catalog.categories;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoriesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await showNameDialog(
            context,
            title: l10n.addCategory,
            confirm: l10n.save,
          );
          if (name != null) {
            await cubit.createCategory(name);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.addCategory),
      ),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(bottom: 96),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(l10n.categoriesHint),
        ),
        itemCount: categories.length,
        onReorderItem: (from, to) {
          final ids = [for (final c in categories) c.id];
          ids.insert(to, ids.removeAt(from));
          unawaited(cubit.reorderCategories(ids));
        },
        itemBuilder: (context, index) {
          final category = categories[index];
          return ListTile(
            key: ValueKey(category.id),
            title: Text(category.name),
            onTap: () async {
              final name = await showNameDialog(
                context,
                title: l10n.renameCategory,
                confirm: l10n.save,
                initial: category.name,
              );
              if (name != null && name != category.name) {
                await cubit.renameCategory(category.id, name);
              }
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (category.seedKey != 'other')
                  IconButton(
                    tooltip: l10n.deleteCategory(category.name),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final target = await _askReassignTarget(
                        context,
                        category,
                        catalog,
                      );
                      if (target != null) {
                        await cubit.deleteCategory(
                          category.id,
                          reassignTo: target,
                        );
                      }
                    },
                  ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    // Its own node: merged into the row, its label would
                    // rename the row.
                    child: Semantics(
                      container: true,
                      child: Icon(
                        Icons.drag_handle,
                        semanticLabel: l10n.dragCategory(category.name),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Asks for a category name; null when cancelled or left empty.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String confirm,
  String initial = '',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) =>
        _NameDialog(title: title, confirm: confirm, initial: initial),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class const _NameDialog({
  required final String title,
  required final String confirm,
  required final String initial,
}) extends StatefulWidget {
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState() extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_name.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: l10n.categoryName),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}

/// Where the deleted category's items go; null when cancelled.
Future<String?> _askReassignTarget(
  BuildContext context,
  Category category,
  Catalog catalog,
) => showDialog<String>(
  context: context,
  builder: (_) => _DeleteDialog(category: category, catalog: catalog),
);

class const _DeleteDialog({
  required final Category category,
  required final Catalog catalog,
}) extends StatefulWidget {
  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState() extends State<_DeleteDialog> {
  late String? _target = widget.catalog.fallback?.id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = _target;
    return AlertDialog(
      title: Text(l10n.deleteCategory(widget.category.name)),
      content: DropdownButtonFormField<String>(
        initialValue: target,
        isExpanded: true,
        decoration: InputDecoration(labelText: l10n.moveItemsTo),
        items: [
          for (final c in widget.catalog.categories)
            if (c.id != widget.category.id)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
        ],
        onChanged: (id) => setState(() => _target = id),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: target == null
              ? null
              : () => Navigator.of(context).pop(target),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}
