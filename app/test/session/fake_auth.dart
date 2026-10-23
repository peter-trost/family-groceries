import 'dart:async';
import 'dart:io';

import 'package:family_groceries/session/session_cubit.dart';
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
  User? user;

  @override
  Stream<AuthState> get onAuthStateChange => states.stream;

  @override
  User? get currentUser => user;

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

/// A client whose database is unreachable.
class FakeClient(final FakeAuth fakeAuth)
    extends Fake
    implements SupabaseClient {
  @override
  GoTrueClient get auth => fakeAuth;

  @override
  SupabaseQueryBuilder from(String table) =>
      throw const SocketException('offline');
}

/// The device cache, in memory; [households] is its contents.
class MemorySessionCache() implements SessionCache {
  final households = <String, Household>{};
  var forgotten = 0;

  @override
  Future<Household?> household(String userId) async => households[userId];

  @override
  Future<void> remember(String userId, Household? household) async {
    if (household == null) {
      households.remove(userId);
    } else {
      households[userId] = household;
    }
  }

  @override
  Future<void> forget() async {
    households.clear();
    forgotten++;
  }
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
