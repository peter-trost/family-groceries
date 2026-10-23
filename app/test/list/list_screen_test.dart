import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

void main() {
  late FakeRepository repo;

  Future<void> pumpList(
    WidgetTester tester, {
    void Function(FakeRepository repo)? seed,
  }) async {
    repo = FakeRepository();
    seed?.call(repo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) =>
              ListCubit(repo, MemoryListCache(), userId: 'peter')..start(),
          child: const ShoppingList(
            household: Household(id: 'h', name: 'Trost'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder addField() => find.widgetWithText(TextField, 'Was fehlt?');
  Finder chip(String name) => find.widgetWithText(ChoiceChip, name);
  List<String> headings(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.descendant(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.header ?? false),
          ),
        ),
        matching: find.byType(Text),
      ),
    ))
      text.data!,
  ];

  testWidgets('the add field has focus on open, with the store picker', (
    tester,
  ) async {
    await pumpList(tester);
    final field = tester.widget<TextField>(addField());
    expect(field.focusNode!.hasFocus, isTrue);
    expect(
      tester.getSemantics(chip('Alle')),
      isSemantics(label: 'Alle', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(chip('dm')),
      isSemantics(label: 'dm', isButton: true, isSelected: false),
    );
    expect(find.byTooltip('Reihenfolge bearbeiten'), findsNothing);
    expect(
      find.text('Die Liste ist leer. Tippe oben ein, was fehlt.'),
      findsOneWidget,
    );
  });

  testWidgets('a group heading is its own semantics node', (tester) async {
    await pumpList(tester);
    await tester.enterText(addField(), 'Vollmilch');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Kühlregal')),
      isSemantics(label: 'Kühlregal', isHeader: true),
    );
    expect(
      tester.getSemantics(find.text('Kühlregal')).parent?.getSemanticsData(),
      isNot(isSemantics(isButton: true)),
      reason: 'the heading does not sit inside the item row',
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

  testWidgets('a long paste is capped at the server limit', (tester) async {
    await pumpList(tester);
    await tester.enterText(addField(), 'x' * 130);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(repo.rows.values.single.name, hasLength(120));
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
  testWidgets('the store picker sorts and filters the list for a store', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: (repo) => repo
        ..remoteAdd('Äpfel', categoryId: 'produce')
        ..remoteAdd('Milch')
        ..remoteAdd('Seife', storeId: 'dm'),
    );
    expect(headings(tester), ['Obst & Gemüse', 'Kühlregal', 'Sonstiges']);

    await tester.tap(chip('Lidl'));
    await tester.pumpAndSettle();
    expect(headings(tester), ['Kühlregal', 'Obst & Gemüse']);
    expect(find.text('Seife'), findsNothing);
    expect(tester.getSemantics(chip('Lidl')), isSemantics(isSelected: true));

    await tester.tap(chip('dm'));
    await tester.pumpAndSettle();
    expect(headings(tester), ['Sonstiges']);
    final show = find.text(
      '2 Artikel, die es bei dm meist nicht gibt, anzeigen',
    );
    await tester.tap(show);
    await tester.pumpAndSettle();
    expect(headings(tester), ['Sonstiges', 'Obst & Gemüse', 'Kühlregal']);
    await tester.tap(
      find.text('2 Artikel, die es bei dm meist nicht gibt, ausblenden'),
    );
    await tester.pumpAndSettle();
    expect(headings(tester), ['Sonstiges']);
    expect(find.byTooltip('Reihenfolge bearbeiten'), findsOneWidget);
  });

  testWidgets('an item added in a store view stays there', (tester) async {
    await pumpList(tester);
    await tester.tap(chip('dm'));
    await tester.pumpAndSettle();
    await tester.enterText(addField(), 'Vollmilch');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(repo.rows.values.single.storeId, 'dm');
    expect(find.widgetWithText(ListTile, 'Vollmilch'), findsOneWidget);
  });

  testWidgets('the edit sheet tags an item to a store', (tester) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Brot'));
    await tester.tap(find.widgetWithText(ListTile, 'Brot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle Geschäfte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lidl').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(repo.rows.values.single.storeId, 'lidl');
  });

  testWidgets('long-press dragging an item onto a category moves it', (
    tester,
  ) async {
    await pumpList(tester, seed: (repo) => repo.remoteAdd('Milch'));
    expect(headings(tester), ['Kühlregal']);
    final gesture = await tester.startGesture(
      tester.getCenter(find.widgetWithText(ListTile, 'Milch')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();
    expect(headings(tester), ['Obst & Gemüse', 'Kühlregal', 'Sonstiges']);

    await gesture.moveTo(tester.getCenter(find.text('Obst & Gemüse')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.rows.values.single.categoryId, 'produce');
    expect(headings(tester), ['Obst & Gemüse']);
  });

  testWidgets('the store layout screen saves which categories dm carries', (
    tester,
  ) async {
    await pumpList(tester);
    await tester.tap(chip('dm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reihenfolge bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('dm: Reihenfolge'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Obst & Gemüse gibt es bei dm'));
    await tester.pumpAndSettle();
    final produce = repo.layout.singleWhere(
      (r) => r.storeId == 'dm' && r.categoryId == 'produce',
    );
    expect(produce.hidden, isFalse);
  });
}
