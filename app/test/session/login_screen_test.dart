import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth.dart';

void main() {
  late FakeAuth auth;
  late FakeNativeSignIn native;

  const both = {
    SocialProvider.google: SignInFlow.native,
    SocialProvider.apple: SignInFlow.native,
  };

  Future<void> pumpLogin(
    WidgetTester tester, {
    Map<SocialProvider, SignInFlow> flows = both,
    Exception? returnError,
  }) async {
    auth = FakeAuth();
    addTearDown(auth.close);
    native = FakeNativeSignIn();
    final session = SessionCubit(FakeClient(auth));
    addTearDown(session.close);
    auth.states.add(const AuthState(AuthChangeEvent.initialSession, null));
    if (returnError != null) {
      auth.states.addError(returnError);
    }
    await tester.pump();
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: SocialSignIn(auth, flows: flows, native: native),
        child: BlocProvider.value(
          value: session,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('de'),
            home: LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder google() => find.bySemanticsLabel('Mit Google anmelden');
  Finder apple() => find.bySemanticsLabel('Mit Apple anmelden');

  testWidgets('shows every configured method', (tester) async {
    await pumpLogin(tester);
    expect(google(), findsOneWidget);
    expect(apple(), findsOneWidget);
    expect(find.text('oder mit E-Mail'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'E-Mail'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
    expect(find.text('Anmeldelink per E-Mail senden'), findsOneWidget);
  });

  testWidgets('hides providers the build has not configured', (tester) async {
    await pumpLogin(tester, flows: const {});
    expect(google(), findsNothing);
    expect(apple(), findsNothing);
    expect(find.text('oder mit E-Mail'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'E-Mail'), findsOneWidget);
  });

  testWidgets('shows only Google when Apple is not configured', (tester) async {
    await pumpLogin(
      tester,
      flows: const {SocialProvider.google: SignInFlow.native},
    );
    expect(google(), findsOneWidget);
    expect(apple(), findsNothing);
  });

  testWidgets('Google signs in with an ID token', (tester) async {
    await pumpLogin(tester);
    await tester.tap(google());
    await tester.pumpAndSettle();
    expect(auth.idTokenCalls.single.provider, OAuthProvider.google);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Apple signs in with an ID token', (tester) async {
    await pumpLogin(tester);
    await tester.tap(apple());
    await tester.pumpAndSettle();
    expect(auth.idTokenCalls.single.provider, OAuthProvider.apple);
  });

  testWidgets('cancel says so in German and re-enables the buttons', (
    tester,
  ) async {
    await pumpLogin(tester);
    native.error = const SocialSignInCanceled();
    await tester.tap(apple());
    await tester.pumpAndSettle();
    expect(find.text('Anmeldung abgebrochen'), findsOneWidget);
    expect(auth.idTokenCalls, isEmpty);

    native.error = null;
    await tester.tap(google());
    await tester.pumpAndSettle();
    expect(auth.idTokenCalls, hasLength(1));
  });

  testWidgets('a provider error is shown in German', (tester) async {
    await pumpLogin(tester);
    native.error = const AuthException('Unacceptable audience');
    await tester.tap(google());
    await tester.pumpAndSettle();
    expect(
      find.text('Anmeldung fehlgeschlagen: Unacceptable audience'),
      findsOneWidget,
    );
  });

  testWidgets('a failed browser sign-in is reported on return', (tester) async {
    await pumpLogin(
      tester,
      returnError: const AuthException('Error getting user email'),
    );
    expect(
      find.text('Anmeldung fehlgeschlagen: Error getting user email'),
      findsOneWidget,
    );
  });

  testWidgets('a canceled browser sign-in is reported on return', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      returnError: const AuthException(
        'The user denied the request',
        code: 'access_denied',
      ),
    );
    expect(find.text('Anmeldung abgebrochen'), findsOneWidget);
  });
}
