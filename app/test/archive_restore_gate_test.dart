import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/archive/archive_wiring.dart';
import 'package:running_app/features/storage/storage_start.dart';

import 'storage_world.dart';

const String _pw = 'synthetisches Testpasswort';
const String _path = '/cache/imports/archive.bin';

/// Ersatz für Prüfung und Wiederherstellung. Merkt, wie viele Löschaufrufe
/// der Dateien zum Zeitpunkt jedes Aufrufs schon liefen.
class _Fakes {
  _Fakes(this.w);

  final World w;
  final List<String> events = [];
  final List<({String path, String password})> verifies = [];
  final List<({String path, String password, bool reset})> restores = [];
  final List<Object> verifyErrors = [];
  final List<Object> restoreErrors = [];
  Completer<void>? verifyGate;
  StorageSession? freshSeen;
  late StorageSession restored;

  Future<void> verify({
    required String path,
    required String password,
    ArchiveCancel? cancel,
  }) async {
    events.add('verify(delete=${w.files.deleteCalls})');
    verifies.add((path: path, password: password));
    await verifyGate?.future;
    if (cancel?.isCancelled ?? false) {
      throw const ArchiveImportException(ArchiveImportFailure.cancelled);
    }
    if (verifyErrors.isNotEmpty) throw verifyErrors.removeAt(0);
  }

  Future<ArchiveRestoreRunner> restore(
    StorageSession fresh,
    SerializeAction serialize,
  ) async {
    freshSeen = fresh;
    return ({
      required path,
      required password,
      bool resetConfirmed = false,
      ArchiveCancel? cancel,
    }) async {
      events.add('restore(delete=${w.files.deleteCalls})');
      restores.add((path: path, password: password, reset: resetConfirmed));
      if (restoreErrors.isNotEmpty) throw restoreErrors.removeAt(0);
      return restored;
    };
  }
}

Future<(World, _Fakes, FakeFileHandoff, StorageStartController)> _pump(
  WidgetTester tester, {
  bool wired = true,
  FilePickResult pick = const FilePickResult.completed(_path),
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [const Locale('de')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final w = World();
  await w.seed(fileKey: keyOf(1), storedKey: keyOf(2));
  final fakes = _Fakes(w);
  fakes.restored = await FakeStorage().open(keyOf(3));
  await fakes.restored.settings.set(
    SettingKeys.setupDone,
    '1',
    at: DateTime.utc(2030),
  );
  final handoff = FakeFileHandoff()..nextPick = pick;
  final c = w.controller();
  await tester.pumpWidget(
    RunningApp(
      dependencies: AppDependencies(
        storageStart: c,
        fileHandoff: handoff,
        archiveRestore: wired ? fakes.restore : null,
        archiveVerify: wired ? fakes.verify : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (w, fakes, handoff, c);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _password(WidgetTester tester, [String pw = _pw]) async {
  await tester.enterText(find.byKey(const Key('archive_import_password')), pw);
  await _tap(tester, 'archive_import_password_ok');
}

/// Der Neubeginn läuft (Fortschrittsanzeige animiert ohne Ende): nur einige
/// Bilder statt pumpAndSettle.
Future<void> _tapBusy(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Alles unverändert: Datei da, nichts gelöscht, Schlüssel unberührt.
void _untouched(World w) {
  expect(w.files.deleteCalls, 0);
  expect(w.files.present, isTrue);
  expect(w.log, isEmpty);
  expect(sameBytes(w.keys.store[storageKeyName], keyOf(2)), isTrue);
}

void main() {
  testWidgets('ohne Verdrahtung kein Weg über das Archiv', (tester) async {
    await _pump(tester, wired: false);
    expect(find.text('Neu beginnen'), findsOneWidget);
    expect(find.byKey(const Key('not_openable_restore')), findsNothing);
  });

  testWidgets('Weg sichtbar mit Erklärung: die alte Datei bleibt', (
    tester,
  ) async {
    final (w, _, _, _) = await _pump(tester);
    expect(find.text('Aus Archiv wiederherstellen'), findsOneWidget);
    expect(
      find.textContaining('bleibt bestehen, bis du ihr Löschen bestätigst'),
      findsOneWidget,
    );
    _untouched(w);
  });

  testWidgets('Rundgang: erst prüfen, dann Bestätigung, dann Löschen und '
      'Einspielen vor "bereit"', (tester) async {
    final (w, f, h, c) = await _pump(tester);
    await _tap(tester, 'not_openable_restore');
    expect(h.pickCount, 1);
    final field = tester.widget<TextField>(
      find.byKey(const Key('archive_import_password')),
    );
    expect(field.obscureText, isTrue);
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.autofillHints, anyOf(isNull, isEmpty));
    await _password(tester);

    // Geprüft, aber noch nichts gelöscht: die Bestätigung steht an.
    expect(f.verifies.single.path, _path);
    expect(f.verifies.single.password, _pw);
    expect(find.byKey(const Key('restore_confirm_dialog')), findsOneWidget);
    expect(find.text('Archiv einspielen?'), findsOneWidget);
    expect(find.textContaining('endgültig gelöscht'), findsOneWidget);
    expect(
      find.textContaining('Ein älteres Archiv kann Daten'),
      findsOneWidget,
    );
    _untouched(w);
    expect(f.restores, isEmpty);

    await _tap(tester, 'restore_confirm_action');
    expect(f.events, ['verify(delete=0)', 'restore(delete=1)']);
    expect(f.restores.single.path, _path);
    expect(f.restores.single.password, _pw);
    expect(f.restores.single.reset, isFalse, reason: 'App ist leer');
    expect(f.freshSeen, isNotNull);
    expect((c.state as StorageReady).session, same(f.restored));
    expect(h.discardCount, 1);
    expect(find.textContaining('Archiv importiert'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(w.violations, isEmpty);
  });

  testWidgets('Dateiwahl abgebrochen: nichts geschieht, Kopie entsorgt', (
    tester,
  ) async {
    final (w, f, h, _) = await _pump(
      tester,
      pick: const FilePickResult.cancelled(),
    );
    await _tap(tester, 'not_openable_restore');
    expect(find.byKey(const Key('archive_import_password')), findsNothing);
    expect(f.events, isEmpty);
    expect(h.discardCount, 1);
    _untouched(w);
  });

  testWidgets('Dateiwahl fehlgeschlagen: Meldung, nichts geschieht', (
    tester,
  ) async {
    final (w, f, h, _) = await _pump(
      tester,
      pick: const FilePickResult.failed(),
    );
    await _tap(tester, 'not_openable_restore');
    expect(
      find.text('Die Datei konnte nicht geöffnet werden.'),
      findsOneWidget,
    );
    expect(f.events, isEmpty);
    expect(h.discardCount, 1);
    _untouched(w);
  });

  testWidgets('Abbruch am Passwortdialog: nichts geprüft, nichts gelöscht', (
    tester,
  ) async {
    final (w, f, h, _) = await _pump(tester);
    await _tap(tester, 'not_openable_restore');
    await _tap(tester, 'archive_import_password_cancel');
    expect(f.events, isEmpty);
    expect(h.discardCount, 1);
    _untouched(w);
    expect(find.text('Daten lassen sich nicht öffnen'), findsOneWidget);
  });

  testWidgets('falsches Passwort kostet nichts: Fehler im Dialog, Abbruch '
      'dort lässt die Datei stehen', (tester) async {
    final (w, f, h, _) = await _pump(tester);
    f.verifyErrors.add(
      const ArchiveImportException(ArchiveImportFailure.wrongPasswordOrDamaged),
    );
    await _tap(tester, 'not_openable_restore');
    await _password(tester, 'falsch falsch falsch');
    expect(
      find.textContaining('Falsches Passwort oder beschädigter Anfang'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('restore_confirm_dialog')), findsNothing);
    expect(
      h.discardCount,
      0,
      reason:
          'Datei wird für den nächsten Versuch '
          'gebraucht',
    );
    await _tap(tester, 'archive_import_password_cancel');
    expect(f.restores, isEmpty);
    expect(h.discardCount, 1);
    _untouched(w);
  });

  testWidgets('falsches Passwort, zweiter Versuch richtig: weiter bis zur '
      'Bestätigung, noch nichts gelöscht', (tester) async {
    final (w, f, _, _) = await _pump(tester);
    f.verifyErrors.add(
      const ArchiveImportException(ArchiveImportFailure.wrongPasswordOrDamaged),
    );
    await _tap(tester, 'not_openable_restore');
    await _password(tester, 'falsch falsch falsch');
    await _password(tester);
    expect(f.verifies.map((v) => v.password), ['falsch falsch falsch', _pw]);
    expect(find.byKey(const Key('restore_confirm_dialog')), findsOneWidget);
    _untouched(w);
  });

  for (final (name, error, text) in <(String, ArchiveImportFailure, String)>[
    ('beschädigt', ArchiveImportFailure.damaged, 'Das Archiv ist beschädigt.'),
    (
      'keine Archivdatei',
      ArchiveImportFailure.notAnArchive,
      'Das ist keine Archivdatei.',
    ),
    (
      'neuere Version',
      ArchiveImportFailure.newerSchema,
      'aktualisiere die App.',
    ),
    (
      'Lesen der Datei',
      ArchiveImportFailure.readFailed,
      'Die Datei konnte nicht gelesen werden.',
    ),
  ]) {
    testWidgets('Prüfung: $name: Meldung, alte Datei bleibt', (tester) async {
      final (w, f, h, _) = await _pump(tester);
      f.verifyErrors.add(ArchiveImportException(error));
      await _tap(tester, 'not_openable_restore');
      await _password(tester);
      expect(find.textContaining(text), findsOneWidget);
      expect(find.byKey(const Key('restore_confirm_dialog')), findsNothing);
      await _tap(tester, 'archive_import_error_close');
      expect(f.restores, isEmpty);
      expect(h.discardCount, 1);
      _untouched(w);
      expect(find.text('Daten lassen sich nicht öffnen'), findsOneWidget);
    });
  }

  testWidgets('Abbruch während der Prüfung: nichts gelöscht', (tester) async {
    final (w, f, h, _) = await _pump(tester);
    f.verifyGate = Completer<void>();
    await _tap(tester, 'not_openable_restore');
    await tester.enterText(
      find.byKey(const Key('archive_import_password')),
      _pw,
    );
    await tester.tap(find.byKey(const Key('archive_import_password_ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('archive_import_working')), findsOneWidget);
    await tester.tap(find.byKey(const Key('archive_import_abort')));
    await tester.pump();
    f.verifyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Import abgebrochen.'), findsOneWidget);
    expect(h.discardCount, 1);
    _untouched(w);
  });

  testWidgets('Abbruch an der Bestätigung (Abbrechen, daneben, Zurück): alte '
      'Datei bleibt', (tester) async {
    final (w, f, h, _) = await _pump(tester);
    await _tap(tester, 'not_openable_restore');
    await _password(tester);
    await _tap(tester, 'restore_confirm_cancel');
    _untouched(w);
    expect(h.discardCount, 1);

    await _tap(tester, 'not_openable_restore');
    await _password(tester);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restore_confirm_dialog')), findsNothing);
    _untouched(w);

    await _tap(tester, 'not_openable_restore');
    await _password(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _untouched(w);
    expect(f.restores, isEmpty);
    expect(h.discardCount, 3);
    expect(find.text('Daten lassen sich nicht öffnen'), findsOneWidget);
  });

  testWidgets('Einspielen scheitert nach dem Neubeginn: Meldung, leere App '
      'bereit, Kopie entsorgt', (tester) async {
    final (w, f, h, c) = await _pump(tester);
    f.restoreErrors.add(
      const ArchiveImportException(ArchiveImportFailure.targetFailed),
    );
    await _tap(tester, 'not_openable_restore');
    await _password(tester);
    await _tapBusy(tester, 'restore_confirm_action');
    expect(
      find.textContaining('zum Beispiel weil der Speicher voll ist'),
      findsOneWidget,
    );
    await _tap(tester, 'archive_import_error_close');
    expect(w.files.deleteCalls, 1);
    expect(c.state, isA<StorageReady>());
    expect((c.state as StorageReady).session, same(f.freshSeen));
    expect(h.discardCount, 1);
    expect(w.violations, isEmpty);
  });

  testWidgets('Tausch scheitert (swapFailed mit Sitzung): die App läuft mit '
      'der Sitzung der Ausnahme, nicht mit der geschlossenen', (tester) async {
    final (w, f, h, c) = await _pump(tester);
    final other = await FakeStorage().open(keyOf(4));
    f.restoreErrors.add(
      ArchiveRestoreException(ArchiveRestoreFailure.swapFailed, session: other),
    );
    await _tap(tester, 'not_openable_restore');
    await _password(tester);
    await _tapBusy(tester, 'restore_confirm_action');
    await _tap(tester, 'archive_import_error_close');
    expect(c.state, isA<StorageReady>());
    expect((c.state as StorageReady).session, same(other));
    expect((c.state as StorageReady).session, isNot(same(f.freshSeen)));
    expect(h.discardCount, 1);
    expect(w.violations, isEmpty);
  });

  testWidgets('Öffnen nach dem Tausch scheitert: "nicht zu öffnen", Erneut '
      'versuchen öffnet normal', (tester) async {
    final (w, f, h, c) = await _pump(tester);
    f.restoreErrors.add(
      const ArchiveRestoreException(ArchiveRestoreFailure.reopenFailed),
    );
    await _tap(tester, 'not_openable_restore');
    await _password(tester);
    await _tapBusy(tester, 'restore_confirm_action');
    await _tap(tester, 'archive_import_error_close');
    expect(c.state, isA<StorageNotOpenableState>());
    expect(
      (c.state as StorageNotOpenableState).cause,
      StorageNotOpenableCause.openFailed,
    );
    expect(h.discardCount, 1);
    expect(find.text('Neubeginn fortsetzen'), findsNothing);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(c.state, isA<StorageReady>());
    expect(w.files.deleteCalls, 1, reason: 'kein zweiter Neubeginn');
    expect(w.violations, isEmpty);
  });

  testWidgets('Neubeginn scheitert (Datei nicht löschbar): kein Einspielen', (
    tester,
  ) async {
    final (w, f, h, c) = await _pump(tester);
    w.files.failDelete = true;
    await _tap(tester, 'not_openable_restore');
    await _password(tester);
    await _tap(tester, 'restore_confirm_action');
    expect(f.restores, isEmpty);
    expect(c.state, isA<StorageNotOpenableState>());
    expect(h.discardCount, 1);
    expect(sameBytes(w.keys.store[storageKeyName], keyOf(2)), isTrue);
  });

  testWidgets('Weg nicht angeboten, solange der Neubeginn nicht erlaubt ist', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final w = World();
    await w.seed(fileKey: keyOf(1), storedKey: keyOf(1));
    w.inner.openFailure = StorageFailure.openFailed;
    final f = _Fakes(w);
    await tester.pumpWidget(
      RunningApp(
        dependencies: AppDependencies(
          storageStart: w.controller(),
          fileHandoff: FakeFileHandoff(),
          archiveRestore: f.restore,
          archiveVerify: f.verify,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Daten lassen sich nicht öffnen'), findsOneWidget);
    expect(find.text('Neu beginnen'), findsNothing);
    expect(find.byKey(const Key('not_openable_restore')), findsNothing);
  });
}
