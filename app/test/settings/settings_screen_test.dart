import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/settings/access_repository.dart';
import 'package:family_groceries/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAccessRepository() implements AccessRepository {
  final tokens = <AccessToken>[];
  final revoked = <String>[];
  final apps = <ConnectedApp>[];
  final disconnected = <String>[];
  var limitReached = false;

  @override
  Future<List<AccessToken>> fetchTokens() async => [
    for (final t in tokens.reversed)
      if (!revoked.contains(t.id)) t,
  ];

  @override
  Future<NewToken> createToken(String name) async {
    if (limitReached) {
      throw const AccessError('too_many_tokens');
    }
    const token = 'fgp_secretsecretsecretsecretsecretsecret1234';
    tokens.add(
      AccessToken(
        id: 't${tokens.length}',
        name: name,
        hint: '1234',
        createdAt: DateTime(2026, 10, 22),
      ),
    );
    return NewToken(name: name, token: token);
  }

  @override
  Future<void> revokeToken(String id) async => revoked.add(id);

  @override
  Future<List<ConnectedApp>> fetchApps() async => [
    for (final a in apps)
      if (!disconnected.contains(a.clientId)) a,
  ];

  @override
  Future<void> disconnect(String clientId) async => disconnected.add(clientId);
}

void main() {
  late FakeAccessRepository repo;

  Future<void> pumpSettings(
    WidgetTester tester, {
    void Function(FakeAccessRepository repo)? seed,
  }) async {
    repo = FakeAccessRepository();
    seed?.call(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: SettingsScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  const secret = 'fgp_secretsecretsecretsecretsecretsecret1234';

  testWidgets('shows the MCP endpoint and empty sections', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Zugänge'), findsOneWidget);
    expect(find.textContaining('/functions/v1/mcp'), findsOneWidget);
    expect(find.text('Kein aktiver Token.'), findsOneWidget);
    expect(find.text('Noch keine App verbunden.'), findsOneWidget);
  });

  testWidgets('a new token is shown once, then only its hint', (tester) async {
    await pumpSettings(tester);
    await tapText(tester, 'Token erstellen');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Claude');
    await tapText(tester, 'Erstellen');

    expect(find.text(secret), findsOneWidget);
    expect(
      find.text(
        'Kopiere den Token jetzt. Er wird nicht noch einmal angezeigt.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Fertig');

    expect(find.text(secret), findsNothing);
    expect(find.text('Claude'), findsOneWidget);
    expect(
      find.text('…1234 · Erstellt am 22.10.2026 · Noch nie benutzt'),
      findsOneWidget,
    );
  });

  testWidgets('the token limit is explained', (tester) async {
    await pumpSettings(tester, seed: (r) => r.limitReached = true);
    await tapText(tester, 'Token erstellen');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Siri');
    await tapText(tester, 'Erstellen');
    expect(find.text('Höchstens 20 aktive Tokens.'), findsOneWidget);
    expect(find.textContaining('fgp_'), findsNothing);
  });

  testWidgets('revoking asks first, then removes the token', (tester) async {
    await pumpSettings(
      tester,
      seed: (r) => r.tokens.add(
        AccessToken(
          id: 'siri',
          name: 'Siri',
          hint: 'abcd',
          createdAt: DateTime(2026, 10, 2),
          lastUsedAt: DateTime(2026, 10, 20),
        ),
      ),
    );
    expect(
      find.text('…abcd · Erstellt am 2.10.2026 · Zuletzt benutzt 20.10.2026'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Siri widerrufen'));
    await tester.pumpAndSettle();
    expect(find.text('Token widerrufen?'), findsOneWidget);
    await tapText(tester, 'Abbrechen');
    expect(repo.revoked, isEmpty);

    await tester.tap(find.byTooltip('Siri widerrufen'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Widerrufen');
    expect(repo.revoked, ['siri']);
    expect(find.text('Siri'), findsNothing);
    expect(find.text('Kein aktiver Token.'), findsOneWidget);
  });

  testWidgets('connected apps can be disconnected', (tester) async {
    await pumpSettings(
      tester,
      seed: (r) => r.apps.add(
        ConnectedApp(
          clientId: 'client-1',
          name: 'Claude',
          grantedAt: DateTime(2026, 10, 21),
          scopes: const ['openid', 'email'],
        ),
      ),
    );
    expect(find.text('Claude'), findsOneWidget);
    expect(
      find.text(
        'Verbunden am 21.10.2026 · Deine Anmeldung bestätigen · '
        'Deine E-Mail-Adresse',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Claude trennen'));
    await tester.pumpAndSettle();
    expect(find.text('Claude trennen?'), findsOneWidget);
    await tapText(tester, 'Trennen');
    expect(repo.disconnected, ['client-1']);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('Noch keine App verbunden.'), findsOneWidget);
  });
}
