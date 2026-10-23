import 'dart:convert';

import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';

/// What an offline start needs, in shared preferences: each user's household
/// and one list snapshot per user and household. A cache: a value that
/// cannot be read counts as missing, and a failed write is dropped.
class DeviceCache(final SharedPreferencesAsync _prefs) implements SessionCache {
  /// On Linux, supabase_flutter's legacy SharedPreferences and
  /// SharedPreferencesAsync each rewrite the whole file from their own copy,
  /// so sharing shared_preferences.json loses the session. The other
  /// platforms ignore Linux options and keep their default store.
  factory onDevice() => DeviceCache(
    SharedPreferencesAsync(
      options: const SharedPreferencesLinuxOptions(fileName: 'device_cache'),
    ),
  );

  static const _householdPrefix = 'household.';
  static const _listPrefix = 'list.';

  static String _householdKey(String userId) => '$_householdPrefix$userId';

  static String _listKey(String userId, String householdId) =>
      '$_listPrefix$userId.$householdId';

  ListCache list(String userId, String householdId) =>
      _PrefsListCache(this, userId, householdId);

  @override
  Future<Household?> household(String userId) async {
    try {
      final json = await _prefs.getString(_householdKey(userId));
      return switch (json == null ? null : jsonDecode(json)) {
        {'id': final String id, 'name': final String name} => Household(
          id: id,
          name: name,
        ),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  Future<void> remember(String userId, Household? household) =>
      _write(() async {
        final key = _householdKey(userId);
        if (household == null) {
          await _prefs.remove(key);
        } else {
          await _prefs.setString(
            key,
            jsonEncode({'id': household.id, 'name': household.name}),
          );
        }
        final keep = household == null ? null : _listKey(userId, household.id);
        await _removeWhere(
          (k) => k.startsWith('$_listPrefix$userId.') && k != keep,
        );
      });

  @override
  Future<void> forget() => _write(
    () => _removeWhere(
      (k) => k.startsWith(_householdPrefix) || k.startsWith(_listPrefix),
    ),
  );

  Future<void> _removeWhere(bool Function(String key) test) async {
    final keys = (await _prefs.getKeys()).where(test).toSet();
    if (keys.isNotEmpty) {
      await _prefs.clear(allowList: keys);
    }
  }

  Future<void> _write(Future<void> Function() write) async {
    try {
      await write();
    } on Object {
      // A cache write that fails only costs the next offline start.
    }
  }
}

class _PrefsListCache(
  final DeviceCache _device,
  final String _userId,
  final String _householdId,
) implements ListCache {
  String get _key => DeviceCache._listKey(_userId, _householdId);

  @override
  Future<ListSnapshot?> load() async {
    try {
      final json = await _device._prefs.getString(_key);
      return json == null
          ? null
          : ListSnapshot.fromJson(jsonDecode(json) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  /// Skipped once the user signed out or moved to another household, so a
  /// list closing late cannot write its snapshot back.
  @override
  Future<void> save(ListSnapshot snapshot) => _device._write(() async {
    if ((await _device.household(_userId))?.id == _householdId) {
      await _device._prefs.setString(_key, jsonEncode(snapshot.toJson()));
    }
  });
}
