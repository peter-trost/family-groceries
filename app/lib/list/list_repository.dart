import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ConnectionStatus() {
  connecting,
  online,
  offline,
}

/// The list's only door to the backend. Errors from [send] other than a
/// [RejectedOp] are treated as transient and retried.
abstract interface class ListRepository() {
  Future<Catalog> fetchCatalog();

  /// Active items plus the most recently bought ones.
  Future<List<Item>> fetchItems();

  /// Applies [op] on the server and returns the resulting row, or null when
  /// the item no longer exists.
  Future<Item?> send(ItemOp op);

  Future<void> renameCategory(String id, String name);

  /// Appends the category to the route and to every store layout.
  Future<void> createCategory(String name);

  /// [ids] is every category, in the new route order.
  Future<void> reorderCategories(List<String> ids);

  /// Moves the category's items to [reassignTo], by default the fallback.
  Future<void> deleteCategory(String id, {String? reassignTo});

  /// [orderedIds] is every category in the store's walking order.
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  );

  /// Splits a dictated sentence into entries with the server's German
  /// splitter (the voice endpoint Siri uses); empty when it found nothing.
  Future<List<Entry>> splitSpoken(String text);

  /// Live changes for the household; returns a function that unsubscribes.
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id) onItemDeleted,
    required void Function() onCatalogChanged,
    required void Function(ConnectionStatus status) onStatus,
  });
}

/// The server refused a write (constraint, policy); retrying will not help.
final class const RejectedOp(
  final String message, {

  /// A category or store with that name already exists.
  final bool nameTaken = false,
}) implements Exception {
  @override
  String toString() => 'RejectedOp($message)';
}

/// Runs a write; a PostgREST answer means the database refused it.
Future<T> _refusable<T>(Future<T> Function() write) async {
  try {
    return await write();
  } on PostgrestException catch (e) {
    throw RejectedOp(e.message, nameTaken: e.code == '23505');
  }
}

class SupabaseListRepository(
  final SupabaseClient _client,
  final String householdId,
) implements ListRepository {
  static const _itemColumns =
      'id, name, quantity, category_id, store_id, status, created_at, '
      'updated_at, bought_at';

  @override
  Future<Catalog> fetchCatalog() async {
    final (categories, stores, layout) = await (
      _client
          .from('categories')
          .select('id, name, sort_order, seed_key')
          .eq('household_id', householdId)
          .order('sort_order', ascending: true),
      _client
          .from('stores')
          .select('id, name, sort_order, seed_key')
          .eq('household_id', householdId)
          .order('sort_order', ascending: true),
      _client
          .from('store_category_order')
          .select('store_id, category_id, sort_order, hidden')
          .eq('household_id', householdId),
    ).wait;
    return Catalog(
      categories: categories.map(Category.fromJson).toList(),
      stores: stores.map(Store.fromJson).toList(),
      layout: layout.map(StoreCategory.fromJson).toList(),
    );
  }

  @override
  Future<void> renameCategory(String id, String name) => _refusable(
    () => _client.from('categories').update({'name': name}).eq('id', id),
  );

  @override
  Future<void> createCategory(String name) => _refusable(
    () => _client.rpc<void>(
      'create_category',
      params: {'p_household': householdId, 'p_name': name},
    ),
  );

  @override
  Future<void> reorderCategories(List<String> ids) => _refusable(
    () => _client.rpc<void>(
      'reorder_categories',
      params: {'p_household': householdId, 'p_ids': ids},
    ),
  );

  @override
  Future<void> deleteCategory(String id, {String? reassignTo}) => _refusable(
    () => _client.rpc<void>(
      'delete_category',
      params: {'p_category': id, 'p_reassign_to': reassignTo},
    ),
  );

  @override
  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) => _refusable(
    () => _client.rpc<void>(
      'set_store_layout',
      params: {
        'p_store': storeId,
        'p_categories': orderedIds,
        'p_hidden': hiddenIds.toList(),
      },
    ),
  );

  @override
  Future<List<Item>> fetchItems() async {
    final results = await Future.wait([
      _client
          .from('items')
          .select(_itemColumns)
          .eq('household_id', householdId)
          .eq('status', 'active'),
      _client
          .from('items')
          .select(_itemColumns)
          .eq('household_id', householdId)
          .eq('status', 'bought')
          .order('bought_at', ascending: false)
          .limit(50),
    ]);
    return [for (final rows in results) ...rows.map(Item.fromJson)];
  }

  @override
  Future<Item?> send(ItemOp op) async {
    final rows = await _refusable(() => _write(op));
    if (op is DeleteItem) {
      return null;
    }
    // No row back: the item is gone, or an upsert hit an existing id.
    return rows.isEmpty
        ? await _fetchItem(op.itemId)
        : Item.fromJson(rows.single);
  }

  Future<List<Map<String, dynamic>>> _write(ItemOp op) {
    final items = _client.from('items');
    return switch (op) {
      AddItem(:final item) =>
        items
            .upsert({
              'id': item.id,
              'household_id': householdId,
              'name': item.name,
              'quantity': item.quantity,
              'category_id': ?item.categoryId,
              // None given: the server fills in the remembered store.
              'store_id': ?item.storeId,
              'status': item.status.name,
            }, ignoreDuplicates: true)
            .select(_itemColumns),
      SetStatus(:final status, :final storeId) =>
        items
            .update({'status': status.name, 'store_id': ?storeId})
            .eq('id', op.itemId)
            .select(_itemColumns),
      EditItem(
        :final name,
        :final quantity,
        :final categoryId,
        :final storeId,
      ) =>
        items
            .update({
              'name': name,
              'quantity': quantity,
              'category_id': categoryId,
              'store_id': storeId,
            })
            .eq('id', op.itemId)
            .select(_itemColumns),
      MoveItem(:final categoryId) =>
        items
            .update({'category_id': categoryId})
            .eq('id', op.itemId)
            .select(_itemColumns),
      DeleteItem() => items.delete().eq('id', op.itemId).select('id'),
    };
  }

  @override
  Future<List<Entry>> splitSpoken(String text) async {
    try {
      final response = await _client.functions.invoke(
        'voice',
        body: {'text': text, 'mode': 'parse'},
      );
      final items = switch (response.data) {
        {'items': final List<Object?> items} => items,
        _ => const <Object?>[],
      };
      return [
        for (final item in items)
          if (item case {
            'name': final String name,
            'quantity': final String? quantity,
          })
            Entry(name, quantity),
      ];
    } on FunctionException catch (e) {
      if (e.status == 422) {
        return const [];
      }
      rethrow;
    }
  }

  Future<Item?> _fetchItem(String id) async {
    final row = await _client
        .from('items')
        .select(_itemColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Item.fromJson(row);
  }

  @override
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id) onItemDeleted,
    required void Function() onCatalogChanged,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    final mine = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'household_id',
      value: householdId,
    );
    final channel = _client.channel('household:$householdId');
    for (final table in ['categories', 'stores', 'store_category_order']) {
      for (final event in [
        PostgresChangeEvent.insert,
        PostgresChangeEvent.update,
      ]) {
        channel.onPostgresChanges(
          event: event,
          schema: 'public',
          table: table,
          filter: mine,
          callback: (_) => onCatalogChanged(),
        );
      }
      // Delete events cannot be filtered; another household's only costs a
      // reload.
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: table,
        callback: (_) => onCatalogChanged(),
      );
    }
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'items',
          filter: mine,
          callback: (p) => onItem(Item.fromJson(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'items',
          filter: mine,
          callback: (p) => onItem(Item.fromJson(p.newRecord)),
        )
        // Delete events cannot be filtered; unknown ids are ignored.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'items',
          callback: (p) => switch (p.oldRecord['id']) {
            final String id => onItemDeleted(id),
            _ => null,
          },
        )
        .subscribe(
          (status, _) => onStatus(switch (status) {
            RealtimeSubscribeStatus.subscribed => ConnectionStatus.online,
            RealtimeSubscribeStatus.channelError ||
            RealtimeSubscribeStatus.timedOut ||
            RealtimeSubscribeStatus.closed => ConnectionStatus.offline,
          }),
        );
    return () async {
      await _client.removeChannel(channel);
    };
  }
}
