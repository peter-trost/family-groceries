import 'dart:async';

import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

@immutable
class const ListState({
  final List<Category> categories = const [],

  /// Rows as last confirmed by the server.
  final Map<String, Item> server = const {},

  /// Ops not yet acknowledged, oldest first.
  final List<ItemOp> pending = const [],
  final bool loaded = false,
  final ConnectionStatus connection = ConnectionStatus.connecting,
}) {
  Map<String, Item> get items => visibleItems(server, pending);

  ListState copyWith({
    List<Category>? categories,
    Map<String, Item>? server,
    List<ItemOp>? pending,
    bool? loaded,
    ConnectionStatus? connection,
  }) => ListState(
    categories: categories ?? this.categories,
    server: server ?? this.server,
    pending: pending ?? this.pending,
    loaded: loaded ?? this.loaded,
    connection: connection ?? this.connection,
  );
}

sealed class const AddResult();

final class const Added(final Item item) extends AddResult;

final class const AlreadyOnList(final Item item) extends AddResult;

final class const NothingToAdd() extends AddResult;

/// An op the server refused; the UI tells the user.
@immutable
class const Rejected(final String itemName, final String message);

class ListCubit(final ListRepository _repo, {DateTime Function()? clock})
    extends Cubit<ListState> {
  this : super(const ListState());

  final DateTime Function() _clock = clock ?? DateTime.now;
  final _rejections = StreamController<Rejected>.broadcast();
  Future<void> Function()? _unwatch;
  Timer? _retry;
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
      onCategoriesChanged: () => unawaited(_reloadCategories()),
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
      status: ItemStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    _enqueue(AddItem(item));
    return Added(item);
  }

  void tick(String id) => _enqueue(SetStatus(id, ItemStatus.bought, _clock()));

  void untick(String id) =>
      _enqueue(SetStatus(id, ItemStatus.active, _clock()));

  void edit(
    String id, {
    required String name,
    required String? quantity,
    required String categoryId,
  }) => _enqueue(
    EditItem(id, name: name, quantity: quantity, categoryId: categoryId),
  );

  void delete(String id) => _enqueue(DeleteItem(id));

  /// Puts a deleted item back, keeping its id and category.
  void restore(Item item) => _enqueue(
    AddItem(item.copyWith(status: ItemStatus.active, boughtAt: () => null)),
  );

  Future<void> resync() async {
    _ackedDuringResync = {};
    try {
      final (categories, rows) = await (
        _repo.fetchCategories(),
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
      emit(
        state.copyWith(categories: categories, server: snapshot, loaded: true),
      );
    } on Object {
      _goOffline();
    } finally {
      _ackedDuringResync = null;
    }
    unawaited(_flush());
  }

  Future<void> _reloadCategories() async {
    try {
      emit(state.copyWith(categories: await _repo.fetchCategories()));
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
        } on RejectedOp catch (e) {
          _drop(op);
          _rejections.add(Rejected(_nameOf(op), e.message));
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
    await _unwatch?.call();
    await _rejections.close();
    await super.close();
  }
}
