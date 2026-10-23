import 'dart:async';

import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

void main() {
  late FakeRepository repo;
  late ListCubit cubit;
  late MemoryListCache cache;

  Future<void> settle() => pumpEventQueue();
  List<String> activeNames() => [
    for (final i in cubit.state.items.values)
      if (i.status == ItemStatus.active) i.name,
  ];

  setUp(() async {
    repo = FakeRepository();
    cache = MemoryListCache();
    cubit = ListCubit(repo, cache, userId: 'peter')..start();
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
    expect(rejections.single, isA<ItemRejected>());
    expect((rejections.single as ItemRejected).itemName, 'Wein');
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

  test('overlapping resyncs both land and the list stays online', () async {
    repo.remoteAdd('Tee');
    // The channel subscribes while the opening resync is still in flight.
    repo.emitStatus!(ConnectionStatus.online);
    await cubit.resync();
    await settle();
    expect(cubit.state.connection, ConnectionStatus.online);
    expect(activeNames(), ['Tee']);
  });

  test('a resync that answers after a failed one clears offline', () async {
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    repo.online = false;
    await cubit.resync();
    expect(cubit.state.connection, ConnectionStatus.offline);
    repo.online = true;
    await cubit.resync();
    expect(cubit.state.connection, ConnectionStatus.online);
  });

  test('a resync does not claim online while the channel is down', () async {
    repo.emitStatus!(ConnectionStatus.offline);
    await cubit.resync();
    expect(cubit.state.connection, ConnectionStatus.offline);
  });

  test('an add acked during a catalog reload survives the reload', () async {
    repo.catalogGate = Completer();
    final rename = cubit.renameCategory('produce', 'Obst');
    await settle();
    cubit.add('Brot');
    await settle();
    expect(cubit.state.pending, isEmpty);
    repo.catalogGate!.complete();
    await rename;
    expect(cubit.state.pending, isEmpty);
    expect(activeNames(), ['Brot']);
    expect(cubit.state.catalog.categories.first.name, 'Obst');
  });

  test('a closed channel is subscribed again until it is live', () async {
    final retrying = ListCubit(
      repo,
      cache,
      userId: 'peter',
      resubscribeAfter: const Duration(milliseconds: 10),
    )..start();
    await settle();
    final before = repo.watches;
    repo.emitStatus!(ConnectionStatus.offline);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repo.watches, before + 1);
    repo.emitStatus!(ConnectionStatus.online);
    await settle();
    expect(retrying.state.connection, ConnectionStatus.online);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repo.watches, before + 1, reason: 'no more resubscribes once live');
    await retrying.close();
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
  test('in a store view, adds and ticks are tagged with that store', () async {
    cubit.selectStore(const AtStore('lidl'));
    final id = (cubit.add('Brot') as Added).item.id;
    await settle();
    expect(repo.rows[id]!.storeId, 'lidl');

    cubit.selectStore(const AllStores());
    final other = (cubit.add('Käse') as Added).item.id;
    await settle();
    expect(repo.rows[other]!.storeId, isNull);

    cubit
      ..selectStore(const AtStore('dm'))
      ..tick(other);
    await settle();
    expect(repo.sent.last, isA<SetStatus>());
    expect(repo.rows[other]!.status, ItemStatus.bought);
    expect(repo.rows[other]!.storeId, 'dm');
  });

  test('ticking in "Alle" sends no store', () async {
    final id = repo.remoteAdd('Brot', storeId: 'dm').id;
    await cubit.resync();
    cubit.tick(id);
    await settle();
    expect((repo.sent.last as SetStatus).storeId, isNull);
    expect(repo.rows[id]!.storeId, 'dm');
  });

  test('a move sends only the new category', () async {
    final id = (cubit.add('Vollmilch') as Added).item.id;
    await settle();
    cubit.move(id, 'produce');
    expect(cubit.state.items[id]!.categoryId, 'produce', reason: 'optimistic');
    await settle();
    expect(repo.sent.last, isA<MoveItem>());
    expect(repo.rows[id]!.categoryId, 'produce');
  });

  test('an edit sends the store tag, null clearing it', () async {
    final id = (cubit.add('Brot') as Added).item.id;
    await settle();
    cubit.edit(
      id,
      name: 'Brot',
      quantity: null,
      categoryId: 'other',
      storeId: 'dm',
    );
    await settle();
    expect(repo.rows[id]!.storeId, 'dm');
    cubit.edit(
      id,
      name: 'Brot',
      quantity: null,
      categoryId: 'other',
      storeId: null,
    );
    await settle();
    expect(repo.rows[id]!.storeId, isNull);
  });

  List<String> routeOrder() => [
    for (final c in cubit.state.catalog.categories) c.id,
  ];

  test('a reorder shows at once and is saved', () async {
    final saved = cubit.reorderCategories(['chilled', 'produce', 'other']);
    expect(routeOrder(), ['chilled', 'produce', 'other']);
    await saved;
    expect(repo.catalogCalls, ['reorder(chilled, produce, other)']);
    expect(routeOrder(), ['chilled', 'produce', 'other']);
  });

  test('a refused reorder is reported and reverts', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    repo.reject = true;
    final saved = cubit.reorderCategories(['chilled', 'produce', 'other']);
    expect(routeOrder(), ['chilled', 'produce', 'other']);
    await saved;
    await settle();
    expect(routeOrder(), ['produce', 'chilled', 'other']);
    expect(rejections.single, isA<CatalogRejected>());
    await sub.cancel();
  });

  test('a store layout change is saved and sorts the store view', () async {
    await cubit.setStoreLayout(
      'dm',
      ['produce', 'other', 'chilled'],
      {'chilled'},
    );
    final grouping = groupActive(
      [repo.remoteAdd('Äpfel', categoryId: 'produce')],
      cubit.state.catalog,
      const AtStore('dm'),
    );
    expect(grouping.groups.single.category!.id, 'produce');
    expect(repo.layout.where((r) => r.storeId == 'dm' && r.hidden), [
      isA<StoreCategory>().having((r) => r.categoryId, 'id', 'chilled'),
    ]);
  });

  test('a duplicate category name is reported by name', () async {
    final rejections = <Rejected>[];
    final sub = cubit.rejections.listen(rejections.add);
    await cubit.renameCategory('chilled', 'Sonstiges');
    await settle();
    expect(rejections.single, isA<NameTaken>());
    expect(cubit.state.catalog.categories[1].name, 'Kühlregal');
    await sub.cancel();
  });

  test('a deleted category moves its items to the chosen one', () async {
    final id = (cubit.add('Vollmilch') as Added).item.id;
    await settle();
    await cubit.deleteCategory('chilled', reassignTo: 'produce');
    expect(routeOrder(), ['produce', 'other']);
    expect(cubit.state.items[id]!.categoryId, 'produce');
  });

  test(
    'when the selected store disappears the view falls back to Alle',
    () async {
      cubit.selectStore(const AtStore('dm'));
      repo.stores = [...repo.stores.where((s) => s.id != 'dm')];
      for (var i = 0; i < 5; i++) {
        repo.emitCatalogChanged!();
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cubit.state.filter, isA<AllStores>());
    },
  );

  group('across restarts', () {
    // Longer than the cubit's save debounce.
    Future<void> saved() => Future.delayed(const Duration(milliseconds: 400));

    Future<void> restart() async {
      await cubit.close();
      cubit = ListCubit(repo, cache, userId: 'peter')..start();
      await settle();
    }

    test('an offline start shows the cached list and its queued ops', () async {
      final bread = (cubit.add('Brot') as Added).item.id;
      await settle();
      repo.online = false;
      cubit
        ..tick(bread)
        ..add('Käse');
      await saved();

      await restart();
      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.connection, ConnectionStatus.offline);
      expect(cubit.state.server.keys, [bread]);
      expect(cubit.state.pending, hasLength(2));
      expect(activeNames(), ['Käse']);
    });

    test('ops queued during an offline start survive the next restart, '
        'then flush on reconnect', () async {
      final bread = (cubit.add('Brot') as Added).item.id;
      await settle();
      repo.online = false;
      await saved();

      await restart();
      cubit
        ..tick(bread)
        ..add('Eier');
      // No wait for the debounce: the app may be killed right after a tap.
      await settle();
      await restart();
      expect(cubit.state.pending, hasLength(2));
      expect(activeNames(), ['Eier']);

      repo.online = true;
      repo.emitStatus!(ConnectionStatus.online);
      await settle();
      expect(cubit.state.pending, isEmpty);
      expect(repo.rows[bread]!.status, ItemStatus.bought);
      expect([for (final i in repo.rows.values) i.name], ['Brot', 'Eier']);

      await saved();
      expect(cache.saved!.pending, isEmpty, reason: 'the flush is saved too');
    });
  });

  Future<void> startAgain() async {
    await cubit.close();
    cubit = ListCubit(repo, cache, userId: 'peter')..start();
    await settle();
  }

  group('who added what', () {
    test('rows carry who added them', () async {
      final theirs = repo.remoteAdd('Tee').id;
      final mine = (cubit.add('Brot') as Added).item.id;
      expect(cubit.state.items[mine]!.addedBy, isNull, reason: 'unconfirmed');
      await cubit.resync();
      expect(cubit.state.items[theirs]!.addedBy, 'lea');
      expect(cubit.state.items[mine]!.addedBy, 'peter');
      expect(cubit.state.catalog.member('lea')?.displayName, 'Lea');
    });

    test('a first start highlights nothing that was already there', () async {
      repo
        ..remoteAdd('Tee')
        ..remoteAdd('Äpfel');
      cache = MemoryListCache();
      await startAgain();
      expect(cubit.fresh, isEmpty);
      expect(cache.seen, isNotNull, reason: 'the baseline is stored');
    });

    test('a later partner add is fresh, an own add never', () async {
      final tea = repo.remoteAdd('Tee').id;
      cubit.add('Brot');
      await cubit.resync();
      expect(cubit.fresh, {tea});
    });

    test('a live partner insert becomes fresh', () {
      final tea = repo.remoteAdd('Tee');
      repo.emitItem!(tea);
      expect(cubit.fresh, {tea.id});
    });

    test('marking seen clears and survives a restart', () async {
      final tea = repo.remoteAdd('Tee').id;
      final apples = repo.remoteAdd('Äpfel').id;
      await cubit.resync();
      cubit.markSeen({tea});
      expect(cubit.fresh, {apples});
      cubit.markSeen({apples, 'not-fresh'});
      expect(cubit.fresh, isEmpty);
      await settle();

      await startAgain();
      expect(cubit.fresh, isEmpty);
      final later = repo.remoteAdd('Käse').id;
      await cubit.resync();
      expect(cubit.fresh, {later});
    });

    test('a cached list alone sets no baseline', () async {
      repo.remoteAdd('Tee');
      await cubit.resync();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      cache.seen = null;
      repo.online = false;
      await startAgain();
      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.seen, isNull);
      expect(cubit.fresh, isEmpty);

      repo.online = true;
      await cubit.resync();
      expect(cubit.fresh, isEmpty, reason: 'the first resync is the baseline');
    });

    test('an add by an unknown member reloads the catalog', () async {
      repo.members = [
        ...repo.members,
        const Member(id: 'ana', displayName: 'Ana'),
      ];
      repo.emitItem!(repo.remoteAdd('Tee', addedBy: 'ana'));
      expect(cubit.state.catalog.member('ana'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cubit.state.catalog.member('ana')?.displayName, 'Ana');
    });
  });

  group('usuals', () {
    List<String> names(List<Usual> usuals) => [for (final u in usuals) u.name];

    setUp(() async {
      repo.usuals = [
        const Usual(name: 'Milch', quantity: '2', due: true),
        const Usual(name: 'Mehl', due: false),
        const Usual(name: 'Hafer-Milch', due: true),
        const Usual(name: 'Möhren', quantity: '1 kg', due: true),
        const Usual(name: 'Mais', due: false),
        const Usual(name: 'Mango', due: false),
        const Usual(name: 'Müsli', due: false),
        const Usual(name: 'Käse', due: false),
      ];
      await cubit.resync();
      await settle();
    });

    test('suggestions fold, rank whole names first and leave out the list', () {
      expect(names(cubit.suggestionsFor('mi')), ['Milch', 'Hafer-Milch']);
      expect(names(cubit.suggestionsFor(' MILCH')), ['Milch', 'Hafer-Milch']);
      expect(names(cubit.suggestionsFor('moe')), ['Möhren']);
      expect(names(cubit.suggestionsFor('kä')), ['Käse']);
      expect(names(cubit.suggestionsFor('m')), [
        'Milch',
        'Mehl',
        'Möhren',
        'Mais',
        'Mango',
      ]);
      expect(cubit.suggestionsFor(''), isEmpty);

      cubit.add('milch');
      expect(names(cubit.suggestionsFor('milch')), ['Hafer-Milch']);
    });

    test('due usuals leave out what is on the list', () {
      expect(names(cubit.dueUsuals), ['Milch', 'Hafer-Milch', 'Möhren']);
      cubit.add('Möhren');
      expect(names(cubit.dueUsuals), ['Milch', 'Hafer-Milch']);
    });

    test('adding a usual takes its quantity', () async {
      final result = cubit.addUsual(cubit.suggestionsFor('möh').single);
      expect(result, isA<Added>());
      await settle();
      final row = repo.rows.values.single;
      expect((row.name, row.quantity), ('Möhren', '1 kg'));
      expect(cubit.addUsual(cubit.state.usuals[3]), isA<AlreadyOnList>());
    });

    test('cached usuals work offline', () async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      repo.online = false;
      await startAgain();
      expect(cubit.state.connection, ConnectionStatus.offline);
      expect(names(cubit.suggestionsFor('mi')), ['Milch', 'Hafer-Milch']);
      expect(names(cubit.dueUsuals), hasLength(3));
    });

    test('a failed refresh keeps them and the list stays online', () async {
      repo
        ..usualsFail = true
        ..usuals = [];
      await cubit.resync();
      await settle();
      expect(cubit.state.connection, isNot(ConnectionStatus.offline));
      expect(cubit.state.usuals, hasLength(8));
    });

    test('they refresh once the list settles after a change', () async {
      final before = repo.usualsCalls;
      final id = (cubit.add('Brot') as Added).item.id;
      await settle();
      cubit.tick(id);
      await settle();
      expect(repo.usualsCalls, before);
      repo.usuals = [const Usual(name: 'Brot', due: true)];
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(repo.usualsCalls, before + 1);
      expect(names(cubit.dueUsuals), ['Brot']);
    });
  });
}
