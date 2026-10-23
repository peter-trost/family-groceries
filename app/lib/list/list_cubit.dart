import 'dart:async';

import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

@immutable
class const ListState({
  final Catalog catalog = const Catalog(),

  /// Rows as last confirmed by the server.
  final Map<String, Item> server = const {},

  /// Ops not yet acknowledged, oldest first.
  final List<ItemOp> pending = const [],
  final bool loaded = false,
  final ConnectionStatus connection = ConnectionStatus.connecting,

  /// Starts at "Alle" on every launch.
  final StoreFilter filter = const AllStores(),

  /// Whether the store view also shows untagged items in categories the
  /// store does not carry.
  final bool showHidden = false,
}) {
  Map<String, Item> get items => visibleItems(server, pending);

  /// The store being shopped at, or null for "Alle".
  String? get storeId => switch (filter) {
    AtStore(:final storeId) => storeId,
    AllStores() => null,
  };

  ListState copyWith({
    Catalog? catalog,
    Map<String, Item>? server,
    List<ItemOp>? pending,
    bool? loaded,
    ConnectionStatus? connection,
    StoreFilter? filter,
    bool? showHidden,
  }) {
    final next = ListState(
      catalog: catalog ?? this.catalog,
      server: server ?? this.server,
      pending: pending ?? this.pending,
      loaded: loaded ?? this.loaded,
      connection: connection ?? this.connection,
      filter: filter ?? this.filter,
      showHidden: showHidden ?? this.showHidden,
    );
    // A store that disappeared from the catalog falls back to "Alle".
    return switch (next.filter) {
      AtStore(:final storeId)
          when next.loaded && next.catalog.store(storeId) == null =>
        next.copyWith(filter: const AllStores(), showHidden: false),
      _ => next,
    };
  }
}

sealed class const AddResult();

final class const Added(final Item item) extends AddResult;

final class const AlreadyOnList(final Item item) extends AddResult;

final class const NothingToAdd() extends AddResult;

/// A write the server refused; the UI tells the user.
sealed class const Rejected();

final class const ItemRejected(final String itemName) extends Rejected;

final class const NameTaken(final String name) extends Rejected;

/// A category or layout change did not save; the catalog was reloaded.
final class const CatalogRejected() extends Rejected;

class ListCubit(final ListRepository _repo, {DateTime Function()? clock})
    extends Cubit<ListState> {
  this : super(const ListState());

  final DateTime Function() _clock = clock ?? DateTime.now;
  final _rejections = StreamController<Rejected>.broadcast();
  Future<void> Function()? _unwatch;
  Timer? _retry;
  Timer? _catalogReload;
  var _flushing = false;

  /// Rows acknowledged while a resync is in flight; they beat its snapshot.
  Map<String, Item?>? _ackedDuringResync;

  Stream<Rejected> get rejections => _rejections.stream;

  void start() {
    _unwatch = _repo.watch(
      onItem: (row) => _setServer(mergeServerRow(state.server, row)),
      onItemDeleted: (id) {
        if (state.server.containsKey(id)) {
          _setServer({...state.server}..remove(id));
        }
      },
      // A reorder fires one event per row; reload once they settle.
      onCatalogChanged: () {
        _catalogReload?.cancel();
        _catalogReload = Timer(
          const Duration(milliseconds: 200),
          () => unawaited(_reloadCatalog()),
        );
      },
      onStatus: (status) {
        emit(state.copyWith(connection: status));
        if (status == ConnectionStatus.online) {
          // Covers the first subscribe and every reconnect.
          unawaited(resync());
        }
      },
    );
    unawaited(resync());
  }

  AddResult add(String input) {
    final entry = parseEntry(input);
    if (entry.name.isEmpty) {
      return const NothingToAdd();
    }
    final key = entry.name.toLowerCase();
    for (final item in state.items.values) {
      if (item.status == ItemStatus.active && item.name.toLowerCase() == key) {
        return AlreadyOnList(item);
      }
    }
    final now = _clock();
    final item = Item(
      id: const Uuid().v4(),
      name: entry.name,
      quantity: entry.quantity,
      // Typed in a store view, it belongs there and stays visible.
      storeId: state.storeId,
      status: ItemStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    _enqueue(AddItem(item));
    return Added(item);
  }

  void tick(String id) => _enqueue(
    SetStatus(id, ItemStatus.bought, _clock(), storeId: state.storeId),
  );

  void untick(String id) =>
      _enqueue(SetStatus(id, ItemStatus.active, _clock()));

  void edit(
    String id, {
    required String name,
    required String? quantity,
    required String categoryId,
    required String? storeId,
  }) => _enqueue(
    EditItem(
      id,
      name: name,
      quantity: quantity,
      categoryId: categoryId,
      storeId: storeId,
    ),
  );

  void move(String id, String categoryId) => _enqueue(MoveItem(id, categoryId));

  void delete(String id) => _enqueue(DeleteItem(id));

  /// Puts a deleted item back, keeping its id and category.
  void restore(Item item) => _enqueue(
    AddItem(item.copyWith(status: ItemStatus.active, boughtAt: () => null)),
  );

  void selectStore(StoreFilter filter) =>
      emit(state.copyWith(filter: filter, showHidden: false));

  void toggleShowHidden() =>
      emit(state.copyWith(showHidden: !state.showHidden));

  Future<void> renameCategory(String id, String name) => _changeCatalog(
    state.catalog.withName(id, name),
    () => _repo.renameCategory(id, name),
    name: name,
  );

  Future<void> createCategory(String name) =>
      _changeCatalog(null, () => _repo.createCategory(name), name: name);

  Future<void> reorderCategories(List<String> ids) => _changeCatalog(
    state.catalog.withRouteOrder(ids),
    () => _repo.reorderCategories(ids),
  );

  /// Items move on the server; a resync brings them over.
  Future<void> deleteCategory(String id, {String? reassignTo}) async {
    await _changeCatalog(
      null,
      () => _repo.deleteCategory(id, reassignTo: reassignTo),
    );
    await resync();
  }

  Future<void> setStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) => _changeCatalog(
    state.catalog.withStoreLayout(storeId, orderedIds, hiddenIds),
    () => _repo.setStoreLayout(storeId, orderedIds, hiddenIds),
  );

  /// Shows [optimistic] at once, writes, then reloads the catalog. A failed
  /// write is reported, and the reload puts the server's state back.
  Future<void> _changeCatalog(
    Catalog? optimistic,
    Future<void> Function() write, {
    String? name,
  }) async {
    if (optimistic != null) {
      emit(state.copyWith(catalog: optimistic));
    }
    try {
      await write();
    } on RejectedOp catch (e) {
      _report(
        e.nameTaken && name != null ? NameTaken(name) : const CatalogRejected(),
      );
    } on Object {
      _report(const CatalogRejected());
    }
    await _reloadCatalog();
  }

  void _report(Rejected rejection) {
    if (!_rejections.isClosed) {
      _rejections.add(rejection);
    }
  }

  Future<void> resync() async {
    _ackedDuringResync = {};
    try {
      final (catalog, rows) = await (
        _repo.fetchCatalog(),
        _repo.fetchItems(),
      ).wait;
      final snapshot = {for (final row in rows) row.id: row};
      for (final MapEntry(:key, :value) in _ackedDuringResync!.entries) {
        if (value == null) {
          snapshot.remove(key);
        } else {
          snapshot[key] = value;
        }
      }
      emit(state.copyWith(catalog: catalog, server: snapshot, loaded: true));
    } on Object {
      _goOffline();
    } finally {
      _ackedDuringResync = null;
    }
    unawaited(_flush());
  }

  Future<void> _reloadCatalog() async {
    try {
      emit(state.copyWith(catalog: await _repo.fetchCatalog()));
    } on Object {
      _goOffline();
    }
  }

  void _enqueue(ItemOp op) {
    emit(state.copyWith(pending: [...state.pending, op]));
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      while (state.pending.isNotEmpty && !isClosed) {
        final op = state.pending.first;
        try {
          _ack(op, await _repo.send(op));
        } on RejectedOp {
          _drop(op);
          _report(ItemRejected(_nameOf(op)));
          unawaited(resync());
        } on Object {
          _goOffline();
          return;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void _ack(ItemOp op, Item? row) {
    _ackedDuringResync?[op.itemId] = row;
    final server = row == null
        ? ({...state.server}..remove(op.itemId))
        : mergeServerRow(state.server, row);
    emit(
      state.copyWith(
        server: server,
        pending: [...state.pending.where((p) => !identical(p, op))],
        connection: ConnectionStatus.online,
      ),
    );
  }

  void _drop(ItemOp op) => emit(
    state.copyWith(pending: [...state.pending.where((p) => !identical(p, op))]),
  );

  String _nameOf(ItemOp op) => switch (op) {
    AddItem(:final item) => item.name,
    EditItem(:final name) => name,
    _ => state.server[op.itemId]?.name ?? '',
  };

  void _setServer(Map<String, Item> server) =>
      emit(state.copyWith(server: server));

  void _goOffline() {
    emit(state.copyWith(connection: ConnectionStatus.offline));
    _retry ??= Timer(const Duration(seconds: 3), () {
      _retry = null;
      if (!isClosed) {
        unawaited(resync());
      }
    });
  }

  // Fetches and acks can land after the screen is gone.
  @override
  void emit(ListState state) {
    if (!isClosed) {
      super.emit(state);
    }
  }

  @override
  Future<void> close() async {
    _retry?.cancel();
    _catalogReload?.cancel();
    await _unwatch?.call();
    await _rejections.close();
    await super.close();
  }
}
