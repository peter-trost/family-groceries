import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/list_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'memory_cache.dart';

/// Hears whatever the test completes `finish` with.
class FakeDictation({final DictationProblem? problem}) implements Dictation {
  final finish = Completer<Dictated>();

  @override
  Future<DictationProblem?> prepare() async => problem;

  @override
  Future<Dictated> listen({
    required void Function(String words) onWords,
  }) async {
    final dictated = await finish.future;
    if (dictated case Heard(:final text)) {
      onWords(text);
    }
    return dictated;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  late FakeRepository repo;

  Future<void> pumpList(WidgetTester tester, Dictation? dictation) async {
    repo = FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BlocProvider(
          create: (_) => ListCubit(repo, MemoryListCache())..start(),
          child: ShoppingList(
            household: const Household(id: 'h', name: 'Trost'),
            dictation: dictation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder addField() => find.byType(TextField);
  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(addField()).controller!.text;

  testWidgets('no microphone without a recognizer (web)', (tester) async {
    await pumpList(tester, null);
    expect(find.byTooltip('Diktieren'), findsNothing);
  });

  testWidgets('a dictated sentence becomes separate items', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pump();
    expect(find.byTooltip('Diktat beenden'), findsOneWidget);
    expect(find.text('Ich höre zu …'), findsOneWidget);

    dictation.finish.complete(Heard('Milch, 2 Gurken und Klopapier'));
    await tester.pumpAndSettle();

    expect(repo.rows.values.map((i) => (i.name, i.quantity)), [
      ('Milch', null),
      ('Gurken', '2'),
      ('Klopapier', null),
    ]);
    expect(
      find.text('Hinzugefügt: Milch, 2 Gurken, Klopapier.'),
      findsOneWidget,
    );
    expect(fieldText(tester), isEmpty);
    expect(find.byTooltip('Diktieren'), findsOneWidget);
    expect(tester.widget<TextField>(addField()).focusNode!.hasFocus, isTrue);
  });

  testWidgets('items already on the list are named, not doubled', (
    tester,
  ) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.enterText(addField(), 'Milch');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(Heard('Milch und Brot'));
    await tester.pumpAndSettle();

    expect(repo.rows.values.map((i) => i.name), ['Milch', 'Brot']);
    expect(
      find.text('Hinzugefügt: Brot. Schon auf der Liste: Milch.'),
      findsOneWidget,
    );
  });

  testWidgets('offline, the sentence stays in the field', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    repo.online = false;
    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(Heard('Milch und Brot'));
    await tester.pumpAndSettle();

    expect(fieldText(tester), 'Milch und Brot');
    expect(find.textContaining('Keine Verbindung'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });

  testWidgets('silence adds nothing', (tester) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(NothingHeard());
    await tester.pumpAndSettle();

    expect(find.text('Ich habe nichts gehört.'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });

  testWidgets('a refused microphone explains where to allow it', (
    tester,
  ) async {
    await pumpList(
      tester,
      FakeDictation(problem: DictationProblem.unavailable),
    );
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mikrofon'), findsOneWidget);
    expect(find.byTooltip('Diktieren'), findsOneWidget);
  });

  testWidgets('without offline German the microphone says why and stays off', (
    tester,
  ) async {
    await pumpList(
      tester,
      FakeDictation(problem: DictationProblem.noOfflineGerman),
    );
    await tester.tap(find.byTooltip('Diktieren'));
    await tester.pumpAndSettle();

    expect(find.textContaining('deutsche Offline-Spracherkennung'), findsOne);
    expect(find.text('Ich höre zu …'), findsNothing);
    expect(find.byTooltip('Diktieren'), findsOneWidget);
  });

  testWidgets('a recognizer that finds no German model mid-way says why', (
    tester,
  ) async {
    final dictation = FakeDictation();
    await pumpList(tester, dictation);
    await tester.tap(find.byTooltip('Diktieren'));
    dictation.finish.complete(Refused(DictationProblem.noOfflineGerman));
    await tester.pumpAndSettle();

    expect(find.textContaining('deutsche Offline-Spracherkennung'), findsOne);
    expect(repo.rows, isEmpty);
  });
}
