import 'package:family_groceries/list/list_cache.dart';
import 'package:family_groceries/list/model.dart';

/// A device cache that lives as long as the test; [saved] and [seen] are its
/// contents.
class MemoryListCache([var ListSnapshot? saved]) implements ListCache {
  SeenMark? seen;

  @override
  Future<ListSnapshot?> load() async => saved;

  @override
  Future<void> save(ListSnapshot snapshot) async => saved = snapshot;

  @override
  Future<SeenMark?> loadSeen() async => seen;

  @override
  Future<void> saveSeen(SeenMark mark) async => seen = mark;
}
