import 'package:core/core.dart';
import 'package:core/testing/contract_support.dart' show at;
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

Future<void> _setTimes(
  StorageSession s,
  int runId, {
  required Duration total,
  required Duration? moving,
}) => s.preprocessing.replace(
  runId,
  StoredPreprocessing(
    summary: PreprocessingSummary(
      method: 'preprocessing',
      methodVersion: 1,
      parameterVersion: 2,
      computedAt: at(0),
      totalTime: total,
      movingTime: moving,
    ),
  ),
);

void main() {
  late RecalcWorld w;
  late SubjectiveService service;
  late int run;

  setUp(() async {
    w = await RecalcWorld.create();
    service = SubjectiveService(session: w.session, clock: w.clock);
    run = (await w.session.runs.create(startedAt: at(0))).id;
  });

  test(
    'sRPE nimmt die Bewegungszeit, nicht die Gesamtzeit (OQ-0015)',
    () async {
      await _setTimes(
        w.session,
        run,
        total: const Duration(minutes: 60),
        moving: const Duration(minutes: 45),
      );
      await service.save(run, RunSubjective(rpe: 5));
      final s = (await service.read(run))!.srpe!;
      expect(s.points, 225);
      expect(s.duration, const Duration(minutes: 45));
      expect(s.points, isNot(300));
    },
  );

  test('sRPE folgt dem RPE: geändert, dann entfernt', () async {
    await _setTimes(
      w.session,
      run,
      total: const Duration(minutes: 50),
      moving: const Duration(minutes: 40),
    );
    await service.save(run, RunSubjective(rpe: 5));
    expect((await service.read(run))!.srpe!.points, 200);
    await service.save(run, RunSubjective(rpe: 6, note: 'n'));
    expect((await service.read(run))!.srpe!.points, 240);
    await service.save(run, RunSubjective(note: 'n'));
    final kept = (await service.read(run))!;
    expect(kept.srpe, isNull);
    expect(kept.subjective.note, 'n');
  });

  test(
    'ohne Bewegungszeit kein Wert, nie 0; nach der Berechnung folgt er',
    () async {
      await service.save(run, RunSubjective(rpe: 5));
      expect((await service.read(run))!.srpe, isNull);
      await _setTimes(
        w.session,
        run,
        total: const Duration(minutes: 30),
        moving: null,
      );
      await refreshSrpe(w.session, run);
      expect((await service.read(run))!.srpe, isNull);
      await _setTimes(
        w.session,
        run,
        total: const Duration(minutes: 30),
        moving: const Duration(minutes: 20),
      );
      await refreshSrpe(w.session, run);
      expect((await service.read(run))!.srpe!.points, 100);
    },
  );

  test('Neuberechnung der Bewegungszeit: Wert ist aktuell (refresh)', () async {
    await _setTimes(
      w.session,
      run,
      total: const Duration(minutes: 30),
      moving: const Duration(minutes: 20),
    );
    await service.save(run, RunSubjective(rpe: 5));
    await _setTimes(
      w.session,
      run,
      total: const Duration(minutes: 30),
      moving: const Duration(minutes: 28),
    );
    await refreshSrpe(w.session, run);
    expect((await service.read(run))!.srpe!.points, 140);
    // Ohne Angaben passiert nichts und es entsteht kein Satz.
    final other = (await w.session.runs.create(startedAt: at(5))).id;
    await refreshSrpe(w.session, other);
    expect(await service.read(other), isNull);
  });

  test('Berechnung nach dem Lauf zieht sRPE nach, TRIMP bleibt unberührt und getrennt (FR-0096)', () async {
    final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 30);
    await service.save(id, RunSubjective(rpe: 5));
    expect((await service.read(id))!.srpe, isNull);
    await w.calc().calculateAfterRun(id);
    final srpe = (await service.read(id))!.srpe!;
    final moving = (await w.session.preprocessing.read(id))!
        .summary
        .movingTime!;
    expect(srpe.duration, moving);
    expect(
      srpe.points,
      moving.inMicroseconds * 5 / Duration.microsecondsPerMinute,
    );

    // TRIMP und sRPE sind getrennte Werte: sRPE steht nicht unter den Laufwerten,
    // TRIMP ist genauso hoch wie ohne Angabe, und es gibt keinen Summenwert.
    final keys = [
      for (final p in await w.session.values.read(ValueOwner.run(id)))
        p.current.key,
    ];
    expect(keys, contains(trimpRunValueKey));
    expect(keys.where((k) => k.contains('srpe')), isEmpty);
    final withRpe = (await w.session.values.read(ValueOwner.run(id)))
        .firstWhere((p) => p.current.key == trimpRunValueKey)
        .current
        .value;
    final w2 = await RecalcWorld.create();
    final id2 = await w2.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 30);
    await w2.calc().calculateAfterRun(id2);
    final without = (await w2.session.values.read(ValueOwner.run(id2)))
        .firstWhere((p) => p.current.key == trimpRunValueKey)
        .current
        .value;
    expect(withRpe, without);
    expect(withRpe, isNot(srpe.points));
  });

  test('Neuberechnung (WP09) lässt Angabe und sRPE bestehen', () async {
    final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 30);
    await w.calc().calculateAfterRun(id);
    await service.save(id, RunSubjective(rpe: 4));
    final before = (await service.read(id))!.srpe!;
    await w.session.profile.save(profile180);
    final recalc = w.recalc();
    final offer = await recalc.profileChanged(
      before: profile190,
      after: profile180,
    );
    await recalc.confirm(offer!);
    final after = (await service.read(id))!;
    expect(after.subjective.rpe, 4);
    expect(after.srpe, before);
  });

  test(
    'Lauf löschen entfernt Angaben und sRPE, nachgetragenes Training bleibt',
    () async {
      await _setTimes(
        w.session,
        run,
        total: const Duration(minutes: 30),
        moving: const Duration(minutes: 30),
      );
      await service.save(run, RunSubjective(rpe: 5));
      await service.addTraining(
        ManualTraining(
          day: DateTime.utc(2030, 2, 1),
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 10),
          rpe: 3,
        ),
      );
      await w.session.deleteRun(run);
      expect(await service.read(run), isNull);
      expect(await service.trainings(), hasLength(1));
      await w.session.deleteAll();
      expect(await service.trainings(), isEmpty);
    },
  );

  test(
    'nachgetragenes Training: Tag nicht in der Zukunft, einzeln löschbar',
    () async {
      // Uhr steht auf 2030-03-01 12:00 UTC (+ Laufende der Welt).
      final today = w.clock.now();
      ManualTraining on(DateTime d) => ManualTraining(
        day: d,
        kind: ManualTrainingKind.run,
        duration: const Duration(minutes: 20),
        rpe: 2,
      );
      final ok = await service.addTraining(on(today));
      await service.addTraining(on(today.subtract(const Duration(days: 3))));
      await expectLater(
        service.addTraining(on(today.add(const Duration(days: 1)))),
        throwsA(isA<SubjectiveRangeError>()),
      );
      expect(await service.trainings(), hasLength(2));
      await expectLater(
        service.updateTraining(ok.id, on(today.add(const Duration(days: 2)))),
        throwsA(isA<SubjectiveRangeError>()),
      );
      await service.deleteTraining(ok.id);
      expect(await service.trainings(), hasLength(1));
      // Ein nachgetragenes Training erzeugt keinen Lauf.
      expect(await w.session.runs.list(), hasLength(1));
    },
  );

  test('Training heute im Ortstag: kurz nach Ortsmitternacht (+1 h)', () async {
    // 23:30 UTC am 1.1. ist in UTC+1 schon der 2.1.
    final clock = FakeClock(
      DateTime.utc(2030, 1, 1, 23, 30),
      utcOffset: const Duration(hours: 1),
    );
    final svc = SubjectiveService(session: w.session, clock: clock);
    ManualTraining on(int day) => ManualTraining(
      day: DateTime.utc(2030, 1, day),
      kind: ManualTrainingKind.run,
      duration: const Duration(minutes: 20),
      rpe: 2,
    );
    final today = await svc.addTraining(on(2));
    await svc.updateTraining(today.id, on(2));
    await expectLater(
      svc.addTraining(on(3)),
      throwsA(isA<SubjectiveRangeError>()),
    );
    await expectLater(
      svc.updateTraining(today.id, on(3)),
      throwsA(isA<SubjectiveRangeError>()),
    );
  });

  test(
    'Training: westlich von UTC (-5 h) ist der Ortstag noch gestern',
    () async {
      // 02:00 UTC am 2.1. ist in UTC-5 noch der 1.1. um 21 Uhr.
      final clock = FakeClock(
        DateTime.utc(2030, 1, 2, 2),
        utcOffset: const Duration(hours: -5),
      );
      final svc = SubjectiveService(session: w.session, clock: clock);
      ManualTraining on(int day) => ManualTraining(
        day: DateTime.utc(2030, 1, day),
        kind: ManualTrainingKind.run,
        duration: const Duration(minutes: 20),
        rpe: 2,
      );
      await svc.addTraining(on(1));
      // „Morgen“ im Ortstag, obwohl in UTC schon heute.
      await expectLater(
        svc.addTraining(on(2)),
        throwsA(isA<SubjectiveRangeError>()),
      );
      expect(await svc.trainings(), hasLength(1));
    },
  );

  test('refreshSrpe überschreibt eine parallele Änderung nicht', () async {
    await _setTimes(
      w.session,
      run,
      total: const Duration(minutes: 50),
      moving: const Duration(minutes: 40),
    );
    await service.save(run, RunSubjective(rpe: 5, note: 'alt'));
    // Bewegungszeit ändert sich; der Aufruf liest zuerst, dann schreibt ein
    // anderer Weg Notiz und Befinden, bevor die Neuberechnung speichert.
    await _setTimes(
      w.session,
      run,
      total: const Duration(minutes: 60),
      moving: const Duration(minutes: 50),
    );
    final racing = _RacingSession(w.session, () async {
      await service.save(run, RunSubjective(rpe: 5, note: 'neu', wellbeing: 4));
    });
    await refreshSrpe(racing, run);
    final s = (await service.read(run))!;
    expect(s.subjective.note, 'neu');
    expect(s.subjective.wellbeing, 4);
    expect(s.srpe!.points, 250);
  });

  test(
    'refreshSrpe: geändertes RPE wird nicht mit altem Wert belegt',
    () async {
      await _setTimes(
        w.session,
        run,
        total: const Duration(minutes: 50),
        moving: const Duration(minutes: 40),
      );
      await service.save(run, RunSubjective(rpe: 5));
      // Neue Bewegungszeit: die Neuberechnung hat etwas zu schreiben.
      await _setTimes(
        w.session,
        run,
        total: const Duration(minutes: 60),
        moving: const Duration(minutes: 50),
      );
      final racing = _RacingSession(w.session, () async {
        await service.save(run, RunSubjective(rpe: 7));
      });
      await refreshSrpe(racing, run);
      final s = (await service.read(run))!;
      expect(s.subjective.rpe, 7);
      expect(s.srpe!.points, 350);
    },
  );

  test('unbekannter Lauf: notFound', () async {
    await expectLater(
      service.save(999, RunSubjective(rpe: 5)),
      throwsA(
        isA<StorageException>().having(
          (e) => e.failure,
          'f',
          StorageFailure.notFound,
        ),
      ),
    );
  });
}

/// Führt nach dem ersten Lesen der Angaben eine parallele Änderung aus.
class _RacingSession implements StorageSession {
  _RacingSession(this._inner, this._race);
  final StorageSession _inner;
  final Future<void> Function() _race;

  @override
  RunSubjectiveStore get subjective => _RacingStore(_inner.subjective, _race);

  @override
  PreprocessingStore get preprocessing => _inner.preprocessing;

  // Mehr braucht refreshSrpe nicht; alles andere wirft hier bewusst.
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RacingStore implements RunSubjectiveStore {
  _RacingStore(this._inner, this._race);
  final RunSubjectiveStore _inner;
  Future<void> Function()? _race;

  @override
  Future<StoredRunSubjective?> read(int runId) async {
    final r = await _inner.read(runId);
    final race = _race;
    _race = null;
    if (race != null) await race();
    return r;
  }

  @override
  Future<Map<int, StoredRunSubjective>> readAll() => _inner.readAll();

  @override
  Future<void> save(int runId, RunSubjective subjective, {SrpeLoad? srpe}) =>
      _inner.save(runId, subjective, srpe: srpe);

  @override
  Future<bool> setSrpe(
    int runId,
    SrpeLoad? srpe, {
    required int? expectedRpe,
  }) => _inner.setSrpe(runId, srpe, expectedRpe: expectedRpe);
}
