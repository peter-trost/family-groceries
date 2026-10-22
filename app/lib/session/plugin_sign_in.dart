import 'package:family_groceries/session/social_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [NativeSignIn] through Google Sign-In (Android Credential Manager, iOS
/// GoogleSignIn SDK) and sign_in_with_apple (iOS AuthenticationServices).
///
/// Google goes through the platform interface with only the Android and iOS
/// implementations as dependencies: the app-facing google_sign_in package
/// would add the web implementation, which loads Google's script on every
/// page although the web app signs in by redirect.
class PluginSignIn({
  /// Supabase verifies the ID token's audience against this client.
  required final String googleWebClientId,

  /// Null on Android, which finds its client by package name and SHA-1.
  final String? googleIosClientId,
}) implements NativeSignIn {
  Future<void>? _googleReady;

  @override
  Future<NativeCredential> signIn(
    SocialProvider provider, {
    required String hashedNonce,
  }) => switch (provider) {
    SocialProvider.google => _google(hashedNonce),
    SocialProvider.apple => _apple(hashedNonce),
  };

  Future<NativeCredential> _google(String hashedNonce) async {
    final google = GoogleSignInPlatform.instance;
    try {
      // Initialize exactly once per app run, as the plugin requires.
      await (_googleReady ??= google.init(
        InitParameters(
          clientId: googleIosClientId,
          serverClientId: googleWebClientId,
          nonce: hashedNonce,
        ),
      ));
      final result = await google.authenticate(const AuthenticateParameters());
      final idToken = result.authenticationTokens.idToken;
      if (idToken == null) {
        throw const AuthException('Google returned no ID token');
      }
      return (idToken: idToken, givenName: null, familyName: null);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialSignInCanceled();
      }
      throw AuthException(e.description ?? e.code.name);
    }
  }

  Future<NativeCredential> _apple(String hashedNonce) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('Apple returned no ID token');
      }
      return (
        idToken: idToken,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SocialSignInCanceled();
      }
      throw AuthException(e.message);
    }
  }
}
