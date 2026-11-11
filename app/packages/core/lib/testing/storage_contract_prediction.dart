import '../core.dart';
import 'contract_support.dart';

/// Vertrag der Prognose-Daten (WP20): Referenzleistungen und abgelehnte
/// Vorschläge. Der Speicher muss [PredictionStorage] sein.
final List<StorageContractCase> predictionContractCases = [
  const StorageContractCase(
    'Referenzleistungen: anlegen, jüngste gilt, löschen',
    _references,
  ),
  const StorageContractCase(
    'Referenzleistungen: ungültige werden abgelehnt',
    _invalid,
  ),
  const StorageContractCase(
    'Referenzleistungen: ein Lauf wird höchstens einmal Referenz',
    _idempotent,
  ),
  const StorageContractCase(
    'Referenzleistungen: gleichzeitige Aufrufe für einen Lauf ergeben eine Zeile',
    _concurrent,
  ),
  const StorageContractCase(
    'Referenz und Ablehnung verschwinden mit dem Lauf',
    _cascade,
  ),
  const StorageContractCase(
    'Referenz aus bestätigtem Lauf löschen lehnt den Lauf ab, manuelle nicht',
    _deleteConfirmed,
  ),
  const StorageContractCase('Alles löschen leert Prognose-Daten', _deleteAll),
];

PredictionStore _p(StorageSession s) => (s as PredictionStorage).prediction;

ReferencePerformance _ref({
  ReferenceKind kind = ReferenceKind.race,
  double meters = 10000,
  double seconds = 3000,
  required DateTime date,
  required DateTime createdAt,
  String? runId,
}) => ReferencePerformance(
  kind: kind,
  distanceMeters: meters,
  seconds: seconds,
  date: date,
  createdAt: createdAt,
  runId: runId,
);

String _d(ReferencePerformance r) =>
    '${r.kind.name}/${r.distanceMeters}/${r.seconds}/'
    '${calendarDay(r.date)}/${us(r.createdAt)}/${r.runId}';

Future<void> _references(StorageContractHarness h) async {
  var s = await h.open();
  final p = _p(s);
  expectTrue(await p.activeReference() == null, 'ohne Referenz keine aktive');
  expectEq(await p.references(), [], 'leer');
  final a = await p.addReference(
    _ref(date: DateTime(2029, 12, 21), createdAt: at(10, 7)),
  );
  final b = await p.addReference(
    _ref(
      kind: ReferenceKind.test,
      meters: 5000,
      seconds: 1500.5,
      date: DateTime(2029, 12, 22),
      createdAt: at(5),
    ),
  );
  // Gleiches Datum wie b, später angelegt: gewinnt.
  final c = await p.addReference(
    _ref(date: DateTime(2029, 12, 22), createdAt: at(20)),
  );
  expectTrue(a != b && b != c && a != c, 'Kennungen verschieden');
  expectEq((await p.references()).map((r) => r.id), [
    c,
    b,
    a,
  ], 'jüngste zuerst');
  expectEq(
    _d((await p.activeReference())!),
    _d(_ref(date: DateTime(2029, 12, 22), createdAt: at(20))),
    'aktive: jüngste nach Datum, bei gleichem Datum die zuletzt angelegte',
  );
  // Werte und Mikrosekunden bleiben erhalten.
  final stored = (await p.references()).firstWhere((r) => r.id == a).reference;
  expectEq(
    _d(stored),
    _d(_ref(date: DateTime(2029, 12, 21), createdAt: at(10, 7))),
    'Werte unverändert',
  );
  await p.deleteReference(c);
  expectEq((await p.references()).map((r) => r.id), [b, a], 'gelöscht');
  expectEq(
    (await p.activeReference())!.kind.name,
    'test',
    'danach gilt die nächste',
  );
  await expectFails(
    () => p.deleteReference(c),
    StorageFailure.notFound,
    'unbekannte Referenz löschen',
  );
  await s.close();
  s = await h.open();
  expectEq((await _p(s).references()).map((r) => r.id), [
    b,
    a,
  ], 'überlebt Schließen und Öffnen');
  await s.close();
}

Future<void> _invalid(StorageContractHarness h) async {
  final s = await h.open();
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  final ok = _ref(date: DateTime(2030, 1, 1), createdAt: at(0));
  Future<void> rejects(ReferencePerformance r, String what) =>
      expectFails(() => p.addReference(r), StorageFailure.rejected, what);
  await rejects(
    _ref(meters: 2999, date: ok.date, createdAt: ok.createdAt),
    'zu kurz',
  );
  await rejects(
    _ref(seconds: 0, date: ok.date, createdAt: ok.createdAt),
    'Zeit 0',
  );
  await rejects(
    _ref(
      meters: 5000,
      seconds: 999 * 3600,
      date: ok.date,
      createdAt: ok.createdAt,
    ),
    'Tempo außerhalb der Spanne (5 km in 999 h)',
  );
  await rejects(
    _ref(date: DateTime(2030, 1, 3), createdAt: at(0)),
    'Datum nach dem Anlegen',
  );
  await rejects(
    _ref(
      kind: ReferenceKind.confirmedRun,
      date: ok.date,
      createdAt: ok.createdAt,
    ),
    'bestätigter Lauf ohne Lauf-ID',
  );
  await rejects(
    _ref(
      kind: ReferenceKind.confirmedRun,
      date: ok.date,
      createdAt: ok.createdAt,
      runId: '${run + 99}',
    ),
    'unbekannter Lauf',
  );
  expectEq((await p.references()).length, 0, 'nichts geschrieben');
  await expectFails(
    () => p.rejectSuggestion(run + 99),
    StorageFailure.notFound,
    'Ablehnen eines unbekannten Laufs',
  );
  await s.close();
}

Future<void> _cascade(StorageContractHarness h) async {
  final s = await h.open();
  final p = _p(s);
  final a = (await s.runs.create(startedAt: at(0))).id;
  final b = (await s.runs.create(startedAt: at(1))).id;
  for (final r in [a, b]) {
    await p.addReference(
      _ref(
        kind: ReferenceKind.confirmedRun,
        date: DateTime(2029, 12, 20),
        createdAt: at(r),
        runId: '$r',
      ),
    );
    await p.rejectSuggestion(r);
  }
  // Wettkampfzeit ohne Lauf bleibt.
  await p.addReference(_ref(date: DateTime(2029, 12, 20), createdAt: at(3)));
  await p.rejectSuggestion(b); // idempotent
  expectEq(await p.rejectedSuggestions(), {a, b}, 'abgelehnt');
  await s.deleteRun(a);
  final left = await p.references();
  expectEq(left.length, 2, 'Referenz des Laufs weg');
  expectEq(left.map((r) => '${r.reference.runId}').toList()..sort(), [
    '$b',
    'null',
  ], 'andere Referenzen bleiben');
  expectEq(await p.rejectedSuggestions(), {b}, 'Ablehnung des Laufs weg');
  await s.close();
}

Future<void> _deleteAll(StorageContractHarness h) async {
  var s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  await _p(s).addReference(
    _ref(
      kind: ReferenceKind.confirmedRun,
      date: DateTime(2029, 12, 20),
      createdAt: at(1),
      runId: '$r',
    ),
  );
  await _p(s)
      .addReference(_ref(date: DateTime(2029, 12, 20), createdAt: at(2)));
  await _p(s).rejectSuggestion(r);
  await s.deleteAll();
  expectEq((await _p(s).references()).length, 0, 'Referenzen');
  expectEq((await _p(s).rejectedSuggestions()).length, 0, 'Ablehnungen');
  await s.close();
  s = await h.open();
  expectEq((await _p(s).references()).length, 0, 'nach Neuöffnen');
  final id = await _p(s)
      .addReference(_ref(date: DateTime(2029, 12, 20), createdAt: at(3)));
  expectEq(id, 1, 'Zähler zurückgesetzt');
  await s.close();
}

Future<void> _idempotent(StorageContractHarness h) async {
  final s = await h.open();
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  ReferencePerformance confirmed(int hour) => _ref(
    kind: ReferenceKind.confirmedRun,
    date: DateTime(2029, 12, 20),
    createdAt: at(hour),
    runId: '$run',
  );
  final a = await p.addReference(confirmed(1));
  final b = await p.addReference(confirmed(2));
  expectEq(b, a, 'zweites Speichern gibt die vorhandene Kennung');
  expectEq((await p.references()).length, 1, 'keine Doppelzeile');
  await s.close();
}

/// Doppeltippen: zwei gleichzeitige Aufrufe für denselben Lauf (Soll 8).
Future<void> _concurrent(StorageContractHarness h) async {
  final s = await h.open();
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  ReferencePerformance confirmed(int hour) => _ref(
    kind: ReferenceKind.confirmedRun,
    date: DateTime(2029, 12, 20),
    createdAt: at(hour),
    runId: '$run',
  );
  final ids = await Future.wait([
    p.addReference(confirmed(1)),
    p.addReference(confirmed(2)),
  ]);
  expectEq(ids[1], ids[0], 'gleichzeitig: dieselbe Kennung');
  expectEq((await p.references()).length, 1, 'gleichzeitig: keine Doppelzeile');
  await s.close();
}

Future<void> _deleteConfirmed(StorageContractHarness h) async {
  var s = await h.open();
  final p = _p(s);
  // Wegwerf-Läufe vorher: Lauf- und Referenzkennung laufen auseinander, damit
  // eine Verwechslung von Referenz-Id und Lauf-Id auffällt.
  await s.runs.create(startedAt: at(0));
  await s.runs.create(startedAt: at(0));
  final a = (await s.runs.create(startedAt: at(0))).id;
  final confirmed = await p.addReference(
    _ref(
      kind: ReferenceKind.confirmedRun,
      date: DateTime(2029, 12, 20),
      createdAt: at(1),
      runId: '$a',
    ),
  );
  final manual = await p.addReference(
    _ref(date: DateTime(2029, 12, 21), createdAt: at(2)),
  );
  await p.deleteReference(manual);
  expectEq(await p.rejectedSuggestions(), <int>{}, 'manuelle: keine Ablehnung');
  expectTrue(a != confirmed && a != manual, 'Kennungen laufen auseinander');
  await p.deleteReference(confirmed);
  expectEq((await p.references()).length, 0, 'Referenz weg');
  expectEq(await p.rejectedSuggestions(), {a}, 'Lauf abgelehnt');
  await expectFails(
    () => p.deleteReference(confirmed),
    StorageFailure.notFound,
    'zweites Löschen',
  );
  expectEq(await p.rejectedSuggestions(), {a}, 'unverändert');
  await s.close();
  s = await h.open();
  expectEq(await _p(s).rejectedSuggestions(), {a}, 'überlebt Neuöffnen');
  await s.close();
}
