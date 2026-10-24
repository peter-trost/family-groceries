import 'package:flutter/foundation.dart' show immutable;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A personal access token as the settings list shows it. The secret itself
/// is never readable after creation.
@immutable
class const AccessToken({
  required final String id,
  required final String name,

  /// The last four characters, to tell tokens apart.
  required final String hint,
  required final DateTime createdAt,
  final DateTime? lastUsedAt,
}) {
  factory fromJson(Map<String, dynamic> json) => AccessToken(
    id: json['id']! as String,
    name: json['name']! as String,
    hint: json['token_hint']! as String,
    createdAt: DateTime.parse(json['created_at']! as String).toLocal(),
    lastUsedAt: switch (json['last_used_at']) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    },
  );
}

/// A freshly created token; [token] is the only copy of the secret.
@immutable
class const NewToken({required final String name, required final String token});

/// An OAuth client the user granted access to.
@immutable
class const ConnectedApp({
  required final String clientId,
  required final String name,
  required final DateTime grantedAt,
  required final List<String> scopes,
});

/// The server refused a request; [code] is its message, e.g.
/// `too_many_tokens`.
final class const AccessError(final String code) implements Exception;

/// The settings screen's only door to the backend.
abstract interface class AccessRepository() {
  /// Active tokens, newest first. Revoked tokens are not listed.
  Future<List<AccessToken>> fetchTokens();

  Future<NewToken> createToken(String name);

  Future<void> revokeToken(String id);

  Future<List<ConnectedApp>> fetchApps();

  Future<void> disconnect(String clientId);
}

class SupabaseAccessRepository(final SupabaseClient _client)
    implements AccessRepository {
  @override
  Future<List<AccessToken>> fetchTokens() => _guard(() async {
    final rows = await _client.rest
        .from('personal_access_tokens')
        .select('id, name, token_hint, created_at, last_used_at')
        .isFilter('revoked_at', null)
        .order('created_at', ascending: false);
    return rows.map(AccessToken.fromJson).toList();
  });

  @override
  Future<NewToken> createToken(String name) => _guard(() async {
    final row = await _client
        .rpc<List<Map<String, dynamic>>>(
          'create_personal_access_token',
          params: {'p_name': name},
        )
        .single();
    return NewToken(
      name: row['name']! as String,
      token: row['token']! as String,
    );
  });

  @override
  Future<void> revokeToken(String id) => _guard(
    () => _client.rest
        .from('personal_access_tokens')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id),
  );

  @override
  Future<List<ConnectedApp>> fetchApps() => _guard(() async {
    final grants = await _client.auth.oauth.listGrants();
    return [
      for (final grant in grants)
        ConnectedApp(
          clientId: grant.client.clientId,
          name: grant.client.clientName ?? grant.client.clientId,
          grantedAt: grant.grantedAt.toLocal(),
          scopes: grant.scopes,
        ),
    ];
  });

  @override
  Future<void> disconnect(String clientId) =>
      _guard(() => _client.auth.oauth.revokeGrant(clientId));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      throw AccessError(e.message);
    } on AuthException catch (e) {
      throw AccessError(e.message);
    }
  }
}
