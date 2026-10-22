import 'dart:async';

import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';

void main() {
  late FakeRepository repo;
  late ListCubit cubit;

  Future<void> settle() => pumpEventQueue();
  List<String> activeNames() => [
    for (final i in cubit.state.items.values)
      if (i.status == ItemStatus.active) i.name,
  ];

  setUp(() async {
    repo = FakeRepository();
    cubit = ListCubit(repo)..start();
    await settle();
  });

  tearDown(() => cubit.close());

  test('an add shows at once, then takes the server category', () async {
    repo.gate = Completer();
    final result = cubit.add('2 Vollmilch');
    expect(result, isA<Added>());
    final id = (result as Added).item.id;
    expect(cubit.state.items[id]!.categoryId, isNull);
    expect(cubit.state.items[id]!.quantity, '2');

    repo.gate!.complete();
    await settle();
    expect(cubit.state.items[id]!.categoryId, 'chilled');
    expect(cubit.state.pending, isEmpty);
  });

  test('duplicates of active items are refused, case-insensitively', () async {
    cubit.add('Butter');
    await settle();
    expect(cubit.add('butter'), isA<AlreadyOnList>());
    expect(cubit.add('   '), isA<NothingToAdd>());
    expect(activeNames(), ['Butter']);
  });

  test('tick and undo round-trip through the server', () async {
    final id = (cubit.add('Brot') as Added).item.id;
    await settle();
    cubit.tick(id);
    expect(activeNames(), isEmpty, reason: 'optimistic');
    await settle();
    expect(repo.rows[id]!.status, ItemStatus.bought);
    cubit.untick(id);
    await settle();
    expect(repo.rows[id]!.status, ItemStatus.active);
    expect(activeNames(), ['Brot']);
  });

  test('offline ops stay visible, queue, and flush on reconnect', () async {
    final id = (cubit.add('Brot') as Added).item.id;
    await settle();

    repo.online = false;
    cubit
      ..tick(id)
      ..add('Käse');
    await settle();
    expect(cubit.state.connection, ConnectionStatus.offline);
    expect(cubit.state.pending, hasLength(2));
    expect(activeNames(), ['Käse']);

    repo.online = true;
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    expect(cubit.state.pending, isEmpty);
    expect(repo.rows[id]!.status, ItemStatus.bought);
    expect(activeNames(), ['Käse']);
  });

  test('a rejected op is dropped, reported, and the view resyncs', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    repo.reject = true;
    cubit.add('Wein');
    await settle();
    expect(rejections.single.itemName, 'Wein');
    expect(cubit.state.pending, isEmpty);
    expect(activeNames(), isEmpty);
    await sub.cancel();
  });

  test('remote changes and deletes arrive through realtime', () {
    final remote = repo.remoteAdd('Äpfel');
    repo.emitItem!(remote);
    expect(activeNames(), ['Äpfel']);
    repo.emitDelete!(remote.id);
    expect(activeNames(), isEmpty);
    repo.emitDelete!('unknown-id');
  });

  test('resync picks up changes missed while disconnected', () async {
    repo.remoteAdd('Tee');
    await cubit.resync();
    expect(activeNames(), ['Tee']);
  });

  test('a delete can be undone with the same id', () async {
    final item = (cubit.add('Milch') as Added).item;
    await settle();
    final saved = cubit.state.items[item.id]!;
    cubit.delete(item.id);
    await settle();
    expect(repo.rows, isEmpty);
    cubit.restore(saved);
    await settle();
    expect(repo.rows[item.id]!.categoryId, 'chilled');
  });
}
