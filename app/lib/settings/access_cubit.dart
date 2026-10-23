import 'package:family_groceries/settings/access_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';

/// One independently loaded section of the screen.
sealed class const Section<T>();

final class const SectionLoading<T>() extends Section<T>;

final class const SectionLoaded<T>(final T value) extends Section<T>;

final class const SectionFailed<T>(final String message) extends Section<T>;

@immutable
class const AccessState({
  final Section<List<AccessToken>> tokens = const SectionLoading(),
  final Section<List<ConnectedApp>> apps = const SectionLoading(),
});

class AccessCubit(final AccessRepository _repo) extends Cubit<AccessState> {
  this : super(const AccessState());

  Future<void> load() => Future.wait([_loadTokens(), _loadApps()]);

  /// Throws [AccessError], e.g. `too_many_tokens`.
  Future<NewToken> create(String name) async {
    final token = await _repo.createToken(name);
    await _loadTokens();
    return token;
  }

  Future<void> revoke(String id) async {
    await _repo.revokeToken(id);
    await _loadTokens();
  }

  Future<void> disconnect(String clientId) async {
    await _repo.disconnect(clientId);
    await _loadApps();
  }

  Future<void> _loadTokens() async {
    final tokens = await _section(_repo.fetchTokens);
    if (!isClosed) {
      emit(AccessState(tokens: tokens, apps: state.apps));
    }
  }

  Future<void> _loadApps() async {
    final apps = await _section(_repo.fetchApps);
    if (!isClosed) {
      emit(AccessState(tokens: state.tokens, apps: apps));
    }
  }

  static Future<Section<T>> _section<T>(Future<T> Function() fetch) async {
    try {
      return SectionLoaded(await fetch());
    } on Object catch (e) {
      return SectionFailed(e is AccessError ? e.code : '$e');
    }
  }
}
