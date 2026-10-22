import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SocialProvider(final OAuthProvider oauth) {
  google(OAuthProvider.google),
  apple(OAuthProvider.apple),
}

/// How a provider signs in on one platform.
enum SignInFlow() {
  /// The platform's own dialog returns an ID token for `signInWithIdToken`.
  native,

  /// The browser opens Supabase's authorize URL and returns with a code.
  redirect,
}

/// The public, per-build provider settings from `Environment`.
typedef SocialConfig = ({
  String googleWebClientId,
  String googleIosClientId,
  bool apple,
});

/// The providers a build offers and their flow. Unconfigured providers are
/// absent, so their buttons never show.
Map<SocialProvider, SignInFlow> socialFlows(
  SocialConfig config, {
  required bool web,
  required TargetPlatform platform,
}) {
  final google = config.googleWebClientId.isEmpty
      ? null
      : web
      ? SignInFlow.redirect
      : switch (platform) {
          TargetPlatform.android => SignInFlow.native,
          TargetPlatform.iOS when config.googleIosClientId.isNotEmpty =>
            SignInFlow.native,
          _ => null,
        };
  final apple = !config.apple
      ? null
      : web
      ? SignInFlow.redirect
      : switch (platform) {
          TargetPlatform.iOS => SignInFlow.native,
          TargetPlatform.android => SignInFlow.redirect,
          _ => null,
        };
  return {SocialProvider.google: ?google, SocialProvider.apple: ?apple};
}

/// Where Supabase sends the mobile apps back to after a browser sign-in or a
/// magic link. Registered in the Android manifest and the iOS Info.plist.
const mobileAuthCallback = 'com.petertrost.familygroceries://login-callback';

/// The user closed the provider's dialog; nothing to report.
final class const SocialSignInCanceled() implements Exception;

/// What a provider's native dialog returns. Apple sends the name only on the
/// very first sign-in, and never inside the ID token.
typedef NativeCredential = ({
  String idToken,
  String? givenName,
  String? familyName,
});

/// A provider's own sign-in dialog. Implementations throw
/// [SocialSignInCanceled] when the user backs out and [AuthException] on
/// any other failure.
abstract interface class NativeSignIn() {
  /// [hashedNonce] is the SHA-256 hex digest of the nonce later sent to
  /// Supabase; the provider embeds it in the ID token.
  Future<NativeCredential> signIn(
    SocialProvider provider, {
    required String hashedNonce,
  });
}

typedef OAuthLauncher = Future<bool> Function(
  OAuthProvider provider, {
  String? redirectTo,
});

class SocialSignIn(
  final GoTrueClient _auth, {
  required final Map<SocialProvider, SignInFlow> flows,
  required final NativeSignIn _native,
  OAuthLauncher? launch,
  String Function()? newNonce,
}) {
  this {
    // google_sign_in takes its nonce once per app run, in `initialize`.
    _googleNonce = _newNonce();
  }

  final OAuthLauncher _launch =
      launch ??
      (provider, {redirectTo}) => _auth.signInWithOAuth(
        provider,
        redirectTo: redirectTo,
        // On Android, the system browser hands the deep link back to the app.
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
  final String Function() _newNonce = newNonce ?? _randomNonce;
  late final String _googleNonce;

  /// Signs in with [provider]. A redirect flow leaves the page (web) or opens
  /// the browser (Android) and completes when Supabase sends the user back to
  /// [redirectTo].
  Future<void> signIn(SocialProvider provider, {String? redirectTo}) async {
    switch (flows[provider]) {
      case null:
        throw StateError('$provider is not configured in this build');
      case SignInFlow.redirect:
        if (!await _launch(provider.oauth, redirectTo: redirectTo)) {
          throw const AuthException('browser_unavailable');
        }
      case SignInFlow.native:
        final nonce = provider == SocialProvider.google
            ? _googleNonce
            : _newNonce();
        final credential = await _native.signIn(
          provider,
          hashedNonce: sha256.convert(utf8.encode(nonce)).toString(),
        );
        await _auth.signInWithIdToken(
          provider: provider.oauth,
          idToken: credential.idToken,
          nonce: nonce,
        );
        await _saveName(credential);
    }
  }

  /// Supabase only sees the ID token, which never carries Apple's name.
  /// The profile trigger copies `full_name` into `profiles.display_name`.
  Future<void> _saveName(NativeCredential credential) async {
    final parts = [
      credential.givenName,
      credential.familyName,
    ].nonNulls.map((p) => p.trim()).where((p) => p.isNotEmpty);
    if (parts.isEmpty) {
      return;
    }
    try {
      await _auth.updateUser(
        UserAttributes(
          data: {
            'full_name': parts.join(' '),
            'given_name': ?credential.givenName,
            'family_name': ?credential.familyName,
          },
        ),
      );
    } on Exception {
      // The user is signed in; a lost name must not turn that into an error.
    }
  }
}

String _randomNonce() {
  final random = Random.secure();
  return base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
}
