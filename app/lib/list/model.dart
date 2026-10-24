import 'package:flutter/foundation.dart' show immutable;

enum ItemStatus() {
  active,
  bought,
}

@immutable
class const Category({
  required final String id,
  required final String name,
  required final int sortOrder,
  final String? seedKey,
}) {
  factory fromJson(Map<String, Object?> json) => Category(
    id: json['id']! as String,
    name: json['name']! as String,
    sortOrder: json['sort_order']! as int,
    seedKey: json['seed_key'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'seed_key': seedKey,
  };
}

@immutable
class const Store({
  required final String id,
  required final String name,
  required final int sortOrder,
  final String? seedKey,
}) {
  factory fromJson(Map<String, Object?> json) => Store(
    id: json['id']! as String,
    name: json['name']! as String,
    sortOrder: json['sort_order']! as int,
    seedKey: json['seed_key'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'seed_key': seedKey,
  };
}

/// Where a category sits in one store's walking order, and whether the store
/// carries it at all.
@immutable
class const StoreCategory({
  required final String storeId,
  required final String categoryId,
  required final int sortOrder,
  final bool hidden = false,
}) {
  factory fromJson(Map<String, Object?> json) => StoreCategory(
    storeId: json['store_id']! as String,
    categoryId: json['category_id']! as String,
    sortOrder: json['sort_order']! as int,
    hidden: json['hidden']! as bool,
  );

  Map<String, Object?> toJson() => {
    'store_id': storeId,
    'category_id': categoryId,
    'sort_order': sortOrder,
    'hidden': hidden,
  };
}

/// The household's categories, stores and store layouts: everything the list
/// is sorted by. [categories] and [stores] are in their sort order.
@immutable
class const Catalog({
  final List<Category> categories = const [],
  final List<Store> stores = const [],
  final List<StoreCategory> layout = const [],
  final List<Member> members = const [],
}) {
  factory fromJson(Map<String, Object?> json) => Catalog(
    categories: [
      for (final row in json['categories']! as List<Object?>)
        Category.fromJson(row! as Map<String, Object?>),
    ],
    stores: [
      for (final row in json['stores']! as List<Object?>)
        Store.fromJson(row! as Map<String, Object?>),
    ],
    layout: [
      for (final row in json['layout']! as List<Object?>)
        StoreCategory.fromJson(row! as Map<String, Object?>),
    ],
    members: [
      for (final row in json['members']! as List<Object?>)
        Member.fromJson(row! as Map<String, Object?>),
    ],
  );

  Map<String, Object?> toJson() => {
    'categories': [for (final c in categories) c.toJson()],
    'stores': [for (final s in stores) s.toJson()],
    'layout': [for (final row in layout) row.toJson()],
    'members': [for (final m in members) m.toJson()],
  };

  Member? member(String? id) => members.where((m) => m.id == id).firstOrNull;

  /// The badge for [member]: the first letter, two when another member's
  /// name starts with the same one, '?' for an empty name.
  String initialOf(Member member) {
    String head(String name, int n) =>
        String.fromCharCodes(name.trim().runes.take(n));
    final first = head(member.displayName, 1).toUpperCase();
    if (first.isEmpty) {
      return '?';
    }
    final shared = members.any(
      (m) => m.id != member.id && head(m.displayName, 1).toUpperCase() == first,
    );
    return shared
        ? first + head(member.displayName, 2).substring(first.length)
        : first;
  }

  Category? get fallback =>
      categories.where((c) => c.seedKey == 'other').firstOrNull;

  Store? store(String id) => stores.where((s) => s.id == id).firstOrNull;

  /// The route order is the position in [ids].
  Catalog withRouteOrder(List<String> ids) {
    final byId = {for (final c in categories) c.id: c};
    return Catalog(
      categories: [
        for (final (i, id) in ids.indexed)
          if (byId[id] case final c?)
            Category(
              id: c.id,
              name: c.name,
              sortOrder: (i + 1) * 10,
              seedKey: c.seedKey,
            ),
      ],
      stores: stores,
      layout: layout,
      members: members,
    );
  }

  Catalog withName(String categoryId, String name) => Catalog(
    categories: [
      for (final c in categories)
        if (c.id == categoryId)
          Category(
            id: c.id,
            name: name,
            sortOrder: c.sortOrder,
            seedKey: c.seedKey,
          )
        else
          c,
    ],
    stores: stores,
    layout: layout,
    members: members,
  );

  Catalog withStoreLayout(
    String storeId,
    List<String> orderedIds,
    Set<String> hiddenIds,
  ) => Catalog(
    categories: categories,
    stores: stores,
    layout: [
      ...layout.where((row) => row.storeId != storeId),
      for (final (i, id) in orderedIds.indexed)
        StoreCategory(
          storeId: storeId,
          categoryId: id,
          sortOrder: (i + 1) * 10,
          hidden: hiddenIds.contains(id),
        ),
    ],
    members: members,
  );
}

/// A household member as the list names them.
@immutable
class const Member({
  required final String id,
  required final String displayName,
}) {
  factory fromJson(Map<String, Object?> json) => Member(
    id: json['id']! as String,
    displayName: json['display_name']! as String,
  );

  Map<String, Object?> toJson() => {'id': id, 'display_name': displayName};
}

/// Which shop the list is sorted for.
sealed class const StoreFilter();

/// Every active item in route order.
final class const AllStores() extends StoreFilter;

/// Items for one store (tagged to it or to no store), in its walking order.
final class const AtStore(final String storeId) extends StoreFilter;

/// A category in a view's order; `hidden` when the store does not carry it.
typedef Stop = ({Category category, bool hidden});

/// The categories in the order [filter] walks them. A store's layout rows
/// come first; categories it has no row for follow in route order.
List<Stop> walkingOrder(Catalog catalog, StoreFilter filter) {
  final route = [...catalog.categories]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  switch (filter) {
    case AllStores():
      return [for (final c in route) (category: c, hidden: false)];
    case AtStore(:final storeId):
      final rows =
          catalog.layout.where((row) => row.storeId == storeId).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final byId = {for (final c in route) c.id: c};
      final placed = {for (final row in rows) row.categoryId};
      return [
        for (final row in rows)
          if (byId[row.categoryId] case final c?)
            (category: c, hidden: row.hidden),
        for (final c in route)
          if (!placed.contains(c.id)) (category: c, hidden: false),
      ];
  }
}

@immutable
class const Item({
  required final String id,
  required final String name,
  required final ItemStatus status,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final String? quantity,

  /// Null only while a new item waits for the server to classify it.
  final String? categoryId,
  final String? storeId,
  final DateTime? boughtAt,

  /// The member who added it; null until the server confirms the add, and
  /// in snapshots older than the field.
  final String? addedBy,
}) {
  factory fromJson(Map<String, Object?> json) => Item(
    id: json['id']! as String,
    name: json['name']! as String,
    quantity: json['quantity'] as String?,
    categoryId: json['category_id'] as String?,
    storeId: json['store_id'] as String?,
    status: ItemStatus.values.byName(json['status']! as String),
    createdAt: DateTime.parse(json['created_at']! as String),
    updatedAt: DateTime.parse(json['updated_at']! as String),
    boughtAt: switch (json['bought_at']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    addedBy: json['added_by'] as String?,
  );

  /// The same keys as a server row, so [Item.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'category_id': categoryId,
    'store_id': storeId,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'bought_at': boughtAt?.toIso8601String(),
    'added_by': addedBy,
  };

  Item copyWith({
    String? name,
    String? Function()? quantity,
    String? categoryId,
    String? Function()? storeId,
    ItemStatus? status,
    DateTime? Function()? boughtAt,
  }) => Item(
    id: id,
    name: name ?? this.name,
    quantity: quantity == null ? this.quantity : quantity(),
    categoryId: categoryId ?? this.categoryId,
    storeId: storeId == null ? this.storeId : storeId(),
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    boughtAt: boughtAt == null ? this.boughtAt : boughtAt(),
    addedBy: addedBy,
  );

  /// Added by another member (not by [userId], and not still unconfirmed).
  bool isFromPartner(String userId) => addedBy != null && addedBy != userId;
}

/// A user's intent, applied optimistically on top of the server state until
/// the server acknowledges it. Every op is idempotent so it can be retried.
sealed class const ItemOp(final String itemId) {
  /// Reads what [toJson] wrote; throws on anything else.
  factory fromJson(Map<String, Object?> json) {
    final id = json['item_id']! as String;
    return switch (json['op']) {
      'add' => AddItem(Item.fromJson(json['item']! as Map<String, Object?>)),
      'status' => SetStatus(
        id,
        ItemStatus.values.byName(json['status']! as String),
        DateTime.parse(json['at']! as String),
        storeId: json['store_id'] as String?,
      ),
      'edit' => EditItem(
        id,
        name: json['name']! as String,
        quantity: json['quantity'] as String?,
        categoryId: json['category_id']! as String,
        storeId: json['store_id'] as String?,
      ),
      'move' => MoveItem(id, json['category_id']! as String),
      'delete' => DeleteItem(id),
      final op => throw FormatException('unknown op', op),
    };
  }

  /// The item as the user should see it once this op lands.
  Item? apply(Item? current);

  Map<String, Object?> toJson() => {
    'item_id': itemId,
    ...switch (this) {
      AddItem(:final item) => {'op': 'add', 'item': item.toJson()},
      SetStatus(:final status, :final at, :final storeId) => {
        'op': 'status',
        'status': status.name,
        'at': at.toIso8601String(),
        'store_id': storeId,
      },
      EditItem(
        :final name,
        :final quantity,
        :final categoryId,
        :final storeId,
      ) =>
        {
          'op': 'edit',
          'name': name,
          'quantity': quantity,
          'category_id': categoryId,
          'store_id': storeId,
        },
      MoveItem(:final categoryId) => {'op': 'move', 'category_id': categoryId},
      DeleteItem() => {'op': 'delete'},
    },
  };
}

final class AddItem(final Item item) extends ItemOp {
  this : super(item.id);

  @override
  Item? apply(Item? current) => current ?? item;
}

/// Ticking at a store ([storeId] set) also tags the item to that store.
final class const SetStatus(
  super.itemId,
  final ItemStatus status,
  final DateTime at, {
  final String? storeId,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    status: status,
    boughtAt: () => status == ItemStatus.bought ? at : null,
    storeId: storeId == null ? null : () => storeId,
  );
}

final class const EditItem(
  super.itemId, {
  required final String name,
  required final String? quantity,
  required final String categoryId,

  /// Null: any store.
  required final String? storeId,
}) extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(
    name: name,
    quantity: () => quantity,
    categoryId: categoryId,
    storeId: () => storeId,
  );
}

/// Drag to another group: only the category changes.
final class const MoveItem(super.itemId, final String categoryId)
    extends ItemOp {
  @override
  Item? apply(Item? current) => current?.copyWith(categoryId: categoryId);
}

final class const DeleteItem(super.itemId) extends ItemOp {
  @override
  Item? apply(Item? current) => null;
}

/// Server truth plus the pending ops folded on top: what the list shows.
Map<String, Item> visibleItems(
  Map<String, Item> server,
  Iterable<ItemOp> pending,
) {
  final view = Map.of(server);
  for (final op in pending) {
    final next = op.apply(view[op.itemId]);
    if (next == null) {
      view.remove(op.itemId);
    } else {
      view[op.itemId] = next;
    }
  }
  return view;
}

/// Merges a server row, ignoring echoes older than what is already known.
Map<String, Item> mergeServerRow(Map<String, Item> server, Item row) {
  final known = server[row.id];
  if (known != null && known.updatedAt.isAfter(row.updatedAt)) {
    return server;
  }
  return {...server, row.id: row};
}

@immutable
class const CategoryGroup(
  /// Null for items still being classified, and for items whose category is
  /// gone.
  final Category? category,
  final List<Item> items,
);

@immutable
class const Grouping(
  final List<CategoryGroup> groups,

  /// Untagged items in categories the store does not carry; shown only
  /// with `showHidden`.
  final int hiddenCount,
);

/// Active items grouped in [filter]'s walking order; unclassified first,
/// items of unknown categories last. At a store, items tagged to another
/// store are left out, and so are untagged items in a category the store
/// does not carry unless [showHidden]. [includeEmpty] adds every shown
/// category without items, as drop targets.
Grouping groupActive(
  Iterable<Item> items,
  Catalog catalog,
  StoreFilter filter, {
  bool showHidden = false,
  bool includeEmpty = false,
}) {
  final stops = walkingOrder(catalog, filter);
  final hidden = {
    for (final stop in stops)
      if (stop.hidden) stop.category.id,
  };
  var hiddenCount = 0;
  final byCategory = <String?, List<Item>>{};
  for (final item in items.where((i) => i.status == ItemStatus.active)) {
    switch (filter) {
      case AtStore(:final storeId)
          when item.storeId != null && item.storeId != storeId:
        continue;
      case AtStore()
          when item.storeId == null && hidden.contains(item.categoryId):
        hiddenCount++;
        if (showHidden) {
          byCategory.putIfAbsent(item.categoryId, () => []).add(item);
        }
      case _:
        byCategory.putIfAbsent(item.categoryId, () => []).add(item);
    }
  }
  for (final list in byCategory.values) {
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  final known = {for (final stop in stops) stop.category.id};
  final orphans = [
    for (final entry in byCategory.entries)
      if (entry.key != null && !known.contains(entry.key)) ...entry.value,
  ];
  return Grouping([
    if (byCategory[null] case final pending?) CategoryGroup(null, pending),
    for (final (:category, hidden: isHidden) in stops)
      if (byCategory[category.id] case final list?)
        CategoryGroup(category, list)
      else if (includeEmpty && (!isHidden || showHidden))
        CategoryGroup(category, const []),
    if (orphans.isNotEmpty) CategoryGroup(null, orphans),
  ], hiddenCount);
}

/// Bought items, most recent first.
List<Item> recentlyBought(Iterable<Item> items, {int limit = 20}) {
  final bought = items.where((i) => i.status == ItemStatus.bought).toList()
    ..sort(
      (a, b) =>
          (b.boughtAt ?? b.updatedAt).compareTo(a.boughtAt ?? a.updatedAt),
    );
  return bought.take(limit).toList();
}

/// Something the household buys again and again, as `public.suggest_items`
/// ranks it; [due] when its usual interval since the last purchase is up.
@immutable
class const Usual({
  required final String name,
  required final bool due,
  final String? quantity,
}) {
  factory fromJson(Map<String, Object?> json) => Usual(
    name: json['name']! as String,
    quantity: json['quantity'] as String?,
    due: json['due']! as bool,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'quantity': quantity,
    'due': due,
  };
}

/// What `public.normalize_item_name` makes of a name.
String foldName(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'\s+'), ' ');

/// [usuals] matching what is typed, as the server matches a prefix: names
/// starting with it first, then names with a word starting with it, each in
/// the server's order. Names already on the list are left out.
List<Usual> suggestUsuals(
  List<Usual> usuals,
  Iterable<Item> visible,
  String text, {
  int limit = 5,
}) {
  final prefix = foldName(text);
  if (prefix.isEmpty) {
    return const [];
  }
  final offList = _offList(usuals, visible);
  final words = RegExp('[ -]');
  return [
    ...offList.where((u) => foldName(u.name).startsWith(prefix)),
    ...offList.where((u) {
      final name = foldName(u.name);
      return !name.startsWith(prefix) &&
          name.split(words).any((w) => w.startsWith(prefix));
    }),
  ].take(limit).toList();
}

/// The due [usuals] not on the list, in the server's order.
List<Usual> dueUsualsOf(
  List<Usual> usuals,
  Iterable<Item> visible, {
  int limit = 10,
}) => _offList(usuals, visible).where((u) => u.due).take(limit).toList();

Iterable<Usual> _offList(List<Usual> usuals, Iterable<Item> visible) {
  final active = {
    for (final item in visible)
      if (item.status == ItemStatus.active) item.name.toLowerCase(),
  };
  return usuals.where((u) => !active.contains(u.name.toLowerCase()));
}

/// How far a user has looked at partner adds: everything created up to
/// [until] (null: from the beginning), plus the items in [ids] after it.
@immutable
class const SeenMark({
  final DateTime? until,
  final Set<String> ids = const {},
}) {
  factory fromJson(Map<String, Object?> json) => SeenMark(
    until: switch (json['until']) {
      final String at => DateTime.parse(at),
      _ => null,
    },
    ids: {for (final id in json['ids']! as List<Object?>) id! as String},
  );

  Map<String, Object?> toJson() => {
    'until': until?.toIso8601String(),
    'ids': [...ids],
  };

  /// Partner items created after [until], seen or not, ticked or not.
  Iterable<Item> _after(Iterable<Item> visible, String userId) {
    final since = until;
    return visible.where(
      (i) =>
          i.isFromPartner(userId) &&
          (since == null || i.createdAt.isAfter(since)),
    );
  }

  /// Ids of the partner items on the list [userId] has not seen yet.
  Set<String> fresh(Iterable<Item> visible, String userId) => {
    for (final item in _after(visible, userId))
      if (item.status == ItemStatus.active && !ids.contains(item.id)) item.id,
  };

  /// Marks [seenIds] as seen. Once every partner item on the list is seen,
  /// [until] moves past them, so [ids] stays small. A seen item keeps its
  /// id while it is known, so ticking and putting it back is no news.
  SeenMark marking(Set<String> seenIds, Iterable<Item> visible, String userId) {
    final after = _after(visible, userId).toList();
    final seen = {
      ...ids,
      ...seenIds,
    }.intersection({for (final item in after) item.id});
    final active = [
      for (final item in after)
        if (item.status == ItemStatus.active) item,
    ];
    if (active.isEmpty || !active.every((i) => seen.contains(i.id))) {
      return SeenMark(until: until, ids: seen);
    }
    final next = active
        .map((i) => i.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return SeenMark(
      until: next,
      ids: {
        for (final item in after)
          if (seen.contains(item.id) && item.createdAt.isAfter(next)) item.id,
      },
    );
  }
}
