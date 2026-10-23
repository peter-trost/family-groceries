import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show immutable;

/// What the list shows without the network: the server state as last
/// confirmed and the ops it has not acknowledged yet.
@immutable
class const ListSnapshot({
  required final Catalog catalog,
  required final List<Item> server,

  /// Oldest first, as queued.
  required final List<ItemOp> pending,
}) {
  /// Throws on another [version]: an old snapshot is dropped, not migrated.
  factory fromJson(Map<String, Object?> json) {
    if (json['version'] != version) {
      throw FormatException('snapshot version', json['version']);
    }
    return ListSnapshot(
      catalog: Catalog.fromJson(json['catalog']! as Map<String, Object?>),
      server: [
        for (final row in json['server']! as List<Object?>)
          Item.fromJson(row! as Map<String, Object?>),
      ],
      pending: [
        for (final op in json['pending']! as List<Object?>)
          ItemOp.fromJson(op! as Map<String, Object?>),
      ],
    );
  }

  static const version = 1;

  Map<String, Object?> toJson() => {
    'version': version,
    'catalog': catalog.toJson(),
    'server': [for (final item in server) item.toJson()],
    'pending': [for (final op in pending) op.toJson()],
  };
}

/// The device's copy of one household's list for one user. [load] returns
/// null when there is none or it cannot be read.
abstract interface class ListCache() {
  Future<ListSnapshot?> load();

  Future<void> save(ListSnapshot snapshot);
}
