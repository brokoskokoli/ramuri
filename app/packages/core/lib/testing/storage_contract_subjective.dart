import '../core.dart';
import 'contract_support.dart';

/// Vertrag der Angaben zum Lauf und der nachgetragenen Trainings (WP18).
final subjectiveContractCases = <StorageContractCase>[
  const StorageContractCase(
    'Angaben zum Lauf: speichern, ersetzen, leer entfernt, Fehlerarten',
    _runSubjective,
  ),
  const StorageContractCase(
    'Nachgetragene Trainings: anlegen, ändern, einzeln löschen, Reihenfolge',
    _manualTrainings,
  ),
  const StorageContractCase(
    'Angaben: Lauf löschen entfernt Angaben und sRPE, Training bleibt',
    _deleteRun,
  ),
  const StorageContractCase('Angaben und Trainings: Alles löschen', _deleteAll),
];

String _s(StoredRunSubjective? x) => x == null
    ? 'null'
    : '${x.subjective.rpe}|${x.subjective.wellbeing}|${x.subjective.complaints}|'
          '${x.subjective.warningAnswer?.name}|${x.subjective.note}|'
          '${x.srpe?.points}|${x.srpe?.duration.inSeconds}|${x.srpe?.method}|${x.srpe?.version}';

ManualTraining _training(int day, {int rpe = 5, int minutes = 45}) =>
    ManualTraining(
      day: DateTime.utc(2030, 1, day),
      kind: ManualTrainingKind.other,
      duration: Duration(minutes: minutes),
      rpe: rpe,
    );

Future<void> _runSubjective(StorageContractHarness h) async {
  final s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  expectEq(_s(await s.subjective.read(r)), 'null', 'zunächst nichts');

  final srpe = SrpeLoad.compute(duration: const Duration(minutes: 45), rpe: 5);
  await s.subjective.save(
    r,
    RunSubjective(
      rpe: 5,
      wellbeing: 4,
      complaints: 'Knie',
      warningAnswer: WarningAnswer.no,
      note: 'Notiz',
    ),
    srpe: srpe,
  );
  expectEq(
    _s(await s.subjective.read(r)),
    '5|4|Knie|no|Notiz|225.0|2700|${SrpeLoad.methodId}|${SrpeLoad.methodVersion}',
    'gespeichert',
  );
  expectEq((await s.subjective.readAll()).keys, [r], 'readAll');

  // Ersetzen ohne RPE: der sRPE-Wert ist weg, die übrigen Angaben bleiben.
  await s.subjective.save(r, RunSubjective(wellbeing: 2));
  expectEq(
    _s(await s.subjective.read(r)),
    'null|2|null|null|null|null|null|null|null',
    'ersetzt',
  );

  // Grenzfälle der Werte werden gespeichert (0 ist ein gültiges RPE).
  await s.subjective.save(r, RunSubjective(rpe: 0, wellbeing: 1));
  expectEq((await s.subjective.read(r))!.subjective.rpe, 0, 'RPE 0');
  await s.subjective.save(r, RunSubjective(rpe: 10, wellbeing: 5));
  expectEq((await s.subjective.read(r))!.subjective.rpe, 10, 'RPE 10');

  // sRPE passt nicht zum RPE: abgelehnt, nichts geändert.
  await expectFails(
    () => s.subjective.save(r, RunSubjective(rpe: 3), srpe: srpe),
    StorageFailure.rejected,
    'sRPE zu anderem RPE',
  );
  await expectFails(
    () => s.subjective.save(r, RunSubjective(wellbeing: 3), srpe: srpe),
    StorageFailure.rejected,
    'sRPE ohne RPE',
  );
  expectEq((await s.subjective.read(r))!.subjective.rpe, 10, 'unverändert');

  // Nur die sRPE-Spalten setzen: übrige Angaben bleiben, RPE muss noch passen.
  await s.subjective.save(
    r,
    RunSubjective(rpe: 10, wellbeing: 5, complaints: 'Knie', note: 'n'),
  );
  final srpe10 = SrpeLoad.compute(
    duration: const Duration(minutes: 30),
    rpe: 10,
  );
  expectTrue(
    await s.subjective.setSrpe(r, srpe10, expectedRpe: 10),
    'setSrpe greift',
  );
  expectEq(
    _s(await s.subjective.read(r)),
    '10|5|Knie|null|n|300.0|1800|${SrpeLoad.methodId}|${SrpeLoad.methodVersion}',
    'nur sRPE gesetzt, Rest unberührt',
  );
  expectTrue(
    !await s.subjective.setSrpe(r, null, expectedRpe: 9),
    'setSrpe bei geändertem RPE: nichts',
  );
  expectTrue(
    !await s.subjective.setSrpe(99, null, expectedRpe: 10),
    'setSrpe ohne Satz: nichts',
  );
  await expectFails(
    () => s.subjective.setSrpe(r, srpe10, expectedRpe: 3),
    StorageFailure.rejected,
    'setSrpe: sRPE zu anderem RPE',
  );
  expectTrue(
    await s.subjective.setSrpe(r, null, expectedRpe: 10),
    'setSrpe entfernt den Wert',
  );
  expectEq(
    _s(await s.subjective.read(r)),
    '10|5|Knie|null|n|null|null|null|null',
    'sRPE entfernt, Rest unberührt',
  );

  await expectFails(
    () => s.subjective.save(99, RunSubjective(rpe: 1)),
    StorageFailure.notFound,
    'unbekannter Lauf',
  );

  // Leere Angaben entfernen den Satz.
  await s.subjective.save(r, RunSubjective());
  expectEq(_s(await s.subjective.read(r)), 'null', 'leer entfernt');
  expectEq((await s.subjective.readAll()).length, 0, 'readAll leer');
  await s.close();
}

Future<void> _manualTrainings(StorageContractHarness h) async {
  final s = await h.open();
  expectEq((await s.manualTrainings.list()).length, 0, 'leer');
  final a = await s.manualTrainings.add(_training(3));
  final b = await s.manualTrainings.add(_training(5));
  final c = await s.manualTrainings.add(_training(5, rpe: 7));
  expectEq((await s.manualTrainings.list()).map((t) => t.id), [
    c.id,
    b.id,
    a.id,
  ], 'neuester Tag zuerst, dann höhere Id');
  final got = (await s.manualTrainings.get(c.id))!.training;
  expectTrue(got == _training(5, rpe: 7), 'zurückgelesen gleich');

  await s.manualTrainings.update(
    a.id,
    ManualTraining(
      day: DateTime.utc(2030, 1, 9),
      kind: ManualTrainingKind.run,
      duration: const Duration(seconds: 90),
      rpe: 0,
    ),
  );
  final u = (await s.manualTrainings.get(a.id))!.training;
  expectEq(
    '${u.isoDay}|${u.kind.name}|${u.duration.inSeconds}|${u.rpe}',
    '2030-01-09|run|90|0',
    'geändert',
  );

  await s.manualTrainings.delete(b.id);
  expectEq((await s.manualTrainings.list()).map((t) => t.id), [
    a.id,
    c.id,
  ], 'einzeln gelöscht');
  await expectFails(
    () => s.manualTrainings.delete(b.id),
    StorageFailure.notFound,
    'doppelt löschen',
  );
  await expectFails(
    () => s.manualTrainings.update(b.id, _training(1)),
    StorageFailure.notFound,
    'unbekannt ändern',
  );
  expectTrue(await s.manualTrainings.get(b.id) == null, 'get unbekannt');
  await s.close();
}

Future<void> _deleteRun(StorageContractHarness h) async {
  final s = await h.open();
  final a = (await s.runs.create(startedAt: at(0))).id;
  final b = (await s.runs.create(startedAt: at(1))).id;
  final srpe = SrpeLoad.compute(duration: const Duration(minutes: 10), rpe: 4);
  for (final r in [a, b]) {
    await s.subjective.save(r, RunSubjective(rpe: 4, note: 'x'), srpe: srpe);
  }
  await s.manualTrainings.add(_training(2));
  await s.deleteRun(a);
  expectTrue(await s.subjective.read(a) == null, 'Angaben des Laufs weg');
  expectTrue(await s.subjective.read(b) != null, 'Angaben des anderen bleiben');
  expectEq((await s.manualTrainings.list()).length, 1, 'Training bleibt');
  await s.close();
}

Future<void> _deleteAll(StorageContractHarness h) async {
  var s = await h.open();
  final r = (await s.runs.create(startedAt: at(0))).id;
  await s.subjective.save(r, RunSubjective(rpe: 4));
  await s.manualTrainings.add(_training(2));
  await s.deleteAll();
  expectEq((await s.subjective.readAll()).length, 0, 'Angaben');
  expectEq((await s.manualTrainings.list()).length, 0, 'Trainings');
  await s.close();
  s = await h.open();
  expectEq((await s.manualTrainings.list()).length, 0, 'nach Neuöffnen');
  final t = await s.manualTrainings.add(_training(2));
  expectEq(t.id, 1, 'Zähler zurückgesetzt');
  await s.close();
}
