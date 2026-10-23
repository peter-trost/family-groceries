import 'package:family_groceries/list/list_cache.dart';

/// A device cache that lives as long as the test; [saved] is its contents.
class MemoryListCache([var ListSnapshot? saved]) implements ListCache {
  @override
  Future<ListSnapshot?> load() async => saved;

  @override
  Future<void> save(ListSnapshot snapshot) async => saved = snapshot;
}
