import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/oauth/consent_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeConsentApi({required final ConsentRequest details})
    implements ConsentApi {
  final decisions = <String>[];
  Exception? failure;

  @override
  Future<ConsentRequest> getDetails(String authorizationId) async {
    if (failure case final failure?) {
      throw failure;
    }
    return details;
  }

  @override
  Future<Uri> approve(String authorizationId) async {
    decisions.add('approve $authorizationId');
    return Uri.parse('https://client.example/cb?code=granted');
  }

  @override
  Future<Uri> deny(String authorizationId) async {
    decisions.add('deny $authorizationId');
    return Uri.parse('https://client.example/cb?error=access_denied');
  }
}

void main() {
  const request = NeedsConsent(
    clientName: 'Claude',
    clientUri: 'https://claude.ai',
    email: 'peter@example.com',
    scopes: ['openid', 'email', 'offline_access', 'custom:thing'],
  );
  late FakeConsentApi api;
  late List<Uri> visited;

  Future<void> pumpConsent(
    WidgetTester tester, {
    ConsentRequest details = request,
    String? id = 'auth-1',
    Exception? failure,
  }) async {
    api = FakeConsentApi(details: details)..failure = failure;
    visited = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: ConsentView(
          authorizationId: id,
          household: const Household(id: 'h', name: 'Trost'),
          api: api,
          navigate: (url) async => visited.add(url),
        ),
      ),
    );
    // Not pumpAndSettle: the redirect spinner never settles.
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<ButtonStyleButton>(),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the client, account, household and scopes', (
    tester,
  ) async {
    await pumpConsent(tester);
    expect(find.text('Zugriff erlauben?'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('https://claude.ai'), findsOneWidget);
    expect(find.text('Angemeldet als peter@example.com'), findsOneWidget);
    expect(find.text('Haushalt: Trost'), findsOneWidget);
    const listAccess =
        'Einträge deiner Einkaufsliste lesen, hinzufügen, abhaken und '
        'verschieben';
    for (final label in [
      listAccess,
      'Deine Anmeldung bestätigen',
      'Deine E-Mail-Adresse',
      'Dauerhaft angemeldet bleiben',
      'custom:thing',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(visited, isEmpty);
  });

  testWidgets('allow approves and follows the redirect', (tester) async {
    await pumpConsent(tester);
    await tapButton(tester, 'Erlauben');
    expect(api.decisions, ['approve auth-1']);
    expect(visited, [Uri.parse('https://client.example/cb?code=granted')]);
    expect(find.text('Weiterleitung …'), findsOneWidget);
    final allow = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Erlauben'),
    );
    expect(allow.onPressed, isNull);
  });

  testWidgets('deny denies and follows the redirect', (tester) async {
    await pumpConsent(tester);
    await tapButton(tester, 'Ablehnen');
    expect(api.decisions, ['deny auth-1']);
    expect(visited, [
      Uri.parse('https://client.example/cb?error=access_denied'),
    ]);
  });

  testWidgets('an earlier approval redirects without asking', (tester) async {
    await pumpConsent(
      tester,
      details: AlreadyApproved(Uri.parse('https://client.example/cb?code=x')),
    );
    expect(visited, [Uri.parse('https://client.example/cb?code=x')]);
    expect(find.text('Erlauben'), findsNothing);
    expect(api.decisions, isEmpty);
  });

  testWidgets('an expired request explains itself', (tester) async {
    await pumpConsent(
      tester,
      failure: const AuthException('authorization not found'),
    );
    expect(
      find.text(
        'Diese Anfrage ist ungültig oder abgelaufen. '
        'Starte die Verbindung in deiner App neu.',
      ),
      findsOneWidget,
    );
    expect(find.text('authorization not found'), findsOneWidget);
    expect(find.text('Erlauben'), findsNothing);
  });

  testWidgets('a missing authorization id explains itself', (tester) async {
    await pumpConsent(tester, id: null);
    expect(find.textContaining('ungültig oder abgelaufen'), findsOneWidget);
    expect(visited, isEmpty);
  });
}
