import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class const Household({required final String id, required final String name});

sealed class const Session();

final class const SessionLoading() extends Session;

final class const SignedOut([
  /// Why the last sign-in failed, e.g. an error on a provider's return URL.
  final Exception? error,
]) extends Session;

final class const NeedsHousehold(final String userId) extends Session;

final class const InHousehold(final String userId, final Household household)
    extends Session;

/// A household RPC refused the request, e.g. an expired invite code.
final class const HouseholdError(
  /// The Postgres exception message, e.g. `invalid_invite`.
  final String code,
) implements Exception;

class SessionCubit(final SupabaseClient _client) extends Cubit<Session> {
  this : super(const SessionLoading()) {
    // Also replays a failed browser sign-in that supabase_flutter read from
    // the return URL before this cubit existed.
    _auth = _client.auth.onAuthStateChange.listen(
      (event) => unawaited(_load(event.session?.user.id)),
      onError: (Object e) => emit(SignedOut(e is Exception ? e : null)),
    );
  }

  late final StreamSubscription<AuthState> _auth;
  String? _loadedFor;
  Timer? _retry;

  Future<void> _load(String? userId) async {
    if (userId == null) {
      _loadedFor = null;
      emit(const SignedOut());
      return;
    }
    if (_loadedFor == userId && state is! SessionLoading) {
      return;
    }
    _loadedFor = userId;
    try {
      await refresh();
    } on Object {
      // Offline at start: keep the spinner and retry until the server answers.
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 3), () {
        if (!isClosed && _loadedFor == userId) {
          unawaited(_load(userId));
        }
      });
    }
  }

  Future<void> refresh() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      emit(const SignedOut());
      return;
    }
    final row = await _client
        .from('household_members')
        .select('households(id, name)')
        .eq('user_id', userId)
        .maybeSingle();
    final household = row?['households'];
    emit(switch (household) {
      {'id': final String id, 'name': final String name} => InHousehold(
        userId,
        Household(id: id, name: name),
      ),
      _ => NeedsHousehold(userId),
    });
  }

  Future<void> createHousehold(String name) =>
      _rpc('create_household', {'p_name': name});

  Future<void> join(String code) => _rpc('join_household', {'p_code': code});

  Future<void> signOut() => _client.auth.signOut();

  Future<void> _rpc(String fn, Map<String, Object?> params) async {
    try {
      await _client.rpc<Object?>(fn, params: params);
    } on PostgrestException catch (e) {
      throw HouseholdError(e.message);
    }
    await refresh();
  }

  @override
  Future<void> close() async {
    _retry?.cancel();
    await _auth.cancel();
    await super.close();
  }
}
