import 'dart:convert';

import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 22, 12);
  final milk = Item(
    id: 'milk',
    name: 'Milch',
    quantity: '2',
    categoryId: 'chilled',
    storeId: 'lidl',
    status: ItemStatus.bought,
    createdAt: at,
    updatedAt: at.add(const Duration(minutes: 1)),
    boughtAt: at.add(const Duration(minutes: 1)),
  );
  final bread = Item(
    id: 'bread',
    name: 'Brot',
    status: ItemStatus.active,
    createdAt: DateTime(2026, 10, 22, 14),
    updatedAt: DateTime(2026, 10, 22, 14),
  );
  final snapshot = ListSnapshot(
    catalog: const Catalog(
      categories: [
        Category(id: 'chilled', name: 'Kühlregal', sortOrder: 30),
        Category(
          id: 'other',
          name: 'Sonstiges',
          sortOrder: 1000,
          seedKey: 'other',
        ),
      ],
      stores: [Store(id: 'lidl', name: 'Lidl', sortOrder: 20, seedKey: 'lidl')],
      layout: [
        StoreCategory(
          storeId: 'lidl',
          categoryId: 'other',
          sortOrder: 10,
          hidden: true,
        ),
      ],
    ),
    server: [milk],
    pending: [
      AddItem(bread),
      SetStatus('bread', ItemStatus.bought, at, storeId: 'lidl'),
      SetStatus('milk', ItemStatus.active, at),
      const EditItem(
        'milk',
        name: 'Hafermilch',
        quantity: null,
        categoryId: 'other',
        storeId: null,
      ),
      const MoveItem('bread', 'other'),
      const DeleteItem('milk'),
    ],
  );

  ListSnapshot roundTrip(ListSnapshot s) => ListSnapshot.fromJson(
    jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
  );

  test('a snapshot survives encoding, with every op kind', () {
    final back = roundTrip(snapshot);
    expect(back.toJson(), snapshot.toJson());
    expect(back.pending.map((op) => op.runtimeType), [
      AddItem,
      SetStatus,
      SetStatus,
      EditItem,
      MoveItem,
      DeleteItem,
    ]);
    expect(back.catalog.fallback?.id, 'other');
    expect(back.catalog.layout.single.hidden, isTrue);
    expect(back.server.single.boughtAt, milk.boughtAt);
    expect(back.server.single.createdAt.isUtc, isTrue);
    expect(back.pending.first.apply(null)!.createdAt, bread.createdAt);
  });

  test('folding the decoded ops shows the same list', () {
    Map<String, Item> visible(ListSnapshot s) => visibleItems({
      for (final item in s.server) item.id: item,
    }, s.pending.take(5));
    final before = visible(snapshot);
    final after = visible(roundTrip(snapshot));
    expect(after.keys, before.keys);
    expect(
      [for (final i in after.values) i.toJson()],
      [for (final i in before.values) i.toJson()],
    );
    expect(after['milk']!.name, 'Hafermilch');
    expect(after['bread']!.status, ItemStatus.bought);
  });

  test('another version or an unknown op is refused', () {
    final json = snapshot.toJson();
    expect(
      () => ListSnapshot.fromJson({...json, 'version': 0}),
      throwsFormatException,
    );
    expect(
      () => ItemOp.fromJson({'item_id': 'x', 'op': 'teleport'}),
      throwsFormatException,
    );
  });
}
