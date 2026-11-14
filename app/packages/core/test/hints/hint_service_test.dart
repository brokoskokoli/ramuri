import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Hinweisdienst: Eingaben aus dem Speicher, Sperre über mehrere Tage
/// (PAR-175), Karte „Erholung“, Warnsignal.
void main() {
  late FakeStorage fs;
  late RecalcWorld w;
  late HintService service;

  // recalcNow = 2030-03-01 12:00 UTC, Versatz 0.
  final today = DateTime.utc(2030, 3, 1);
  DateTime ago(int n) => today.subtract(Duration(days: n));

  setUp(() async {
    fs = FakeStorage();
    w = await RecalcWorld.create(storage: fs);
    service = HintService(session: w.session, clock: w.clock);
  });

  Future<int> addRun(int daysAgo, {int? rpe, int? wellbeing}) async {
    final end = ago(daysAgo).add(const Duration(hours: 9));
    final run = await w.session.runs.create(
      startedAt: end.subtract(const Duration(minutes: 30)),
    );
    await w.session.runs.setState(
      run.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: Duration.zero,
    );
    if (rpe != null || wellbeing != null) {
      await w.session.subjective.save(
        run.id,
        RunSubjective(rpe: rpe, wellbeing: wellbeing),
      );
    }
    return run.id;
  }

  void plan(int daysAgo, PlanUnitKind kind, {int? runId, int id = 1}) {
    fs.data.planVersions[1] = PlanVersionRecord(
      id: 1,
      goalId: 1,
      createdAt: recalcNow,
      validFrom: ago(90),
      trigger: PlanTrigger.create,
      reason: 'start',
      version: const PlanVersion(),
      inputsJson: '{}',
      summaryJson: '{}',
    );
    fs.data.planUnits[id] = PlanUnit(
      id: id,
      day: ago(daysAgo),
      kind: kind,
      phase: PlanPhase.build,
      weekIndex: 0,
      minutes: 40,
      runId: runId,
      segments: const [],
    );
    fs.data.planUnitPlan[id] = 1;
  }

  test('Pausenfrage: eine übernommene fremde Einheit zählt erst nach dem '
      'Übernehmen als letztes Training', () async {
    await addRun(30);
    final before = (await service.pauseQuestion())!;
    expect(before.lastTrainingDay, ago(30));

    // Nachtrag aus der Übernahme (hc_id) vor 10 Tagen: neuer Stand der Pause.
    await w.session.manualTrainings.add(
      ManualTraining(
        day: ago(10),
        kind: ManualTrainingKind.run,
        duration: const Duration(minutes: 40),
        rpe: 4,
        hcId: 'ex-1',
      ),
    );
    final after = (await service.pauseQuestion())!;
    expect(after.lastTrainingDay, ago(10));
    expect(after.daysSinceTraining, 10);

    // Vor 2 Tagen: keine Pause mehr, keine Frage.
    await w.session.manualTrainings.add(
      ManualTraining(
        day: ago(2),
        kind: ManualTrainingKind.run,
        duration: const Duration(minutes: 40),
        rpe: 4,
        hcId: 'ex-2',
      ),
    );
    expect(await service.pauseQuestion(), isNull);
  });

  test('keine Daten: kein Hinweis, keine Karte, nichts gespeichert', () async {
    expect((await service.today()).hint, isNull);
    expect(await service.recoveryCard(), isNull);
    expect(await w.session.settings.get(hintShownKey), anyOf(isNull, ''));
  });

  test('Befinden niedrig beim letzten Lauf: Karte mit Belegen', () async {
    await addRun(1, rpe: 4, wellbeing: 2);
    final card = (await service.recoveryCard())!;
    expect(card.code, HintCode.lowWellbeing);
    expect(card.basis.map((e) => e.key), [
      EvidenceKey.wellbeing,
      EvidenceKey.wellbeingDaysAgo,
    ]);
  });

  test(
    'PAR-179 aus Lauf-RPE und Plan: gestern RPE 8, heute Intervalle',
    () async {
      await addRun(1, rpe: 8);
      plan(0, PlanUnitKind.intervals);
      final h = (await service.today()).hint!;
      expect(h.code, HintCode.shortInterval);
      expect(h.action, HintAction.easyRun);
    },
  );

  test(
    'PAR-182 aus den letzten locker geplanten Einheiten mit Lauf-RPE',
    () async {
      for (var i = 0; i < 3; i++) {
        final id = await addRun(2 + i * 2, rpe: i == 2 ? 3 : 6);
        plan(2 + i * 2, PlanUnitKind.easy, runId: id, id: 10 + i);
      }
      plan(0, PlanUnitKind.tempo);
      final h = (await service.today()).hint!;
      expect(h.code, HintCode.effortAbovePlan);
      expect(h.evidenceOf(EvidenceKey.easyRunsAboveRpe), 2);
    },
  );

  test(
    'Wiederholte Abfrage zählt nicht doppelt; Befinden verfällt nach 3 Tagen',
    () async {
      // Befinden 1 beim Lauf vor 5 Tagen ist nur 3 Tage lang gültig; daher
      // wandert die Uhr nicht, sondern das Befinden kommt mit einem frischen
      // Lauf je Tag.
      final shown = <HintCode?>[];
      for (var day = 0; day < 5; day++) {
        final clock = FakeClock(recalcNow.add(Duration(days: day)));
        final svc = HintService(session: w.session, clock: clock);
        // Wiederholte Abfrage am selben Tag zählt nicht doppelt.
        await svc.today();
        shown.add((await svc.today()).hint?.code);
        if (day == 0) await addRun(0, wellbeing: 1);
      }
      // Tag 0: Lauf noch nicht da. Tage 1 bis 3 gezeigt, Tag 4: Lauf vor 4
      // Tagen ist zu alt; die Sperre wird deshalb durch Alter gedeckt.
      expect(shown, [
        null,
        HintCode.lowWellbeing,
        HintCode.lowWellbeing,
        HintCode.lowWellbeing,
        null,
      ]);
    },
  );

  test(
    'PAR-175: 3 Tage in Folge gezeigt, am 4. Tag gesperrt, am 5. wieder',
    () async {
      final out = <HintCode?>[];
      for (var day = 0; day < 5; day++) {
        final clock = FakeClock(recalcNow.add(Duration(days: day)));
        final svc = HintService(session: w.session, clock: clock);
        final end = ago(-day).add(const Duration(hours: 8));
        final run = await w.session.runs.create(
          startedAt: end.subtract(const Duration(minutes: 30)),
        );
        await w.session.runs.setState(
          run.id,
          RunState.finished,
          endedAt: end,
          endedUtcOffset: Duration.zero,
        );
        await w.session.subjective.save(run.id, RunSubjective(wellbeing: 1));
        out.add((await svc.today()).hint?.code);
      }
      expect(out, [
        HintCode.lowWellbeing,
        HintCode.lowWellbeing,
        HintCode.lowWellbeing,
        null,
        HintCode.lowWellbeing,
      ]);
    },
  );

  test(
    'Warnsignal: fester Hinweis vor allem, nicht im Verlauf der Sperre',
    () async {
      await addRun(1, rpe: 8, wellbeing: 1);
      plan(0, PlanUnitKind.intervals);
      fs.data.warning = WarningSignal(
        reportedOn: ago(2),
        source: WarningSource.manual,
      );
      final h = (await service.today()).hint!;
      expect(h.code, HintCode.warning);
      expect(await w.session.settings.get(hintShownKey), anyOf(isNull, ''));
      expect((await service.recoveryCard())!.code, HintCode.warning);
      fs.data.warning = null;
      expect((await service.today()).hint!.code, HintCode.shortInterval);
    },
  );

  test('PAR-180: ohne Zusage und Pause nichts, mit Zusage Hinweis', () async {
    await addRun(10);
    expect((await service.today()).hint, isNull);
    await LoadSettings.saveAllRecorded(w.session.settings, true, at: recalcNow);
    expect((await service.today()).hint!.code, HintCode.pause);
  });

  test('Nachtrag zählt als Training für den Abstand', () async {
    await addRun(30);
    await LoadSettings.saveAllRecorded(w.session.settings, true, at: recalcNow);
    await w.session.manualTrainings.add(
      ManualTraining(
        day: ago(2),
        kind: ManualTrainingKind.other,
        duration: const Duration(minutes: 30),
        rpe: 4,
      ),
    );
    expect((await service.today()).hint, isNull);
  });
}
