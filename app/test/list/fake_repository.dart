import 'dart:async';

import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';

/// An in-memory server. [online] false makes every call fail like a dropped
/// connection; [reject] makes the next send fail like a refused write.
class FakeRepository({List<Category>? categories}) implements ListRepository {
  this {
    this.categories =
        categories ??
        [
          const Category(id: 'produce', name: 'Obst & Gemüse', sortOrder: 10),
          const Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
          const Category(
            id: 'other',
            name: 'Sonstiges',
            sortOrder: 1000,
            seedKey: 'other',
          ),
        ];
  }

  late List<Category> categories;
  final rows = <String, Item>{};
  final sent = <ItemOp>[];
  var online = true;
  var reject = false;
  var _clock = DateTime.utc(2026, 10, 22, 12);
  void Function(Item item)? emitItem;
  void Function(String id)? emitDelete;
  void Function(ConnectionStatus status)? emitStatus;

  Completer<void>? gate;

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  String classify(String name) =>
      name.toLowerCase().contains('milch') ? 'chilled' : 'other';

  void _ensureOnline() {
    if (!online) {
      throw Exception('offline');
    }
  }

  @override
  Future<List<Category>> fetchCategories() async {
    _ensureOnline();
    return categories;
  }

  @override
  Future<List<Item>> fetchItems() async {
    _ensureOnline();
    return rows.values.toList();
  }

  @override
  Future<Item?> send(ItemOp op) async {
    await gate?.future;
    _ensureOnline();
    if (reject) {
      reject = false;
      throw const RejectedOp('denied');
    }
    sent.add(op);
    final current = rows[op.itemId];
    final next = switch (op) {
      AddItem(:final item) =>
        current ??
            Item(
              id: item.id,
              name: item.name,
              quantity: item.quantity,
              categoryId: item.categoryId ?? classify(item.name),
              status: item.status,
              createdAt: _tick(),
              updatedAt: _clock,
            ),
      _ => op.apply(current),
    };
    if (next == null) {
      rows.remove(op.itemId);
      return null;
    }
    final stamped = Item(
      id: next.id,
      name: next.name,
      quantity: next.quantity,
      categoryId: next.categoryId,
      status: next.status,
      createdAt: next.createdAt,
      updatedAt: _tick(),
      boughtAt: next.boughtAt,
    );
    rows[op.itemId] = stamped;
    return stamped;
  }

  @override
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id) onItemDeleted,
    required void Function() onCategoriesChanged,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    emitItem = onItem;
    emitDelete = onItemDeleted;
    emitStatus = onStatus;
    return () async {};
  }

  /// A change made by another household member.
  Item remoteAdd(String name, {String? categoryId}) {
    final item = Item(
      id: 'remote-${rows.length}',
      name: name,
      categoryId: categoryId ?? classify(name),
      status: ItemStatus.active,
      createdAt: _tick(),
      updatedAt: _clock,
    );
    rows[item.id] = item;
    return item;
  }
}
