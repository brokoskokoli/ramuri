import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/storage/storage_start.dart';

import 'storage_world.dart';

Future<void> pumpApp(
  WidgetTester tester,
  StorageStartController c, {
  Locale locale = const Locale('de'),
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    RunningApp(dependencies: AppDependencies(storageStart: c)),
  );
  await tester.pumpAndSettle();
}

void main() {
  final k0 = keyOf(1);
  final k1 = keyOf(2);

  testWidgets('bereit: Startseite mit Zugang zu "Daten"', (tester) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k0);
    await pumpApp(tester, w.controller());
    expect(find.text('Willkommen bei der Lauf-App'), findsOneWidget);
    expect(find.text('Daten'), findsOneWidget);
  });

  testWidgets('laden: kein Inhalt, nur Fortschritt', (tester) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k0);
    tester.platformDispatcher.localesTestValue = [const Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    // Zustand "laden" bleibt, solange der Start nicht fertig ist.
    final blocked = StorageStartController(
      keyStore: w.keys,
      generateKey: () => k0,
      wire: () => Future<StorageWiring>.delayed(
        const Duration(seconds: 5),
        () => StorageWiring(storage: w.storage, files: w.files),
      ),
    );
    await tester.pumpWidget(
      RunningApp(dependencies: AppDependencies(storageStart: blocked)),
    );
    await tester.pump();
    expect(find.text('Daten werden geöffnet …'), findsOneWidget);
    expect(find.text('Willkommen bei der Lauf-App'), findsNothing);
    expect(find.text('Daten'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Willkommen bei der Lauf-App'), findsOneWidget);
  });

  for (final (name, setup, text)
      in <(String, Future<void> Function(World), String)>[
        (
          'Schlüssel fehlt',
          (w) => w.seed(fileKey: k0),
          'Schlüssel, der die gespeicherten',
        ),
        (
          'Schlüssel unbrauchbar',
          (w) async {
            await w.seed(fileKey: k0);
            w.keys.put(storageKeyName, Uint8List(3));
          },
          'abgelegte Schlüssel ist beschädigt',
        ),
        (
          'falscher Schlüssel',
          (w) => w.seed(fileKey: k0, storedKey: k1),
          'mit dem vorhandenen Schlüssel nicht lesen',
        ),
        (
          'Schlüsselablage-Fehler',
          (w) async {
            await w.seed(fileKey: k0, storedKey: k0);
            w.keys.failWith = 'defekt';
          },
          'Schlüsselablage des Geräts antwortet nicht',
        ),
      ]) {
    testWidgets('nicht zu öffnen: $name', (tester) async {
      final w = World();
      await setup(w);
      await pumpApp(tester, w.controller());
      expect(find.text('Daten lassen sich nicht öffnen'), findsOneWidget);
      expect(find.textContaining(text), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.text('Neu beginnen'), findsOneWidget);
      expect(find.text('Willkommen bei der Lauf-App'), findsNothing);
      expect(w.files.deleteCalls, 0);
      expect(w.log, isEmpty);
    });
  }

  testWidgets('nicht zu öffnen: Abbrechen und Zurück lassen alles stehen', (
    tester,
  ) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k1);
    await pumpApp(tester, w.controller());
    await tester.tap(find.text('Neu beginnen'));
    await tester.pumpAndSettle();
    expect(find.text('Neu beginnen?'), findsOneWidget);
    expect(find.textContaining('endgültig gelöscht'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Neu beginnen?'), findsNothing);
    expect(w.files.deleteCalls, 0);
    expect(w.files.present, isTrue);

    // Tippen daneben (Dialog schließen ohne Antwort).
    await tester.tap(find.text('Neu beginnen'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text('Neu beginnen?'), findsNothing);
    expect(w.files.deleteCalls, 0);

    // Zurück-Geste.
    await tester.tap(find.text('Neu beginnen'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(w.files.deleteCalls, 0);
    expect(w.log, isEmpty);
    expect(find.text('Daten lassen sich nicht öffnen'), findsOneWidget);
  });

  testWidgets('nicht zu öffnen: erst nach Bestätigung weg, dann leer bereit', (
    tester,
  ) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k1);
    await pumpApp(tester, w.controller());
    await tester.tap(find.text('Neu beginnen'));
    await tester.pumpAndSettle();
    expect(w.files.deleteCalls, 0, reason: 'Dialog allein löscht nichts');
    await tester.tap(find.text('Endgültig löschen und neu beginnen'));
    await tester.pumpAndSettle();
    expect(w.files.deleteCalls, 1);
    expect(find.text('Willkommen bei der Lauf-App'), findsOneWidget);
    expect(w.violations, isEmpty);
  });

  testWidgets('Neubeginn schlägt fehl: Fehler sichtbar, kein neuer Schlüssel', (
    tester,
  ) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k1);
    w.files.failDelete = true;
    await pumpApp(tester, w.controller());
    await tester.tap(find.text('Neu beginnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Endgültig löschen und neu beginnen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nicht vollständig gelöscht'), findsOneWidget);
    expect(find.text('Daten lassen sich nicht öffnen'), findsOneWidget);
    expect(sameBytes(w.keys.store[storageKeyName], k1), isTrue);
  });

  testWidgets('Verschlüsselung nicht aktiv: eigene Meldung, kein Neubeginn', (
    tester,
  ) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k0);
    w.inner.encryptionActive = false;
    await pumpApp(tester, w.controller());
    expect(find.text('Verschlüsselung nicht aktiv'), findsOneWidget);
    expect(find.text('Neu beginnen'), findsNothing);
    expect(find.textContaining('Neu beginnen'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Willkommen bei der Lauf-App'), findsNothing);
    expect(find.text('Daten'), findsNothing);
    expect(w.files.deleteCalls, 0);
    expect(w.log, isEmpty);
    expect(w.files.present, isTrue);
  });

  testWidgets('englisch: nicht zu öffnen und Bestätigung', (tester) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k1);
    await pumpApp(tester, w.controller(), locale: const Locale('en'));
    expect(find.text('Data cannot be opened'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();
    expect(find.text('Start over?'), findsOneWidget);
  });

  testWidgets('englisch: Verschlüsselung nicht aktiv', (tester) async {
    final w2 = World();
    await w2.seed(fileKey: k0, storedKey: k0);
    w2.inner.encryptionActive = false;
    await pumpApp(tester, w2.controller(), locale: const Locale('en'));
    expect(find.text('Encryption not active'), findsOneWidget);
  });

  testWidgets('Daten: Alles löschen nur nach Bestätigung', (tester) async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k0);
    final c = w.controller();
    await pumpApp(tester, c);
    final session = (c.state as StorageReady).session;
    await tester.tap(find.text('Daten'));
    await tester.pumpAndSettle();
    expect(find.text('Alles löschen'), findsOneWidget);
    await tester.tap(find.text('Alles löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await session.runs.list(), hasLength(1));
    await tester.tap(find.text('Alles löschen'));
    await tester.pumpAndSettle();
    // Zweite Schaltfläche "Alles löschen" im Dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Alles löschen'));
    await tester.pumpAndSettle();
    expect(await session.runs.list(), isEmpty);
  });
}
