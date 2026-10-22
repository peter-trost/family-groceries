import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth.dart';

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  group('socialFlows', () {
    const all = (
      googleWebClientId: 'web.apps.googleusercontent.com',
      googleIosClientId: 'ios.apps.googleusercontent.com',
      apple: true,
    );
    const none = (googleWebClientId: '', googleIosClientId: '', apple: false);
    const g = SocialProvider.google;
    const a = SocialProvider.apple;
    final cases = <(String, SocialConfig, bool, TargetPlatform, Object)>[
      (
        'web',
        all,
        true,
        TargetPlatform.linux,
        {g: SignInFlow.redirect, a: SignInFlow.redirect},
      ),
      (
        'iOS',
        all,
        false,
        TargetPlatform.iOS,
        {g: SignInFlow.native, a: SignInFlow.native},
      ),
      (
        'Android',
        all,
        false,
        TargetPlatform.android,
        {g: SignInFlow.native, a: SignInFlow.redirect},
      ),
      ('unconfigured web', none, true, TargetPlatform.linux, <Never, Never>{}),
      ('unconfigured iOS', none, false, TargetPlatform.iOS, <Never, Never>{}),
      (
        'iOS without an iOS client ID',
        (googleWebClientId: 'web', googleIosClientId: '', apple: false),
        false,
        TargetPlatform.iOS,
        <Never, Never>{},
      ),
      (
        'Google only on Android',
        (googleWebClientId: 'web', googleIosClientId: '', apple: false),
        false,
        TargetPlatform.android,
        {g: SignInFlow.native},
      ),
      ('desktop', all, false, TargetPlatform.linux, <Never, Never>{}),
    ];
    for (final (name, config, web, platform, expected) in cases) {
      test(name, () {
        expect(socialFlows(config, web: web, platform: platform), expected);
      });
    }
  });

  group('native sign-in', () {
    late FakeAuth auth;
    late FakeNativeSignIn native;
    var nonces = 0;

    SocialSignIn build() => SocialSignIn(
      auth,
      flows: const {
        SocialProvider.google: SignInFlow.native,
        SocialProvider.apple: SignInFlow.native,
      },
      native: native,
      newNonce: () => 'raw-nonce-${nonces++}',
    );

    setUp(() {
      auth = FakeAuth();
      native = FakeNativeSignIn();
      nonces = 0;
    });

    test(
      'Google: the provider gets the hashed nonce, Supabase the raw one',
      () async {
        await build().signIn(SocialProvider.google);

        expect(native.hashedNonces, [
          (SocialProvider.google, sha256Hex('raw-nonce-0')),
        ]);
        expect(auth.idTokenCalls, [
          (
            provider: OAuthProvider.google,
            idToken: 'id-token',
            nonce: 'raw-nonce-0',
          ),
        ]);
        expect(auth.metadataUpdates, isEmpty);
      },
    );

    test(
      'Google keeps one nonce per app run; Apple gets a fresh one',
      () async {
        final social = build();
        await social.signIn(SocialProvider.google);
        await social.signIn(SocialProvider.apple);
        await social.signIn(SocialProvider.google);
        await social.signIn(SocialProvider.apple);

        expect(auth.idTokenCalls.map((c) => (c.provider, c.nonce)), [
          (OAuthProvider.google, 'raw-nonce-0'),
          (OAuthProvider.apple, 'raw-nonce-1'),
          (OAuthProvider.google, 'raw-nonce-0'),
          (OAuthProvider.apple, 'raw-nonce-2'),
        ]);
        for (final (i, (provider, hashed)) in native.hashedNonces.indexed) {
          expect(provider.oauth, auth.idTokenCalls[i].provider);
          expect(hashed, sha256Hex(auth.idTokenCalls[i].nonce!));
        }
      },
    );

    test("Apple's first sign-in stores the name it sends only once", () async {
      native.result = (
        idToken: 'apple-token',
        givenName: 'Lea',
        familyName: 'Trost',
      );
      await build().signIn(SocialProvider.apple);

      expect(auth.idTokenCalls.single.provider, OAuthProvider.apple);
      expect(auth.idTokenCalls.single.idToken, 'apple-token');
      expect(auth.metadataUpdates, [
        {'full_name': 'Lea Trost', 'given_name': 'Lea', 'family_name': 'Trost'},
      ]);
    });

    test('a later Apple sign-in without a name keeps the stored one', () async {
      native.result = (idToken: 'apple-token', givenName: null, familyName: '');
      await build().signIn(SocialProvider.apple);

      expect(auth.idTokenCalls, hasLength(1));
      expect(auth.metadataUpdates, isEmpty);
    });

    test('cancel reaches the caller and never calls Supabase', () async {
      native.error = const SocialSignInCanceled();
      await expectLater(
        build().signIn(SocialProvider.google),
        throwsA(isA<SocialSignInCanceled>()),
      );
      expect(auth.idTokenCalls, isEmpty);
    });

    test('a rejected ID token surfaces as an AuthException', () async {
      auth.idTokenError = const AuthException('Nonces mismatch');
      await expectLater(
        build().signIn(SocialProvider.apple),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Nonces mismatch',
          ),
        ),
      );
    });
  });

  group('redirect sign-in', () {
    test('opens the authorize URL for the provider and return URL', () async {
      final launched = <(OAuthProvider, String?)>[];
      final social = SocialSignIn(
        FakeAuth(),
        flows: const {SocialProvider.apple: SignInFlow.redirect},
        native: FakeNativeSignIn(),
        launch: (provider, {redirectTo}) async {
          launched.add((provider, redirectTo));
          return true;
        },
      );
      await social.signIn(SocialProvider.apple, redirectTo: mobileAuthCallback);
      expect(launched, [(OAuthProvider.apple, mobileAuthCallback)]);
    });

    test('no browser to open is an error', () async {
      final social = SocialSignIn(
        FakeAuth(),
        flows: const {SocialProvider.google: SignInFlow.redirect},
        native: FakeNativeSignIn(),
        launch: (_, {redirectTo}) async => false,
      );
      await expectLater(
        social.signIn(SocialProvider.google),
        throwsA(isA<AuthException>()),
      );
    });
  });
}
