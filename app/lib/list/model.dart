import 'package:flutter/foundation.dart' show immutable;

enum ItemStatus() {
  active,
  bought,
}

@immutable
class const Category({
  required final String id,
  required final String name,
  required final int sortOrder,
  final String? seedKey,
}) {
  factory fromJson(Map<String, Object?> json) => Category(
    id: json['id']! as String,
    name: json['name']! as String,
    sortOrder: json['sort_order']! as int,
    seedKey: json['seed_key'] as String?,
  );
}

@immutable
class const Item({
  required final String id,
  required final String name,
  required final ItemStatus status,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final String? quantity,

  /// Null only while a new item waits for the server to classify it.
  final String? categoryId,
  final String? storeId,
  final DateTime? boughtAt,
}) {
  factory fromJson(Map<String, Object?> json) => Item(
    id: json['id']! as String,
    name: json['name']! as String,
    quantity: json['quantity'] as String?,
    categoryId: json['category_id'] as String?,
    storeId: json['store_id'] as String?,
    status: ItemStatus.values.byName(json['status']! as String),
    createdAt: DateTime.parse(json['created_at']! as String),
    updatedAt: DateTime.parse(json['updated_at']! as String),
    boughtAt: switch (json['bought_at']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
  );

  Item copyWith({
    String? name,
    String? Function()? quantity,
    String? categoryId,
    ItemStatus? status,
    DateTime? Function()? boughtAt,
  }) => Item(
    id: id,
    name: name ?? this.name,
    quantity: quantity == null ? this.quantity : quantity(),
    categoryId: categoryId ?? this.categoryId,
    storeId: storeId,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    boughtAt: boughtAt == null ? this.boughtAt : boughtAt(),
  );
}

/// A user's intent, applied optimistically on top of the server state until
/// the server acknowledges it. Every op is idempotent so it can be retried.
sealed class const ItemOp(final String itemId) {
  /// The item as the user should see it once this op lands.
  Item? apply(Item? current);
}

final class AddItem(final Item item) extends ItemOp {
  this : super(item.id);

  @override
  Item? apply(Item? current) => current ?? item;
}

final class const SetStatus(
  super.itemId,
  final ItemStatus status,
  final DateTime at,
) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    status: status,
    boughtAt: () => status == ItemStatus.bought ? at : null,
  );
}

final class const EditItem(
  super.itemId, {
  required final String name,
  required final String? quantity,
  required final String categoryId,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    name: name,
    quantity: () => quantity,
    categoryId: categoryId,
  );
}

final class const DeleteItem(super.itemId) extends ItemOp {
  @override
  Item? apply(Item? current) => null;
}

/// Server truth plus the pending ops folded on top: what the list shows.
Map<String, Item> visibleItems(
  Map<String, Item> server,
  Iterable<ItemOp> pending,
) {
  final view = Map.of(server);
  for (final op in pending) {
    final next = op.apply(view[op.itemId]);
    if (next == null) {
      view.remove(op.itemId);
    } else {
      view[op.itemId] = next;
    }
  }
  return view;
}

/// Merges a server row, ignoring echoes older than what is already known.
Map<String, Item> mergeServerRow(Map<String, Item> server, Item row) {
  final known = server[row.id];
  if (known != null && known.updatedAt.isAfter(row.updatedAt)) {
    return server;
  }
  return {...server, row.id: row};
}

@immutable
class const CategoryGroup(
  /// Null for items still being classified.
  final Category? category,
  final List<Item> items,
);

/// Active items grouped by category in route order; unclassified first.
List<CategoryGroup> groupActive(
  Iterable<Item> items,
  List<Category> categories,
) {
  final byCategory = <String?, List<Item>>{};
  for (final item in items.where((i) => i.status == ItemStatus.active)) {
    byCategory.putIfAbsent(item.categoryId, () => []).add(item);
  }
  for (final list in byCategory.values) {
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  final ordered = [...categories]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final known = {for (final c in ordered) c.id};
  final orphans = [
    for (final entry in byCategory.entries)
      if (entry.key != null && !known.contains(entry.key)) ...entry.value,
  ];
  return [
    if (byCategory[null] case final pending?) CategoryGroup(null, pending),
    for (final category in ordered)
      if (byCategory[category.id] case final list?)
        CategoryGroup(category, list),
    if (orphans.isNotEmpty) CategoryGroup(null, orphans),
  ];
}

/// Bought items, most recent first.
List<Item> recentlyBought(Iterable<Item> items, {int limit = 20}) {
  final bought = items.where((i) => i.status == ItemStatus.bought).toList()
    ..sort(
      (a, b) =>
          (b.boughtAt ?? b.updatedAt).compareTo(a.boughtAt ?? a.updatedAt),
    );
  return bought.take(limit).toList();
}
