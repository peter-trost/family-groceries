import 'package:family_groceries/app/device_cache.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late DeviceCache cache;
  const home = Household(id: 'home', name: 'Zuhause');
  const work = Household(id: 'work', name: 'Büro');
  final snapshot = ListSnapshot(
    catalog: const Catalog(),
    server: [
      Item(
        id: 'milk',
        name: 'Milch',
        status: ItemStatus.active,
        createdAt: DateTime.utc(2026, 10, 22),
        updatedAt: DateTime.utc(2026, 10, 22),
      ),
    ],
    pending: const [DeleteItem('milk')],
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    cache = DeviceCache(SharedPreferencesAsync());
  });

  test('a list is kept per user and household', () async {
    await cache.remember('peter', home);
    await cache.list('peter', 'home').save(snapshot);
    expect((await cache.household('peter'))?.name, 'Zuhause');
    expect(
      (await cache.list('peter', 'home').load())?.toJson(),
      snapshot.toJson(),
    );
    expect(await cache.list('lea', 'home').load(), isNull);
  });

  test('moving to another household drops the old list', () async {
    await cache.remember('peter', home);
    await cache.list('peter', 'home').save(snapshot);
    await cache.remember('peter', work);
    expect(await cache.list('peter', 'home').load(), isNull);

    await cache.list('peter', 'home').save(snapshot);
    expect(
      await cache.list('peter', 'home').load(),
      isNull,
      reason: 'a list closing late cannot write the old household back',
    );
  });

  test('leaving every household drops the lists', () async {
    await cache.remember('peter', home);
    await cache.list('peter', 'home').save(snapshot);
    await cache.remember('peter', null);
    expect(await cache.household('peter'), isNull);
    expect(await cache.list('peter', 'home').load(), isNull);
  });

  test('signing out forgets every user', () async {
    await cache.remember('peter', home);
    await cache.remember('lea', home);
    await cache.list('peter', 'home').save(snapshot);
    await cache.forget();
    expect(await cache.household('peter'), isNull);
    expect(await cache.household('lea'), isNull);
    expect(await cache.list('peter', 'home').load(), isNull);
    await cache.list('peter', 'home').save(snapshot);
    expect(await cache.list('peter', 'home').load(), isNull);
  });

  group('seen marks', () {
    final mark = SeenMark(
      until: DateTime.utc(2026, 10, 22, 12),
      ids: const {'a'},
    );

    test('are kept per user and household', () async {
      await cache.remember('peter', home);
      expect(await cache.list('peter', 'home').loadSeen(), isNull);
      await cache.list('peter', 'home').saveSeen(mark);
      final back = await cache.list('peter', 'home').loadSeen();
      expect(back?.until, mark.until);
      expect(back?.ids, {'a'});
      expect(await cache.list('lea', 'home').loadSeen(), isNull);
      expect(await cache.list('peter', 'work').loadSeen(), isNull);
    });

    test('go with the household and on sign-out', () async {
      await cache.remember('peter', home);
      await cache.list('peter', 'home').saveSeen(mark);
      await cache.remember('peter', home);
      expect(
        await cache.list('peter', 'home').loadSeen(),
        isNotNull,
        reason: 'remembering the same household keeps it',
      );
      await cache.remember('peter', work);
      expect(await cache.list('peter', 'home').loadSeen(), isNull);

      await cache.list('peter', 'work').saveSeen(mark);
      await cache.forget();
      expect(await cache.list('peter', 'work').loadSeen(), isNull);
    });
  });
}
