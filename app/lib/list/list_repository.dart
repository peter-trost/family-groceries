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
  Future<List<Category>> fetchCategories();

  /// Active items plus the most recently bought ones.
  Future<List<Item>> fetchItems();

  /// Applies [op] on the server and returns the resulting row, or null when
  /// the item no longer exists.
  Future<Item?> send(ItemOp op);

  /// Live changes for the household; returns a function that unsubscribes.
  Future<void> Function() watch({
    required void Function(Item item) onItem,
    required void Function(String id) onItemDeleted,
    required void Function() onCategoriesChanged,
    required void Function(ConnectionStatus status) onStatus,
  });
}

/// The server refused an op (constraint, policy); retrying will not help.
final class const RejectedOp(final String message) implements Exception {
  @override
  String toString() => 'RejectedOp($message)';
}

class SupabaseListRepository(
  final SupabaseClient _client,
  final String householdId,
) implements ListRepository {
  static const _itemColumns =
      'id, name, quantity, category_id, store_id, status, created_at, '
      'updated_at, bought_at';

  @override
  Future<List<Category>> fetchCategories() async {
    final rows = await _client
        .from('categories')
        .select('id, name, sort_order, seed_key')
        .eq('household_id', householdId)
        .order('sort_order');
    return rows.map(Category.fromJson).toList();
  }

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
    try {
      final rows = await _write(op);
      if (op is DeleteItem) {
        return null;
      }
      // No row back: the item is gone, or an upsert hit an existing id.
      return rows.isEmpty
          ? await _fetchItem(op.itemId)
          : Item.fromJson(rows.single);
    } on PostgrestException catch (e) {
      // PostgREST answered: the request reached the database and was refused.
      throw RejectedOp(e.message);
    }
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
              'status': item.status.name,
            }, ignoreDuplicates: true)
            .select(_itemColumns),
      SetStatus(:final status) =>
        items
            .update({'status': status.name})
            .eq('id', op.itemId)
            .select(_itemColumns),
      EditItem(:final name, :final quantity, :final categoryId) =>
        items
            .update({
              'name': name,
              'quantity': quantity,
              'category_id': categoryId,
            })
            .eq('id', op.itemId)
            .select(_itemColumns),
      DeleteItem() => items.delete().eq('id', op.itemId).select('id'),
    };
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
    required void Function() onCategoriesChanged,
    required void Function(ConnectionStatus status) onStatus,
  }) {
    final mine = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'household_id',
      value: householdId,
    );
    final channel = _client
        .channel('household:$householdId')
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
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          filter: mine,
          callback: (_) => onCategoriesChanged(),
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
