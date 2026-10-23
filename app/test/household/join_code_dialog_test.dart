import 'package:family_groceries/household/invite_dialog.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'joining by code closes the dialog cleanly and opens the join route',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => showJoinCodeDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/join/:code',
            builder: (_, state) => Text('join ${state.pathParameters['code']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abcd-2345');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('join ABCD2345'), findsOneWidget);
    },
  );
}
