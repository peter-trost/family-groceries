import 'dart:async';

import 'package:family_groceries/list/entry.dart';
import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/list_repository.dart';
import 'package:family_groceries/list/model.dart';
import 'package:flutter/foundation.dart' show immutable, setEquals;
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

  /// What the household buys again and again, best first.
  final List<Usual> usuals = const [],

  /// Null until loaded from the device or, on a first start, set by the
  /// first resync.
  final SeenMark? seen,
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
    List<Usual>? usuals,
    SeenMark? seen,
  }) {
    final next = ListState(
      catalog: catalog ?? this.catalog,
      server: server ?? this.server,
      pending: pending ?? this.pending,
      loaded: loaded ?? this.loaded,
      connection: connection ?? this.connection,
      filter: filter ?? this.filter,
      showHidden: showHidden ?? this.showHidden,
      usuals: usuals ?? this.usuals,
      seen: seen ?? this.seen,
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

const _maxResubscribe = Duration(seconds: 30);

class ListCubit(
  final ListRepository _repo,
  final ListCache _cache, {

  /// The signed-in user: their own adds are never news to them.
  required final String userId,
  DateTime Function()? clock,
  Duration resubscribeAfter = const Duration(seconds: 3),
}) extends Cubit<ListState> {
  this : super(const ListState());

  final DateTime Function() _clock = clock ?? DateTime.now;
  final _rejections = StreamController<Rejected>.broadcast();
  Future<void> Function()? _unwatch;
  Timer? _retry;
  Timer? _catalogReload;
  Timer? _save;
  Timer? _usualsReload;
  var _flushing = false;

  /// Rows acknowledged during each resync in flight; they beat its snapshot.
  /// Resyncs overlap (the opening one and the channel's first subscribe).
  final _resyncAcks = <Map<String, Item?>>{};

  /// Whether the realtime channel is subscribed. A resync that answers only
  /// brings the list back online while it is.
  var _channelUp = false;

  /// A channel the server closed is never rejoined by the client library,
  /// so the list subscribes again itself: after `resubscribeAfter`, doubling
  /// up to 30 s while it stays down.
  final _firstResubscribe = resubscribeAfter;
  late var _resubscribeDelay = _firstResubscribe;
  Timer? _resubscribe;

  /// Bumped on every subscribe, so a replaced channel's late callbacks are
  /// ignored.
  var _watchGeneration = 0;

  /// A resync sets the first seen mark only once the stored one was read.
  var _seenLoaded = false;

  Stream<Rejected> get rejections => _rejections.stream;

  /// Shows the cached list, if any, then connects. Ops queued before the
  /// cache answers go after the cached ones.
  void start() => unawaited(_start());

  Future<void> _start() async {
    final (cached, seen) = await (_cache.load(), _cache.loadSeen()).wait;
    if (cached != null) {
      emit(
        state.copyWith(
          catalog: cached.catalog,
          server: {for (final item in cached.server) item.id: item},
          pending: [...cached.pending, ...state.pending],
          loaded: true,
          usuals: cached.usuals,
        ),
      );
    }
    if (seen != null) {
      emit(state.copyWith(seen: seen));
    }
    _seenLoaded = true;
    if (isClosed) {
      return;
    }
    _watch();
    unawaited(resync());
  }

  void _watch() {
    final generation = ++_watchGeneration;
    bool current() => generation == _watchGeneration && !isClosed;
    _unwatch = _repo.watch(
      onItem: (row) {
        if (current()) {
          _setServer(mergeServerRow(state.server, row));
          // A new member: reload so their initial shows.
          if (row.addedBy != null &&
              state.catalog.member(row.addedBy) == null) {
            _scheduleCatalogReload();
          }
        }
      },
      onItemDeleted: (id) {
        if (current() && state.server.containsKey(id)) {
          _setServer({...state.server}..remove(id));
        }
      },
      onCatalogChanged: () {
        if (current()) {
          _scheduleCatalogReload();
        }
      },
      onStatus: (status) {
        if (current()) {
          _onChannelStatus(status);
        }
      },
    );
  }

  void _onChannelStatus(ConnectionStatus status) {
    _channelUp = status == ConnectionStatus.online;
    emit(state.copyWith(connection: status));
    if (_channelUp) {
      _resubscribe?.cancel();
      _resubscribe = null;
      _resubscribeDelay = _firstResubscribe;
      // Covers the first subscribe and every reconnect.
      unawaited(resync());
    } else {
      _resubscribe ??= Timer(_resubscribeDelay, () => unawaited(_rewatch()));
    }
  }

  Future<void> _rewatch() async {
    _resubscribe = null;
    if (isClosed || _channelUp) {
      return;
    }
    final doubled = _resubscribeDelay * 2;
    _resubscribeDelay = doubled < _maxResubscribe ? doubled : _maxResubscribe;
    final previous = _unwatch;
    _watchGeneration++;
    await previous?.call();
    if (!isClosed && !_channelUp) {
      _watch();
    }
  }

  /// A reorder fires one event per row; reload once they settle.
  void _scheduleCatalogReload() {
    _catalogReload?.cancel();
    _catalogReload = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(_reloadCatalog()),
    );
  }

  /// Ids of partner items the user has not looked at yet.
  Set<String> get fresh =>
      state.seen?.fresh(state.items.values, userId) ?? const {};

  /// Marks [ids] as looked at; ids that are not fresh are ignored.
  void markSeen(Set<String> ids) {
    if (state.seen case final seen?) {
      _setSeen(seen.marking(ids, state.items.values, userId));
    }
  }

  void _setSeen(SeenMark seen) {
    emit(state.copyWith(seen: seen));
    unawaited(_cache.saveSeen(seen));
  }

  /// Usuals for what is typed: at most 5, none already on the list.
  List<Usual> suggestionsFor(String text) =>
      suggestUsuals(state.usuals, state.items.values, text);

  /// Usuals that are due and not on the list, at most 10.
  List<Usual> get dueUsuals => dueUsualsOf(state.usuals, state.items.values);

  AddResult addUsual(Usual usual) =>
      addEntry(Entry(usual.name, usual.quantity));

  AddResult add(String input) => addEntry(parseEntry(input));

  /// Splits a dictated sentence on the server and adds each entry.
  /// Throws when the server can't be reached; nothing is added then.
  Future<List<AddResult>> addSpoken(String text) async {
    final entries = await _repo.splitSpoken(text);
    return [for (final entry in entries) addEntry(entry)];
  }

  AddResult addEntry(Entry entry) {
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
    final acked = <String, Item?>{};
    _resyncAcks.add(acked);
    try {
      final (catalog, rows) = await (
        _repo.fetchCatalog(),
        _repo.fetchItems(),
      ).wait;
      final snapshot = {for (final row in rows) row.id: row};
      for (final MapEntry(:key, :value) in acked.entries) {
        if (value == null) {
          snapshot.remove(key);
        } else {
          snapshot[key] = value;
        }
      }
      emit(
        state.copyWith(
          catalog: catalog,
          server: snapshot,
          loaded: true,
          connection: _channelUp ? ConnectionStatus.online : null,
        ),
      );
      if (state.seen == null && _seenLoaded) {
        // A first start: what is on the list already is not news.
        final created = [for (final row in snapshot.values) row.createdAt]
          ..sort();
        _setSeen(SeenMark(until: created.lastOrNull));
      }
      _usualsReload?.cancel();
      unawaited(_refreshUsuals());
    } on Object {
      _goOffline();
    } finally {
      _resyncAcks.remove(acked);
    }
    unawaited(_flush());
  }

  /// A failure keeps the usuals there are; it says nothing about the list.
  Future<void> _refreshUsuals() async {
    try {
      emit(state.copyWith(usuals: await _repo.fetchUsuals()));
    } on Object {
      return;
    }
  }

  Future<void> _reloadCatalog() async {
    try {
      // Await first: `state` read before the await would be stale by now.
      final catalog = await _repo.fetchCatalog();
      emit(state.copyWith(catalog: catalog));
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
    for (final acked in _resyncAcks) {
      acked[op.itemId] = row;
    }
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

  /// Saves what a restart needs: a change to the queue at once, since the
  /// app may be killed right after a tap, and server churn once it settles.
  /// Not on close: the list closes on sign-out and household switches, which
  /// drop the cache.
  @override
  void onChange(Change<ListState> change) {
    super.onChange(change);
    final next = change.nextState;
    final before = change.currentState;
    if (!identical(next.server, before.server) &&
        !setEquals(_activeNames(next.server), _activeNames(before.server))) {
      _usualsReload?.cancel();
      _usualsReload = Timer(
        const Duration(milliseconds: 1500),
        () => unawaited(_refreshUsuals()),
      );
    }
    if (!next.loaded) {
      return;
    }
    if (!identical(next.pending, before.pending)) {
      _save?.cancel();
      _saveNow(next);
    } else if (!identical(next.catalog, before.catalog) ||
        !identical(next.server, before.server) ||
        !identical(next.usuals, before.usuals)) {
      _save?.cancel();
      _save = Timer(const Duration(milliseconds: 300), () => _saveNow(state));
    }
  }

  void _saveNow(ListState state) => unawaited(
    _cache.save(
      ListSnapshot(
        catalog: state.catalog,
        server: [...state.server.values],
        pending: state.pending,
        usuals: state.usuals,
      ),
    ),
  );

  static Set<String> _activeNames(Map<String, Item> server) => {
    for (final item in server.values)
      if (item.status == ItemStatus.active) item.name.toLowerCase(),
  };

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
    _resubscribe?.cancel();
    _catalogReload?.cancel();
    _save?.cancel();
    _usualsReload?.cancel();
    await _unwatch?.call();
    await _rejections.close();
    await super.close();
  }
}
