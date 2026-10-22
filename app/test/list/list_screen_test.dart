import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';

void main() {
  late FakeRepository repo;

  Future<void> pumpList(WidgetTester tester) async {
    repo = FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) => ListCubit(repo)..start(),
          child: const ShoppingList(
            household: Household(id: 'h', name: 'Trost'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder addField() => find.widgetWithText(TextField, 'Was fehlt?');

  testWidgets('the add field has focus on open', (tester) async {
    await pumpList(tester);
    final field = tester.widget<TextField>(addField());
    expect(field.focusNode!.hasFocus, isTrue);
    expect(
      find.text('Die Liste ist leer. Tippe oben ein, was fehlt.'),
      findsOneWidget,
    );
  });

  testWidgets('enter adds under its category and keeps focus', (tester) async {
    await pumpList(tester);
    await tester.enterText(addField(), 'Vollmilch');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('Kühlregal'), findsOneWidget);
    expect(find.text('Vollmilch'), findsOneWidget);
    expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
    expect(tester.widget<TextField>(addField()).controller!.text, isEmpty);
  });

  testWidgets('hardware enter adds once per press and keeps focus', (
    tester,
  ) async {
    await pumpList(tester);
    for (final name in ['Milch', 'Brot']) {
      await tester.enterText(addField(), name);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot']);
    expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
  });

  testWidgets('ticking offers undo', (tester) async {
    await pumpList(tester);
    await tester.enterText(addField(), 'Brot');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Brot abgehakt'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Brot'), findsNothing);

    await tester.tap(find.text('Rückgängig'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Brot'), findsOneWidget);
  });
}
