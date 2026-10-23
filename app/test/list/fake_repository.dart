import 'dart:async';

import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';

/// An in-memory server. [online] false makes every call fail like a dropped
/// connection; [reject] makes the next write fail like a refused one.
/// Writes come from [me]; [remoteAdd] is Lea's by default.
///
/// Stores: Lidl walks the route backwards; dm does not carry produce or
/// chilled.
class FakeRepository() implements ListRepository {
  var categories = const [
    Category(id: 'produce', name: 'Obst & Gemüse', sortOrder: 10),
    Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
    Category(id: 'other', name: 'Sonstiges', sortOrder: 1000, seedKey: 'other'),
  ];
  var stores = const [
    Store(id: 'dm', name: 'dm', sortOrder: 10, seedKey: 'dm'),
    Store(id: 'lidl', name: 'Lidl', sortOrder: 20, seedKey: 'lidl'),
  ];
  var layout = const [
    StoreCategory(storeId: 'dm', categoryId: 'other', sortOrder: 10),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'produce',
      sortOrder: 20,
      hidden: true,
    ),
    StoreCategory(
      storeId: 'dm',
      categoryId: 'chilled',
      sortOrder: 30,
      hidden: true,
    ),
    StoreCategory(storeId: 'lidl', categoryId: 'other', sortOrder: 10),
    StoreCategory(storeId: 'lidl', categoryId: 'chilled', sortOrder: 20),
    StoreCategory(storeId: 'lidl', categoryId: 'produce', sortOrder: 30),
  ];
  var members = const [
    Member(id: 'peter', displayName: 'Peter'),
    Member(id: 'lea', displayName: 'Lea'),
  ];
  var me = 'peter';

  /// What suggest_items answers; [usualsFail] makes it fail on its own.
  var usuals = <Usual>[];
  var usualsFail = false;
  var usualsCalls = 0;

  /// When set, fetchUsuals waits for it, after the online check.
  Completer<void>? usualsGate;
  final rows = <String, Item>{};
  final sent = <ItemOp>[];

  /// Catalog writes, as `method(args)` strings.
  final catalogCalls = <String>[];
  var online = true;
  var reject = false;
  var _clock = DateTime.utc(2026, 10, 22, 12);
  void Function(Item item)? emitItem;
  void Function(String id)? emitDelete;
  void Function(ConnectionStatus status)? emitStatus;
  void Function()? emitCatalogChanged;

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
  Future<Catalog> fetchCatalog() async {
    _ensureOnline();
    return Catalog(
      categories: categories,
      stores: stores,
      layout: layout,
      members: members,
    );
  }

  void _writeCatalog(String call) {
    _ensureOnline();
    if (reject) {
      reject = false;
      throw const RejectedOp('denied');
    }
    catalogCalls.add(call);
  }

  @override
  Future<void> renameCategory(String id, String name) async {
    if (categories.any((c) => c.id != id && c.name == name)) {
      throw const RejectedOp('duplicate key', nameTaken: true);
    }
    _writeCatalog('rename($id, $name)');
    categories = Catalog(categories: categories).withName(id, name).categories;
  }

  @override
  Future<void> createCategory(String name) async {
    if (categories.any((c) => c.name == name)) {
      throw const RejectedOp('duplicate key', nameTaken: true);
    }
    _writeCatalog('create($name)');
    categories = [
      ...categories,
      Category(id: 'new-$name', name: name, sortOrder: 2000),
    ];
  }

  @override
  Future<void> reorderCategories(List<String> ids) async {
    _writeCatalog('reorder(${ids.join(', ')})');
    categories = Catalog(categories: categories).withRouteOrder(ids).categories;
  }

  @override
  Future<void> deleteCategory(String id, {String? reassignTo}) async {
    _writeCatalog('delete($id, $reassignTo)');
    final target = reassignTo ?? 'other';
    categories = [...categories.where((c) => c.id != id)];
    for (final item in [...rows.values]) {
      if (item.categoryId == id) {
        rows[item.id] = item.copyWith(categoryId: target);
      }
    }
  }

  @override
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) async {
    _writeCatalog(
      'layout($storeId: ${orderedIds.join(', ')}; ${hiddenIds.join(', ')})',
    );
    layout = Catalog(layout: layout)
        .withStoreLayout(storeId, orderedIds, hiddenIds)
        .layout;
  }

  @override
  Future<List<Item>> fetchItems() async {
    _ensureOnline();
    return rows.values.toList();
  }

  @override
  Future<List<Usual>> fetchUsuals() async {
    usualsCalls++;
    _ensureOnline();
    await usualsGate?.future;
    if (usualsFail) {
      throw Exception('suggest_items failed');
    }
    return usuals;
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
              storeId: item.storeId,
              status: item.status,
              createdAt: _tick(),
              updatedAt: _clock,
              addedBy: me,
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
      storeId: next.storeId,
      status: next.status,
      createdAt: next.createdAt,
      updatedAt: _tick(),
      boughtAt: next.boughtAt,
      addedBy: next.addedBy,
    );
    rows[op.itemId] = stamped;
    return stamped;
  }

  /// Stands in for the server's splitter: splits on commas and "und".
  @override
  Future<List<Entry>> splitSpoken(String text) async {
    _ensureOnline();
    return [
      for (final part in text.split(RegExp(r',|\bund\b')))
        if (part.trim().isNotEmpty) parseEntry(part),
    ];
  }

  @override
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id) onItemDeleted,
    required void Function() onCatalogChanged,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    emitItem = onItem;
    emitDelete = onItemDeleted;
    emitStatus = onStatus;
    emitCatalogChanged = onCatalogChanged;
    return () async {};
  }

  /// A change made by another household member.
  Item remoteAdd(
    String name, {
    String? categoryId,
    String? storeId,
    String? addedBy = 'lea',
  }) {
    final item = Item(
      id: 'remote-${rows.length}',
      name: name,
      categoryId: categoryId ?? classify(name),
      storeId: storeId,
      status: ItemStatus.active,
      createdAt: _tick(),
      updatedAt: _clock,
      addedBy: addedBy,
    );
    rows[item.id] = item;
    return item;
  }
}
