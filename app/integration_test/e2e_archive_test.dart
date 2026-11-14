// E2E: Archiv exportieren, Daten loeschen, Archiv wieder einlesen (FR-0192,
// FR-0198). Der Weg ueber die Oberflaeche endet im System-Dateidialog
// (Speichern/Teilen/Datei waehlen); den bedient dieser Test NICHT. Er nutzt
// die App-Schicht direkt darunter, so wie die App sie verdrahtet
// (AppDependencies.archiveExport schreibt die echte, verschluesselte Archivdatei
// in den Exportordner, AppDependencies.archiveRestore liest sie in die echte
// verschluesselte Datenbank ein und tauscht sie). Geprueft wird der
// gespeicherte Zustand vor Export und nach Reimport. Synthetische Daten,
// Ausgabe nur Zaehler. Laeuft in der Sammlung (all_test.dart).
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_support.dart';

const _password = 'synthetisches Testpasswort 1';

/// Inhalt, soweit das Archiv ihn traegt: Profil, Laeufe samt Rohdatenzaehlern,
/// nachgetragene Trainings. Ein Text, damit der Vergleich eine Zeile ist
/// (die Werte stehen nie in der Ausgabe).
Future<String> _snapshot(WidgetTester t, StorageSession s) async {
  return (await t.runAsync(() async {
    final b = StringBuffer();
    final p = await s.profile.read();
    b.writeln(
      'profile ${p.birthYear} ${p.bodyWeightKg} ${p.bodyHeightMeters} '
      '${p.restingHeartRateBpm} ${p.maxHeartRateBpm} ${p.weeklyRunMinutes} '
      '${p.trainingDaysMask} ${p.usualTrainingMinutes}',
    );
    final runs = [...await s.runs.list()]..sort((a, c) => a.id.compareTo(c.id));
    for (final r in runs) {
      final raw = await s.rawData.read(r.id);
      b.writeln(
        'run ${r.state} ${r.mode} ${r.startedAt.toIso8601String()} '
        'pos=${raw.positions.length} hr=${raw.heartRates.length} '
        'rr=${raw.rrPackets.length} belt=${raw.beltSettings.length}',
      );
    }
    for (final m in await s.manualTrainings.list()) {
      b.writeln(
        'manual ${m.training.isoDay} ${m.training.kind} ${m.training.duration} '
        '${m.training.rpe}',
      );
    }
    return b.toString();
  }))!;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Archiv exportieren, Daten loeschen, wieder einlesen', (t) async {
    final w = buildWorld();
    await startApp(t, w);
    await setupIfShown(t);
    var s = await session(t, w);

    // Eigene, erkennbare Daten zusaetzlich zu dem, was frueher Tests anlegten.
    await t.runAsync(() async {
      await s.profile.save(
        const ProfileRecord(
          birthYear: 1985,
          bodyWeightKg: 71.5,
          maxHeartRateBpm: 188,
          restingHeartRateBpm: 57,
          trainingDaysMask: 21,
        ),
      );
      await s.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2025, 1, 2),
          kind: ManualTrainingKind.run,
          duration: const Duration(minutes: 37),
          rpe: 6,
        ),
      );
    });
    final before = await _snapshot(t, s);
    final runsBefore = (await t.runAsync(() => s.runs.list()))!.length;
    log('ARCHIVE runs=$runsBefore');
    expect(before, contains('manual 2025-01-02'));

    // Export: echte Archivdatei im Exportordner.
    final export = w.deps.archiveExport!(s);
    final file = (await t.runAsync(() => export(password: _password)))!;
    final path = file.path;
    expect(path, isNotNull, reason: 'Archivdatei hat einen Pfad');
    final size = (await t.runAsync(() => File(path!).length()))!;
    expect(size, greaterThan(0), reason: 'Archivdatei nicht leer');

    // Alles loeschen; der Speicher ist danach leer.
    await t.runAsync(() => s.deleteAll());
    final emptied = await _snapshot(t, s);
    expect(emptied, isNot(before));
    expect(emptied, isNot(contains('manual')));
    expect(emptied, isNot(contains('run ')));
    expect(
      (await t.runAsync(() => ArchiveRestoreService.isEmpty(s)))!,
      isTrue,
      reason: 'nach dem Loeschen ist die App leer',
    );

    // Reimport ueber den App-Dienst (ohne Dateidialog).
    final restore = (await t.runAsync(
      () => w.deps.archiveRestore!(s, <T>(a) => a()),
    ))!;
    s = (await t.runAsync(() => restore(path: path!, password: _password)))!;
    w.deps.storageStart.adoptSession(s);
    await pumpFor(t, const Duration(seconds: 1));

    final after = await _snapshot(t, s);
    expect(
      after == before,
      isTrue,
      reason: 'Inhalt nach Reimport wie vor dem Export (Werte nie ausgeben)',
    );
    expect(
      (await t.runAsync(() => s.runs.list()))!.length,
      runsBefore,
      reason: 'Laufzahl wie vor dem Export',
    );

    // Falsches Passwort: das Archiv bleibt unlesbar, nichts aendert sich.
    // (runAsync reicht Fehler nicht weiter, darum faengt der Test sie selbst.)
    final again = (await t.runAsync(
      () => w.deps.archiveRestore!(s, <T>(a) => a()),
    ))!;
    final failure = await t.runAsync<ArchiveImportFailure?>(() async {
      try {
        await again(
          path: path!,
          password: 'falsches Passwort 2',
          resetConfirmed: true,
        );
        return null;
      } on ArchiveImportException catch (e) {
        return e.failure;
      }
    });
    expect(failure, ArchiveImportFailure.wrongPasswordOrDamaged);
    expect(
      await _snapshot(t, s) == before,
      isTrue,
      reason: 'unveraendert nach Fehler (Werte nie ausgeben)',
    );
    await t.runAsync(() => File(path!).delete());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
