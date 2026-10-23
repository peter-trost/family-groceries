import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';

sealed class const EditResult();

final class const EditSaved({
  required final String name,
  required final String? quantity,
  required final String categoryId,

  /// Null: any store.
  required final String? storeId,
}) extends EditResult;

final class const EditDeleted() extends EditResult;

Future<EditResult?> showEditItemSheet(
  BuildContext context, {
  required Item item,
  required Catalog catalog,
}) => showModalBottomSheet<EditResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _EditItemSheet(item: item, catalog: catalog),
);

class const _EditItemSheet({
  required final Item item,
  required final Catalog catalog,
}) extends StatefulWidget {
  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState() extends State<_EditItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _quantity = TextEditingController(text: widget.item.quantity);
  late String? _categoryId = widget.item.categoryId;
  late String? _storeId =
      widget.catalog.stores.any((s) => s.id == widget.item.storeId)
      ? widget.item.storeId
      : null;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final categoryId = _categoryId;
    if (name.isEmpty || categoryId == null) {
      return;
    }
    final quantity = _quantity.text.trim();
    Navigator.of(context).pop(
      EditSaved(
        name: name,
        quantity: quantity.isEmpty ? null : quantity,
        categoryId: categoryId,
        storeId: _storeId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.editItem, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            maxLength: 120,
            decoration: InputDecoration(labelText: l10n.itemName),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: l10n.itemQuantity,
              hintText: l10n.itemQuantityHint,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: InputDecoration(labelText: l10n.itemCategory),
            items: [
              for (final category in widget.catalog.categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _storeId,
            decoration: InputDecoration(labelText: l10n.itemStore),
            items: [
              DropdownMenuItem(child: Text(l10n.anyStore)),
              for (final store in widget.catalog.stores)
                DropdownMenuItem(value: store.id, child: Text(store.name)),
            ],
            onChanged: (id) => setState(() => _storeId = id),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(const EditDeleted()),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.delete),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: Text(l10n.save)),
            ],
          ),
        ],
      ),
    );
  }
}
