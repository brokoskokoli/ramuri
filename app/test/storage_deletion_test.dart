import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/storage/deletion.dart';
import 'package:running_app/l10n/app_localizations.dart';

final key = Uint8List.fromList(List.generate(32, (i) => i));

/// Seite mit zwei Knöpfen; das Ergebnis des Dienstes landet in [results].
class _Host extends StatelessWidget {
  const _Host(this.session, this.runId, this.results);
  final StorageSession session;
  final int runId;
  final List<DeletionResult> results;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => Column(
        children: [
          TextButton(
            onPressed: () async => results.add(
              await confirmAndDeleteRun(
                context,
                session,
                FakeClock(DateTime.utc(2030, 6)),
                runId,
              ),
            ),
            child: const Text('run'),
          ),
          TextButton(
            onPressed: () async =>
                results.add(await confirmAndDeleteAll(context, session)),
            child: const Text('all'),
          ),
        ],
      ),
    ),
  );
}

Future<(StorageSession, int, int, List<DeletionResult>)> pump(
  WidgetTester tester,
  FakeStorage storage, {
  Locale locale = const Locale('de'),
}) async {
  final s = await storage.open(key);
  final a = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
  final b = (await s.runs.create(startedAt: DateTime.utc(2030, 2))).id;
  await s.settings.set('k', 'v', at: DateTime.utc(2030));
  final results = <DeletionResult>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Host(s, a, results),
    ),
  );
  return (s, a, b, results);
}

Future<int> runCount(WidgetTester tester, StorageSession s) async =>
    (await tester.runAsync(() => s.runs.list()))!.length;

void main() {
  testWidgets('Lauf: Abbrechen löscht nichts', (tester) async {
    final (s, a, _, results) = await pump(tester, FakeStorage());
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    expect(find.text('Lauf löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(results, [DeletionResult.cancelled]);
    expect(await runCount(tester, s), 2);
    expect(await s.runs.get(a), isNotNull);
  });

  testWidgets('Lauf: Zurück und Tippen neben den Dialog löschen nichts', (
    tester,
  ) async {
    final (s, _, _, results) = await pump(tester, FakeStorage());
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text('Lauf löschen?'), findsNothing);

    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Lauf löschen?'), findsNothing);

    expect(results, [DeletionResult.cancelled, DeletionResult.cancelled]);
    expect(await runCount(tester, s), 2);
  });

  testWidgets('Lauf: Bestätigen löscht genau diesen Lauf', (tester) async {
    final (s, a, b, results) = await pump(tester, FakeStorage());
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen'));
    await tester.pumpAndSettle();
    expect(results, [DeletionResult.deleted]);
    expect(await s.runs.get(a), isNull);
    expect(await s.runs.get(b), isNotNull);
    expect(find.text('Gelöscht.'), findsOneWidget);
  });

  testWidgets('Alles: Abbrechen löscht nichts, Bestätigen löscht alles', (
    tester,
  ) async {
    final (s, _, _, results) = await pump(tester, FakeStorage());
    await tester.tap(find.text('all'));
    await tester.pumpAndSettle();
    expect(find.text('Alle Daten löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await runCount(tester, s), 2);
    expect(await s.settings.get('k'), 'v');

    await tester.tap(find.text('all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alles löschen'));
    await tester.pumpAndSettle();
    expect(results, [DeletionResult.cancelled, DeletionResult.deleted]);
    expect(await runCount(tester, s), 0);
    expect(await s.settings.get('k'), isNull);
  });

  testWidgets(
    'Hinweis nach OQ-0025 in beiden Sprachen, Strava nur als Beispiel',
    (tester) async {
      for (final (locale, hint) in [
        (const Locale('de'), 'etwa bei Strava'),
        (const Locale('en'), 'for example with Strava'),
      ]) {
        await pump(tester, FakeStorage(), locale: locale);
        for (final label in ['run', 'all']) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.textContaining(hint), findsOneWidget, reason: '$locale');
          // "Strava" ist nur das Beispiel, nicht der einzige Fall.
          final text = tester.widget<Text>(find.textContaining(hint)).data!;
          expect(text, isNot(equals('Strava')));
          expect(
            text.contains('bereits weitergegeben') ||
                text.contains('already been shared'),
            isTrue,
          );
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            ),
          );
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets('Englisch: Texte vorhanden', (tester) async {
    await pump(tester, FakeStorage(), locale: const Locale('en'));
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    expect(find.text('Delete run?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('Checkpoint nicht durchgelaufen: gelöscht, aber kein Erfolg', (
    tester,
  ) async {
    final storage = FakeStorage()..checkpointIncomplete = true;
    final (s, a, _, results) = await pump(tester, storage);
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen'));
    await tester.pumpAndSettle();
    expect(results, [DeletionResult.deletedNotErased]);
    expect(await s.runs.get(a), isNull);
    expect(find.textContaining('noch nicht abgeschlossen'), findsOneWidget);
    expect(find.text('Gelöscht.'), findsNothing);
  });

  testWidgets('Unbekannter Lauf: Fehler gemeldet, nichts gelöscht', (
    tester,
  ) async {
    final (s, a, b, results) = await pump(tester, FakeStorage());
    await s.deleteRun(a);
    await tester.tap(find.text('run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen'));
    await tester.pumpAndSettle();
    expect(results, [DeletionResult.failed]);
    expect(await s.runs.get(b), isNotNull);
    expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
  });
}
