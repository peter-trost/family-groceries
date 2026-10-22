import 'dart:async';

import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef IdTokenCall = ({OAuthProvider provider, String idToken, String? nonce});

/// Records what the app sends to Supabase Auth.
class FakeAuth() extends Fake implements GoTrueClient {
  final states = StreamController<AuthState>.broadcast();
  final idTokenCalls = <IdTokenCall>[];
  final metadataUpdates = <Map<String, Object?>>[];
  Exception? idTokenError;

  @override
  Stream<AuthState> get onAuthStateChange => states.stream;

  Future<void> close() => states.close();

  @override
  Future<AuthResponse> signInWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
    String? captchaToken,
  }) async {
    if (idTokenError case final error?) {
      throw error;
    }
    idTokenCalls.add((provider: provider, idToken: idToken, nonce: nonce));
    return AuthResponse();
  }

  @override
  Future<UserResponse> updateUser(
    UserAttributes attributes, {
    String? emailRedirectTo,
  }) async {
    metadataUpdates.add(attributes.data! as Map<String, Object?>);
    return UserResponse.fromJson({});
  }
}

class FakeClient(final FakeAuth fakeAuth)
    extends Fake
    implements SupabaseClient {
  @override
  GoTrueClient get auth => fakeAuth;
}

/// A provider dialog that answers with [result] or throws [error].
class FakeNativeSignIn() extends Fake implements NativeSignIn {
  final hashedNonces = <(SocialProvider, String)>[];
  NativeCredential result = (
    idToken: 'id-token',
    givenName: null,
    familyName: null,
  );
  Exception? error;

  @override
  Future<NativeCredential> signIn(
    SocialProvider provider, {
    required String hashedNonce,
  }) async {
    hashedNonces.add((provider, hashedNonce));
    if (error case final error?) {
      throw error;
    }
    return result;
  }
}
