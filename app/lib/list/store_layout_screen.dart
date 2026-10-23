import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Opens the walking-order editor for one store on top of the list.
Future<void> openStoreLayout(BuildContext context, String storeId) {
  final cubit = context.read<ListCubit>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: StoreLayoutScreen(storeId: storeId),
      ),
    ),
  );
}

/// One store's walking order and which categories it carries. Every change
/// saves at once.
class const StoreLayoutScreen({required final String storeId, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final catalog = context.select<ListCubit, Catalog>((c) => c.state.catalog);
    final storeName = catalog.store(storeId)?.name ?? '';
    final stops = walkingOrder(catalog, AtStore(storeId));

    void save(List<Stop> next) => unawaited(
      cubit.setStoreLayout(
        storeId,
        [for (final s in next) s.category.id],
        {
          for (final s in next)
            if (s.hidden) s.category.id,
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.storeLayoutTitle(storeName))),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(l10n.storeLayoutHint),
        ),
        itemCount: stops.length,
        onReorderItem: (from, to) {
          final next = [...stops];
          next.insert(to, next.removeAt(from));
          save(next);
        },
        itemBuilder: (context, index) {
          final (:category, :hidden) = stops[index];
          return ListTile(
            key: ValueKey(category.id),
            title: Text(category.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: l10n.storeCarries(category.name, storeName),
                  child: Switch(
                    value: !hidden,
                    onChanged: (carried) => save([
                      for (final s in stops)
                        if (s.category.id == category.id)
                          (category: category, hidden: !carried)
                        else
                          s,
                    ]),
                  ),
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
