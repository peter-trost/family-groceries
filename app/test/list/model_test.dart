import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

Item item(
  String id, {
  String? category = 'a',
  String? store,
  ItemStatus status = ItemStatus.active,
  int at = 0,
  int updated = 0,
  String? by,
}) => Item(
  id: id,
  name: id,
  categoryId: category,
  storeId: store,
  status: status,
  createdAt: DateTime.utc(2026).add(Duration(minutes: at)),
  updatedAt: DateTime.utc(2026).add(Duration(minutes: updated)),
  boughtAt: status == ItemStatus.bought
      ? DateTime.utc(2026).add(Duration(minutes: at))
      : null,
  addedBy: by,
);

Duration minutes(int n) => Duration(minutes: n);

void main() {
  const categories = [
    Category(id: 'b', name: 'B', sortOrder: 20),
    Category(id: 'a', name: 'A', sortOrder: 10),
  ];

  test('pending ops fold over server rows in order', () {
    final server = {'x': item('x'), 'y': item('y')};
    final view = visibleItems(server, [
      SetStatus('x', ItemStatus.bought, DateTime.utc(2026)),
      const DeleteItem('y'),
      AddItem(item('z')),
      const EditItem(
        'z',
        name: 'Zitronen',
        quantity: '3',
        categoryId: 'b',
        storeId: null,
      ),
    ]);
    expect(view['x']!.status, ItemStatus.bought);
    expect(view.containsKey('y'), isFalse);
    expect(view['z']!.name, 'Zitronen');
    expect(view['z']!.quantity, '3');
    expect(view['z']!.categoryId, 'b');
    expect(server['x']!.status, ItemStatus.active, reason: 'server untouched');
  });

  test('an add of a row the server already has keeps the server row', () {
    final server = {'x': item('x', category: 'b')};
    expect(visibleItems(server, [AddItem(item('x'))])['x']!.categoryId, 'b');
  });

  test('stale echoes do not overwrite newer rows', () {
    final server = {'x': item('x', updated: 5)};
    final stale = item('x', status: ItemStatus.bought, updated: 4);
    expect(mergeServerRow(server, stale), same(server));
    final fresh = item('x', status: ItemStatus.bought, updated: 6);
    expect(mergeServerRow(server, fresh)['x']!.status, ItemStatus.bought);
  });

  test('groups follow category sort order; unclassified items lead', () {
    final groups = groupActive(
      [
        item('b1', category: 'b', at: 1),
        item('a2', at: 2),
        item('a1', at: 1),
        item('new', category: null),
        item('gone', status: ItemStatus.bought),
        item('orphan', category: 'deleted-category'),
      ],
      const Catalog(categories: categories),
      const AllStores(),
    ).groups;
    expect([for (final g in groups) g.category?.id], [null, 'a', 'b', null]);
    expect([for (final i in groups[1].items) i.id], ['a1', 'a2']);
    expect(groups.last.items.single.id, 'orphan');
  });

  test('ticking at a store tags the item; ticking in "Alle" keeps its tag', () {
    final at = DateTime.utc(2026);
    final tagged = {'x': item('x', store: 'dm')};
    final atLidl = SetStatus('x', ItemStatus.bought, at, storeId: 'lidl');
    expect(visibleItems(tagged, [atLidl])['x']!.storeId, 'lidl');
    final anywhere = SetStatus('x', ItemStatus.bought, at);
    expect(visibleItems(tagged, [anywhere])['x']!.storeId, 'dm');
  });

  test('an edit sets or clears the store tag', () {
    final server = {'x': item('x', store: 'dm')};
    EditItem edit(String? store) => EditItem(
      'x',
      name: 'x',
      quantity: null,
      categoryId: 'a',
      storeId: store,
    );
    expect(visibleItems(server, [edit('lidl')])['x']!.storeId, 'lidl');
    expect(visibleItems(server, [edit(null)])['x']!.storeId, isNull);
  });

  test('a move changes only the category', () {
    final server = {'x': item('x', store: 'dm', at: 3)};
    final moved = visibleItems(server, [const MoveItem('x', 'b')])['x']!;
    expect(moved.categoryId, 'b');
    expect(moved.storeId, 'dm');
    expect(moved.createdAt, server['x']!.createdAt);
    expect(visibleItems({}, [const MoveItem('gone', 'b')]), isEmpty);
  });

  group('store views', () {
    const catalog = Catalog(
      categories: [
        Category(id: 'produce', name: 'produce', sortOrder: 10),
        Category(id: 'chilled', name: 'chilled', sortOrder: 20),
        Category(id: 'pantry', name: 'pantry', sortOrder: 30),
        Category(id: 'new', name: 'new', sortOrder: 40),
        Category(id: 'other', name: 'other', sortOrder: 1000),
      ],
      stores: [
        Store(id: 'dm', name: 'dm', sortOrder: 10),
        Store(id: 'lidl', name: 'Lidl', sortOrder: 20),
      ],
      // Neither store has a row for 'new' yet.
      layout: [
        StoreCategory(storeId: 'lidl', categoryId: 'other', sortOrder: 10),
        StoreCategory(storeId: 'lidl', categoryId: 'pantry', sortOrder: 20),
        StoreCategory(storeId: 'lidl', categoryId: 'chilled', sortOrder: 30),
        StoreCategory(storeId: 'lidl', categoryId: 'produce', sortOrder: 40),
        StoreCategory(storeId: 'dm', categoryId: 'pantry', sortOrder: 10),
        StoreCategory(storeId: 'dm', categoryId: 'other', sortOrder: 20),
        StoreCategory(
          storeId: 'dm',
          categoryId: 'produce',
          sortOrder: 30,
          hidden: true,
        ),
        StoreCategory(
          storeId: 'dm',
          categoryId: 'chilled',
          sortOrder: 40,
          hidden: true,
        ),
      ],
    );
    final everything = [
      item('apple', category: 'produce'),
      item('milk', category: 'chilled', at: 1),
      item('yoghurt', category: 'chilled', store: 'dm', at: 2),
      item('rice', category: 'pantry'),
      item('noodles', category: 'new'),
      item('soap', category: 'other', store: 'dm', at: 1),
      item('beer', category: 'other', store: 'lidl', at: 2),
      item('typed', category: null),
      item('bought', category: 'pantry', status: ItemStatus.bought),
    ];

    final cases =
        <
          ({
            String name,
            List<Item> items,
            StoreFilter filter,
            bool showHidden,
            bool includeEmpty,
            List<String> groups,
            int hiddenCount,
          })
        >[
          (
            name: 'Alle: route order, every store',
            items: everything,
            filter: const AllStores(),
            showHidden: false,
            includeEmpty: false,
            groups: [
              '?: typed',
              'produce: apple',
              'chilled: milk yoghurt',
              'pantry: rice',
              'new: noodles',
              'other: soap beer',
            ],
            hiddenCount: 0,
          ),
          (
            name: "Lidl: its order, no dm items, unplaced 'new' last",
            items: everything,
            filter: const AtStore('lidl'),
            showHidden: false,
            includeEmpty: false,
            groups: [
              '?: typed',
              'other: beer',
              'pantry: rice',
              'chilled: milk',
              'produce: apple',
              'new: noodles',
            ],
            hiddenCount: 0,
          ),
          (
            name: 'dm: hides untagged items it does not carry, keeps tagged',
            items: everything,
            filter: const AtStore('dm'),
            showHidden: false,
            includeEmpty: false,
            groups: [
              '?: typed',
              'pantry: rice',
              'other: soap',
              'chilled: yoghurt',
              'new: noodles',
            ],
            hiddenCount: 2,
          ),
          (
            name: 'dm with hidden items shown',
            items: everything,
            filter: const AtStore('dm'),
            showHidden: true,
            includeEmpty: false,
            groups: [
              '?: typed',
              'pantry: rice',
              'other: soap',
              'produce: apple',
              'chilled: milk yoghurt',
              'new: noodles',
            ],
            hiddenCount: 2,
          ),
          (
            name: 'dm while dragging: empty carried categories as targets',
            items: [item('soap', category: 'other', store: 'dm')],
            filter: const AtStore('dm'),
            showHidden: false,
            includeEmpty: true,
            groups: ['pantry: ', 'other: soap', 'new: '],
            hiddenCount: 0,
          ),
          (
            name: 'dm while dragging with hidden shown: every category',
            items: [],
            filter: const AtStore('dm'),
            showHidden: true,
            includeEmpty: true,
            groups: ['pantry: ', 'other: ', 'produce: ', 'chilled: ', 'new: '],
            hiddenCount: 0,
          ),
          (
            name: 'unknown store: route order',
            items: [item('rice', category: 'pantry')],
            filter: const AtStore('gone'),
            showHidden: false,
            includeEmpty: false,
            groups: ['pantry: rice'],
            hiddenCount: 0,
          ),
        ];

    for (final c in cases) {
      test(c.name, () {
        final grouping = groupActive(
          c.items,
          catalog,
          c.filter,
          showHidden: c.showHidden,
          includeEmpty: c.includeEmpty,
        );
        expect([
          for (final g in grouping.groups)
            '${g.category?.id ?? '?'}: ${g.items.map((i) => i.id).join(' ')}',
        ], c.groups);
        expect(grouping.hiddenCount, c.hiddenCount);
      });
    }
  });

  test('recently bought is newest first', () {
    final bought = recentlyBought([
      item('old', status: ItemStatus.bought, at: 1),
      item('new', status: ItemStatus.bought, at: 2),
      item('active'),
    ]);
    expect([for (final i in bought) i.id], ['new', 'old']);
  });

  test('a badge is the first letter, two when another member shares it', () {
    const catalog = Catalog(
      members: [
        Member(id: 'p', displayName: 'peter'),
        Member(id: 'l', displayName: 'Lea'),
        Member(id: 'l2', displayName: 'Lars'),
        Member(id: 'x', displayName: ' '),
      ],
    );
    expect(
      [for (final m in catalog.members) catalog.initialOf(m)],
      ['P', 'Le', 'La', '?'],
    );
    expect(catalog.member('unknown'), isNull);
  });

  group('seen mark', () {
    final items = [
      item('old', by: 'lea', at: 1),
      item('a', by: 'lea', at: 5),
      item('b', by: 'lea', at: 6),
      item('mine', by: 'peter', at: 7),
      item('pending', at: 8),
      item('gone', by: 'lea', at: 9, status: ItemStatus.bought),
    ];
    final baseline = SeenMark(until: DateTime.utc(2026).add(minutes(2)));
    List<Item> withStatus(String id, ItemStatus status) => [
      for (final i in items)
        if (i.id == id) i.copyWith(status: status) else i,
    ];

    test('fresh is what a partner added after the mark', () {
      expect(baseline.fresh(items, 'peter'), {'a', 'b'});
      expect(const SeenMark().fresh(items, 'peter'), {'old', 'a', 'b'});
      expect(baseline.fresh(items, 'lea'), {'mine'});
    });

    test('marking some keeps their ids, marking all moves the mark', () {
      final some = baseline.marking({'a', 'mine'}, items, 'peter');
      expect(some.fresh(items, 'peter'), {'b'});
      expect(some.ids, {'a'});
      final all = some.marking({'b'}, items, 'peter');
      expect(all.fresh(items, 'peter'), isEmpty);
      expect(all.ids, isEmpty);
      expect(all.until, DateTime.utc(2026).add(minutes(6)));
    });

    test('ids of items that are gone are pruned', () {
      final some = baseline.marking({'a'}, items, 'peter');
      final later = some.marking(const {}, [items[2]], 'peter');
      expect(later.ids, isEmpty);
      expect(later.fresh(items, 'peter'), {'a', 'b'});
    });

    test('a seen item ticked and put back is no news', () {
      final seen = baseline.marking({'a'}, items, 'peter');
      final ticked = withStatus('a', ItemStatus.bought);
      final afterTick = seen.marking(const {}, ticked, 'peter');
      expect(afterTick.fresh(items, 'peter'), {'b'});
    });

    test('an unseen partner item that comes back is news', () {
      final all = baseline.marking({'a', 'b'}, items, 'peter');
      expect(all.until, DateTime.utc(2026).add(minutes(6)));
      final back = withStatus('gone', ItemStatus.active);
      expect(all.fresh(back, 'peter'), {'gone'});
    });
  });

  test('suggestions match whole names first, then word starts', () {
    const usuals = [
      Usual(name: 'Bio-Milch', due: false),
      Usual(name: 'Hafermilch', due: false),
      Usual(name: 'Milch', due: true),
      Usual(name: 'Käse', due: true),
      Usual(name: 'Brot', due: true),
    ];
    List<String> names(List<Usual> list) => [for (final u in list) u.name];
    expect(names(suggestUsuals(usuals, const [], ' MILCH ')), [
      'Milch',
      'Bio-Milch',
    ]);
    expect(names(suggestUsuals(usuals, const [], 'kae')), ['Käse']);
    expect(names(suggestUsuals(usuals, const [], 'Kä')), ['Käse']);
    expect(suggestUsuals(usuals, const [], '  '), isEmpty);
    final brot = Item(
      id: 'x',
      name: 'brot',
      status: ItemStatus.active,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(names(dueUsualsOf(usuals, [brot])), ['Milch', 'Käse']);
  });
}
