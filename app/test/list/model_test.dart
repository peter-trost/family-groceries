import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

Item item(
  String id, {
  String? category = 'a',
  ItemStatus status = ItemStatus.active,
  int at = 0,
  int updated = 0,
}) => Item(
  id: id,
  name: id,
  categoryId: category,
  status: status,
  createdAt: DateTime.utc(2026).add(Duration(minutes: at)),
  updatedAt: DateTime.utc(2026).add(Duration(minutes: updated)),
  boughtAt: status == ItemStatus.bought
      ? DateTime.utc(2026).add(Duration(minutes: at))
      : null,
);

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
      const EditItem('z', name: 'Zitronen', quantity: '3', categoryId: 'b'),
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
    final groups = groupActive([
      item('b1', category: 'b', at: 1),
      item('a2', at: 2),
      item('a1', at: 1),
      item('new', category: null),
      item('gone', status: ItemStatus.bought),
      item('orphan', category: 'deleted-category'),
    ], categories);
    expect([for (final g in groups) g.category?.id], [null, 'a', 'b', null]);
    expect([for (final i in groups[1].items) i.id], ['a1', 'a2']);
    expect(groups.last.items.single.id, 'orphan');
  });

  test('recently bought is newest first', () {
    final bought = recentlyBought([
      item('old', status: ItemStatus.bought, at: 1),
      item('new', status: ItemStatus.bought, at: 2),
      item('active'),
    ]);
    expect([for (final i in bought) i.id], ['new', 'old']);
  });
}
