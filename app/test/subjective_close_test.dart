// Angaben zum Lauf (FR-0038): Schließen der Seite („Fertig“, Zurück) wartet
// auf das Speichern geänderter Texte; scheitert es, bleibt die Seite offen,
// der Text im Feld und die Fehlerzeile sichtbar. Synthetische Daten.

import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show runAndFinish;
import 'run_detail_test.dart' show openDetail, seedDetailRun;

/// Speicher, dessen Schreiben der Angaben scheitern oder anhalten kann.
class _SaveStorage implements Storage {
  _SaveStorage(this.inner);
  final Storage inner;
  late _SaveSession session;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      session = _SaveSession(await inner.open(key));
}

class _SaveSession implements StorageSession {
  _SaveSession(this.s);
  final StorageSession s;

  /// Schreiben der Angaben scheitert.
  bool failSave = false;

  /// Hält das Schreiben der Angaben an, bis der Completer erfüllt ist.
  Completer<void>? hold;

  /// Anzahl der Schreibversuche der Angaben.
  int saves = 0;

  @override
  RunSubjectiveStore get subjective => _SaveSubjective(this, s.subjective);
  @override
  SettingsStore get settings => s.settings;
  @override
  ProfileStore get profile => s.profile;
  @override
  RunStore get runs => s.runs;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  RawDataStore get rawData => s.rawData;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _SaveSubjective implements RunSubjectiveStore {
  _SaveSubjective(this.o, this.inner);
  final _SaveSession o;
  final RunSubjectiveStore inner;
  @override
  Future<StoredRunSubjective?> read(int runId) => inner.read(runId);
  @override
  Future<Map<int, StoredRunSubjective>> readAll() => inner.readAll();
  @override
  Future<void> save(
    int runId,
    RunSubjective subjective, {
    SrpeLoad? srpe,
  }) async {
    o.saves++;
    final hold = o.hold;
    if (hold != null) await hold.future;
    if (o.failSave) throw const StorageException(StorageFailure.failed);
    await inner.save(runId, subjective, srpe: srpe);
  }

  @override
  Future<bool> setSrpe(
    int runId,
    SrpeLoad? srpe, {
    required int? expectedRpe,
  }) => inner.setSrpe(runId, srpe, expectedRpe: expectedRpe);
}

Future<(Device, _SaveStorage)> _started(WidgetTester tester) async {
  final d = Device();
  final storage = _SaveStorage(d.storage);
  d.storageOverride = storage;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  return (d, storage);
}

/// Lauf aufzeichnen und beenden: Abschlussseite mit „Angaben zum Lauf“.
Future<(Device, _SaveStorage)> _finished(WidgetTester tester) async {
  final (d, storage) = await _started(tester);
  await runAndFinish(d, tester, 60);
  expect(key('run_done_close'), findsOneWidget);
  return (d, storage);
}

Future<void> _typeNote(WidgetTester tester, String note) async {
  await tester.ensureVisible(key('subjective_note'));
  await tester.pumpAndSettle();
  await tester.enterText(key('subjective_note'), note);
  await tester.pump();
}

String _noteField(WidgetTester tester) =>
    tester.widget<TextField>(key('subjective_note')).controller!.text;

Future<String?> _storedNote(Device d) async {
  final id = (await d.session.runs.list()).single.id;
  return (await d.session.subjective.read(id))?.subjective.note;
}

/// System-Zurück (Android).
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

Future<void> _tapClose(WidgetTester tester) async {
  await tester.tap(key('run_done_close'));
  await tester.pump();
}

bool _onSummary() => key('run_done_close').evaluate().isNotEmpty;

void main() {
  group('Abschlussseite: Schließen wartet auf die Angaben (FR-0038)', () {
    testWidgets('Notiz tippen, sofort "Fertig": erst gespeichert, dann zu', (
      tester,
    ) async {
      final (d, storage) = await _finished(tester);
      final hold = storage.session.hold = Completer<void>();
      await _typeNote(tester, 'Beine frisch');
      await _tapClose(tester);
      await tester.pump(const Duration(milliseconds: 100));
      // Das Speichern hängt: Die Seite bleibt offen, der Knopf zeigt es an.
      expect(_onSummary(), isTrue);
      expect(key('run_done_saving'), findsOneWidget);
      expect(await _storedNote(d), isNull);
      hold.complete();
      await tester.pumpAndSettle();
      expect(_onSummary(), isFalse);
      expect(key('home_start_run'), findsOneWidget);
      expect(await _storedNote(d), 'Beine frisch');
    });

    testWidgets('Speichern scheitert: Seite bleibt, Text und Fehlerzeile; '
        'zweites "Fertig" schließt', (tester) async {
      final (d, storage) = await _finished(tester);
      storage.session.failSave = true;
      await _typeNote(tester, 'Ferse zieht');
      await _tapClose(tester);
      await tester.pumpAndSettle();
      expect(_onSummary(), isTrue);
      expect(_noteField(tester), 'Ferse zieht');
      expect(key('subjective_save_failed'), findsOneWidget);
      expect(key('run_done_saving'), findsNothing);
      final attempts = storage.session.saves;
      // Der Nutzer hat den Fehler gesehen: zu ohne erneutes Warten.
      await _tapClose(tester);
      await tester.pumpAndSettle();
      expect(_onSummary(), isFalse);
      expect(key('home_start_run'), findsOneWidget);
      expect(storage.session.saves, attempts);
      expect(await _storedNote(d), isNull);
    });

    testWidgets('Zurück-Taste: wartet auf das Speichern', (tester) async {
      final (d, storage) = await _finished(tester);
      final hold = storage.session.hold = Completer<void>();
      await _typeNote(tester, 'Wade fest');
      await _systemBack(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_onSummary(), isTrue);
      expect(key('run_done_saving'), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(_onSummary(), isFalse);
      expect(await _storedNote(d), 'Wade fest');
    });

    testWidgets('Zurück-Taste, Speichern scheitert: Seite bleibt; '
        'zweites Zurück schließt', (tester) async {
      final (_, storage) = await _finished(tester);
      storage.session.failSave = true;
      await _typeNote(tester, 'Knie');
      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(_onSummary(), isTrue);
      expect(_noteField(tester), 'Knie');
      expect(key('subjective_save_failed'), findsOneWidget);
      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(_onSummary(), isFalse);
      expect(key('home_start_run'), findsOneWidget);
    });

    testWidgets('ohne Änderung schließt "Fertig" sofort', (tester) async {
      final (_, storage) = await _finished(tester);
      // Ein hängendes Speichern würde die Seite offen halten.
      storage.session.hold = Completer<void>();
      await _tapClose(tester);
      await tester.pumpAndSettle();
      expect(_onSummary(), isFalse);
      expect(storage.session.saves, 0);
    });

    testWidgets('ohne Änderung schließt Zurück sofort', (tester) async {
      final (_, storage) = await _finished(tester);
      storage.session.hold = Completer<void>();
      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(_onSummary(), isFalse);
      expect(storage.session.saves, 0);
    });
  });

  group('Detailansicht: Zurück wartet auf die Angaben (FR-0038)', () {
    Future<(Device, _SaveStorage)> openSeeded(WidgetTester tester) async {
      final (d, storage) = await _started(tester);
      await openDetail(
        tester,
        d,
        () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
      );
      expect(key('subjective_note'), findsOneWidget);
      return (d, storage);
    }

    bool onDetail() => key('detail_delete').evaluate().isNotEmpty;

    testWidgets('Notiz tippen, sofort Zurück: erst gespeichert, dann zu', (
      tester,
    ) async {
      final (d, storage) = await openSeeded(tester);
      final hold = storage.session.hold = Completer<void>();
      await _typeNote(tester, 'gut erholt');
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 100));
      expect(onDetail(), isTrue);
      hold.complete();
      await tester.pumpAndSettle();
      expect(onDetail(), isFalse);
      expect(await _storedNote(d), 'gut erholt');
    });

    testWidgets('Speichern scheitert: Seite bleibt, Text und Fehlerzeile; '
        'zweites Zurück schließt', (tester) async {
      final (_, storage) = await openSeeded(tester);
      storage.session.failSave = true;
      await _typeNote(tester, 'Hüfte');
      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(onDetail(), isTrue);
      expect(_noteField(tester), 'Hüfte');
      expect(key('subjective_save_failed'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(onDetail(), isFalse);
    });

    testWidgets('ohne Änderung schließt Zurück sofort', (tester) async {
      final (_, storage) = await openSeeded(tester);
      storage.session.hold = Completer<void>();
      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(onDetail(), isFalse);
      expect(storage.session.saves, 0);
    });
  });
}
