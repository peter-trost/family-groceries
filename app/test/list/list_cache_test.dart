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
    addedBy: 'lea',
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
      members: [
        Member(id: 'peter', displayName: 'Peter'),
        Member(id: 'lea', displayName: 'Lea'),
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
    usuals: const [
      Usual(name: 'Gurken', quantity: '2', due: true),
      Usual(name: 'Brot', due: false),
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
    expect(back.server.single.addedBy, 'lea');
    expect(
      [for (final m in back.catalog.members) m.displayName],
      ['Peter', 'Lea'],
    );
    expect(
      [for (final u in back.usuals) (u.name, u.quantity, u.due)],
      [('Gurken', '2', true), ('Brot', null, false)],
    );
  });

  test('a version 1 snapshot loads with its queued ops', () {
    // As the app before who-added and usuals wrote it.
    const v1 = '''
{"version":1,
 "catalog":{"categories":[{"id":"chilled","name":"Kühlregal","sort_order":30,"seed_key":null}],
            "stores":[],"layout":[]},
 "server":[{"id":"milk","name":"Milch","quantity":null,"category_id":"chilled",
            "store_id":null,"status":"active","created_at":"2026-10-22T12:00:00.000Z",
            "updated_at":"2026-10-22T12:00:00.000Z","bought_at":null}],
 "pending":[{"item_id":"bread","op":"add","item":{"id":"bread","name":"Brot",
              "quantity":"2","category_id":null,"store_id":null,"status":"active",
              "created_at":"2026-10-22T12:01:00.000Z",
              "updated_at":"2026-10-22T12:01:00.000Z","bought_at":null}},
            {"item_id":"milk","op":"status","status":"bought",
             "at":"2026-10-22T12:02:00.000Z","store_id":null}]}''';
    final loaded = ListSnapshot.fromJson(
      jsonDecode(v1) as Map<String, Object?>,
    );
    expect(loaded.pending.map((op) => op.runtimeType), [AddItem, SetStatus]);
    expect(loaded.server.single.addedBy, isNull);
    expect(loaded.catalog.members, isEmpty);
    expect(loaded.usuals, isEmpty);
    final visible = visibleItems({
      for (final item in loaded.server) item.id: item,
    }, loaded.pending);
    expect(visible['bread']!.quantity, '2');
    expect(visible['milk']!.status, ItemStatus.bought);
    expect(roundTrip(loaded).toJson(), loaded.toJson());
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

  test('an unknown version or op is refused', () {
    final json = snapshot.toJson();
    expect(
      () => ListSnapshot.fromJson({...json, 'version': 0}),
      throwsFormatException,
    );
    expect(
      () =>
          ListSnapshot.fromJson({...json, 'version': ListSnapshot.version + 1}),
      throwsFormatException,
      reason: 'a downgraded app cannot read a newer snapshot',
    );
    expect(
      () => ItemOp.fromJson({'item_id': 'x', 'op': 'teleport'}),
      throwsFormatException,
    );
  });
}
