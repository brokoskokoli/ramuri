import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'helpers/local_clock.dart';

// Unterforderung in der App (PAR-236, FR-0216): Der Controller zeigt beim
// ersten Muster den Hinweis „HFmax prüfen“, bei erneutem Muster aus späteren
// Läufen die Frage „Plan etwas steigern?“; nur „Ja, steigern“ ändert den
// Plan. Synthetische Daten: Ziel, Plan und Läufe sind ausgedacht.

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i + 5));

final _d0 = DateTime.utc(2026, 11, 16); // Montag
DateTime _day(int n) => _d0.add(Duration(days: n));

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// Lauftage Dienstag, Mittwoch, Freitag, Sonntag.
TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {2, 3, 5, 7},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

class _Env {
  _Env(this.storage, this.session, this.clock, {this.readiness});

  final FakeStorage storage;
  final StorageSession session;
  final LocalFakeClock clock;
  final Future<PlanReadinessDay?> Function(DateTime day)? readiness;

  PlanRepository get plans => (session as PlanStorage).plans;

  /// Neuer Controller wie nach einem Neustart der App; mit [exclusive] wie
  /// in der App hinter der Sperre der Wertberechnung.
  PlanController controller({
    Future<void> Function(Future<void> Function() action)? exclusive,
  }) => PlanController(
    session: session,
    clock: clock,
    reader: PlanDataReader(session: session, clock: clock),
    readinessToday: readiness,
    exclusive: exclusive,
  );

  /// Plan ab Montag [_d0] (Wochenzeit 120 min, Rechnung ab Tag 14), Schalter
  /// [mode], Uhr am Montag (Tag 14) früh.
  static Future<_Env> open(
    PlanAdaptationMode mode, {
    Future<PlanReadinessDay?> Function(DateTime day)? readiness,
  }) async {
    final storage = FakeStorage();
    final session = await storage.open(_key);
    final e = _Env(
      storage,
      session,
      LocalFakeClock(DateTime(2026, 11, 30, 6)),
      readiness: readiness,
    );
    await (session as GoalStorage).goals.save(_goal(), today: _day(0));
    await recalculatePlan(
      plans: e.plans,
      settings: session.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: DateTime.utc(2026, 11, 16, 5),
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 120),
    );
    await SettingsPlanAdaptationStore(session.settings)
        .set(mode, at: DateTime.utc(2026, 11, 16, 5));
    await recalculatePlan(
      plans: e.plans,
      settings: session.settings,
      trigger: PlanTrigger.manual,
      today: _day(14),
      now: DateTime.utc(2026, 11, 30, 5),
      markChecked: false,
    );
    return e;
  }

  /// Wochenprüfung für heute als erledigt markieren (sonst rechnet das
  /// Öffnen am Montag die Woche neu; nicht Teil dieser Regel).
  Future<void> checked() => session.settings.set(
    planLastCheckDayKey,
    _iso(calendarDay(clock.now())),
    at: clock.now(),
  );

  /// Lauf am Tag [n] (Ende 7:40 Uhr Ortszeit), der lockeren Einheit dieses
  /// Tags zugeordnet, mit RPE [rpe] und [highHr] Minuten bei mindestens 80 %
  /// HFmax; die Uhr steht danach auf 8 Uhr dieses Tags.
  /// Mit [sport] ist es eine andere Sportart (FR-0221), die die Einheit
  /// ersetzt (FR-0222). Ohne [assign] bleibt die Zuordnung aus (wie nach
  /// einem Absturz am Lauf-Ende); das Öffnen holt sie nach (PAR-231).
  Future<int> run(
    int n, {
    int? rpe = 3,
    double? highHr = 12,
    bool sport = false,
    bool assign = true,
  }) async {
    final unit = (await plans.unitOn(_day(n)))!;
    expect(unit.kind, isIn([PlanUnitKind.easy, PlanUnitKind.long]));
    final start = DateTime(_day(n).year, _day(n).month, _day(n).day, 7);
    final r = sport
        ? await session.runs.create(
            startedAt: start,
            mode: RunMode.sport,
            sport: OtherSport.rope,
          )
        : await session.runs.create(startedAt: start);
    final end = start.add(const Duration(minutes: 40));
    await session.runs.setState(
      r.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: end.timeZoneOffset,
    );
    if (rpe != null) {
      await session.subjective.save(r.id, RunSubjective(rpe: rpe));
    }
    if (highHr != null) {
      await session.values.createOriginals(ValueOwner.run(r.id), [
        ComputedValue(
          key: highHeartRateTimeValueKey,
          value: highHr,
          unit: minutesUnit,
          computedAt: end.toUtc(),
          measurementCount: 600,
          sources: const ['strap'],
          method: HighHeartRateTime.methodId,
          methodVersion: 1,
          parameterVersion: 1,
          quality: ValueQuality.good,
        ),
      ]);
    }
    if (assign) await plans.assignRun(unit.id!, r.id, expectedRunId: null);
    clock.advance(
      DateTime(start.year, start.month, start.day, 8).difference(clock.now()),
    );
    return r.id;
  }

  /// Öffnet die Plan-Seite mit einem neuen Controller und gibt ihn zurück.
  Future<PlanController> opened({
    Future<void> Function(Future<void> Function() action)? exclusive,
  }) async {
    await checked();
    final c = controller(exclusive: exclusive);
    await c.open();
    return c;
  }

  /// Die Einheit am Tag [n] trägt den Lauf [runId].
  Future<bool> assigned(int n, int runId) async =>
      (await plans.unitOn(_day(n)))?.runId == runId;

  Future<String?> stage() => session.settings.get(planUnderloadStageKey);

  Future<List<String>> sigs() async => [
    for (final u in await plans.unitsBetween(_day(14), planFarFuture))
      '${_iso(u.day)}|${u.kind.name}|${u.minutes}',
  ];

  Future<int> weekMinutes(int monday) async => (await plans.unitsBetween(
    _day(monday),
    _day(monday + 6),
  )).fold<int>(0, (a, u) => a + u.minutes);
}

/// Erstes Muster (Dienstag, Freitag): Hinweis offen, Seite geladen.
Future<PlanController> _toHint(_Env e) async {
  await e.run(15);
  await e.run(18);
  final c = await e.opened();
  expect(c.state.underloadPrompt, PlanUnderloadPrompt.hint);
  return c;
}

/// Hinweis mit „Passt so“ beantwortet, erneutes Muster aus späteren Läufen
/// (Sonntag, Dienstag): Frage offen.
Future<PlanController> _toQuestion(_Env e) async {
  final c = await _toHint(e);
  expect(await c.answerUnderloadHint(), PlanActionResult.done);
  await e.run(20);
  await e.run(22);
  final q = await e.opened();
  expect(q.state.underloadPrompt, PlanUnderloadPrompt.question);
  return q;
}

void main() {
  group('Ablauf (PAR-236)', () {
    test('erstes Muster → Hinweis ohne Planänderung; Hinweis beantwortet → '
        'nicht wieder; erneutes Muster aus späteren Läufen → Frage', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      final one = await e.opened();
      expect(one.state.underloadPrompt, isNull, reason: '1 Lauf: kein Muster');
      await e.run(18);
      final before = await e.sigs();
      final versions = (await e.plans.history()).length;
      final c = await e.opened();
      expect(c.state.underloadPrompt, PlanUnderloadPrompt.hint);
      expect(await e.sigs(), before);
      expect((await e.plans.history()).length, versions);

      expect(await c.answerUnderloadHint(), PlanActionResult.done);
      expect(c.state.underloadPrompt, isNull);
      expect(await e.stage(), 'hintDone');
      // Dieselben Läufe ergeben kein neues Muster.
      expect((await e.opened()).state.underloadPrompt, isNull);
      // Ein späterer Lauf reicht noch nicht (1 von 1 nach dem Hinweis).
      await e.run(20);
      expect((await e.opened()).state.underloadPrompt, isNull);
      await e.run(22);
      final q = await e.opened();
      expect(q.state.underloadPrompt, PlanUnderloadPrompt.question);
      expect(await e.sigs(), isNot(isEmpty));
    });

    test('Puls und RPE aus dem Speicher: 9 min über 80 % HFmax bzw. RPE 6 '
        'zählen nicht als „hart nach Puls, leicht empfunden“', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15, highHr: 9);
      await e.run(18, rpe: 6);
      await e.run(20);
      final c = await e.opened();
      expect(c.state.underloadPrompt, isNull, reason: 'nur 1 von 3');
      expect(await e.stage(), isNull);
    });

    test('Lauf, der genau zum Zeitpunkt der letzten Stufe endete, zählt '
        'nicht mehr (nur Läufe danach)', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      final ended = (await e.session.runs.finishedBetween(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2027, 1, 1),
      )).single.endedAt!.toUtc();
      final reader = PlanDataReader(session: e.session, clock: e.clock);
      expect(await reader.underloadRuns(ended), isEmpty);
      final before = await reader.underloadRuns(
        ended.subtract(const Duration(microseconds: 1)),
      );
      expect(before.map((r) => r.endedAt), [ended]);
    });

    test('ersetzte Sporteinheit (FR-0222) zählt nicht für das Muster, '
        'nur Läufe', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      await e.run(18, sport: true, highHr: 0);
      final reader = PlanDataReader(session: e.session, clock: e.clock);
      final runs = await reader.underloadRuns(null);
      expect(runs, hasLength(1));
      expect(runs.single.endedAt.day, _day(15).day);
    });

    test('Läufe ohne Puls oder ohne RPE zählen nicht mit', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      await e.run(18);
      await e.run(20, highHr: null);
      await e.run(22, rpe: null);
      // Zählten die beiden letzten mit, wäre es 1 von 3: kein Muster.
      expect(
        (await e.opened()).state.underloadPrompt,
        PlanUnderloadPrompt.hint,
      );
    });

    test(
      'Neustart zeigt Hinweis bzw. Frage nach der Antwort nicht erneut',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final c = await _toHint(e);
        // Unbeantwortet bleibt der Hinweis auch nach einem Neustart.
        expect(
          (await e.opened()).state.underloadPrompt,
          PlanUnderloadPrompt.hint,
        );
        expect(await c.answerUnderloadHint(), PlanActionResult.done);
        expect((await e.opened()).state.underloadPrompt, isNull);
        await e.run(20);
        await e.run(22);
        final q = await e.opened();
        expect(q.state.underloadPrompt, PlanUnderloadPrompt.question);
        expect(await q.answerUnderloadQuestion(false), PlanActionResult.done);
        expect((await e.opened()).state.underloadPrompt, isNull);
        expect(await e.stage(), 'declined');
      },
    );

    test('HFmax geändert → Zählung beginnt neu', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final c = await _toHint(e);
      expect(await c.answerUnderloadHint(), PlanActionResult.done);
      await e.run(20);
      // HFmax im Profil geändert: der Lauf vom Sonntag zählt nicht mehr.
      final saved = await ProfileService(
        e.session.profile,
        e.clock,
        settings: e.session.settings,
      ).save(const ProfileRecord(maxHeartRateBpm: 191));
      expect(saved.saved, isTrue);
      e.clock.advance(const Duration(minutes: 1));
      await e.run(22);
      expect((await e.opened()).state.underloadPrompt, isNull);
      await e.run(25);
      expect(
        (await e.opened()).state.underloadPrompt,
        PlanUnderloadPrompt.question,
      );
    });

    /// Profil nur mit [birthYear], Stufe `hintDone` seit November, zwei
    /// passende Läufe im Dezember; Öffnen am 2. Januar 2027.
    Future<(_Env, PlanController)> yearChange(int birthYear) async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.session.profile.save(ProfileRecord(birthYear: birthYear));
      await e.session.settings.set(
        planUnderloadStageKey,
        PlanUnderloadStage.hintDone.name,
        at: e.clock.now(),
      );
      await e.session.settings.set(
        planUnderloadSinceKey,
        DateTime.utc(2026, 11, 30, 5).toIso8601String(),
        at: e.clock.now(),
      );
      await e.run(29); // Dienstag, 15. Dezember
      await e.run(32); // Freitag, 18. Dezember
      e.clock.advance(DateTime(2027, 1, 2, 9).difference(e.clock.now()));
      return (e, await e.opened());
    }

    test('genäherte HFmax ändert sich zum neuen Jahr (FR-0004) → Zählung '
        'beginnt mit den Läufen im Januar neu', () async {
      // 1987: Näherung 2026 181, 2027 180.
      final (e, c) = await yearChange(1987);
      expect(
        c.state.underloadPrompt,
        isNull,
        reason: 'Dezember-Läufe zählen nach dem Jahreswechsel nicht mehr',
      );
      expect(await e.stage(), 'hintDone');
      await e.run(48); // Sonntag, 3. Januar
      await e.run(50); // Dienstag, 5. Januar
      final q = await e.opened();
      expect(q.state.underloadPrompt, PlanUnderloadPrompt.question);
      // Nichts Neues gespeichert: kein Zeitpunkt der HFmax-Änderung.
      expect(await e.session.settings.get(profileHrMaxChangedAtKey), isNull);
    });

    test('genäherte HFmax bleibt zum neuen Jahr gleich → Dezember-Läufe '
        'zählen weiter', () async {
      // 1992: Näherung 2026 und 2027 jeweils 184.
      final (e, c) = await yearChange(1992);
      expect(c.state.underloadPrompt, PlanUnderloadPrompt.question);
      expect(await e.stage(), 'question');
    });
  });

  group('Zuordnung beim Öffnen vor dem Muster (PAR-231, PAR-236)', () {
    test('Lauf, den erst das Öffnen zuordnet, zählt schon bei diesem Öffnen: '
        'Hinweis', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      final late = await e.run(18, assign: false);
      final c = await e.opened();
      expect(await e.assigned(18, late), isTrue);
      expect(c.state.underloadPrompt, PlanUnderloadPrompt.hint);
      expect(await e.stage(), 'hint');
    });

    test('nach „Passt so“: späterer Lauf, den erst das Öffnen zuordnet, '
        'führt beim selben Öffnen zur Frage', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final c = await _toHint(e);
      expect(await c.answerUnderloadHint(), PlanActionResult.done);
      await e.run(20);
      final late = await e.run(22, assign: false);
      final q = await e.opened();
      expect(await e.assigned(22, late), isTrue);
      expect(q.state.underloadPrompt, PlanUnderloadPrompt.question);
      expect(await e.stage(), 'question');
    });

    test('Zuordnung wirft: Öffnen endet ohne Fehler, nur zugeordnete Läufe '
        'zählen, kein Hinweis aus dem nicht zugeordneten', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      final late = await e.run(18, assign: false);
      e.storage.data.failAssignRun = true;
      final c = await e.opened();
      expect(await e.assigned(18, late), isFalse);
      expect(c.state.underloadPrompt, isNull);
      expect(await e.stage(), isNull);
      // Gegenprobe: Ist die Zuordnung wieder möglich, zählt der Lauf.
      e.storage.data.failAssignRun = false;
      expect(
        (await e.opened()).state.underloadPrompt,
        PlanUnderloadPrompt.hint,
      );
    });

    test('Zuordnung wirft: Muster aus schon zugeordneten Läufen zeigt den '
        'Hinweis trotzdem', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      await e.run(18);
      final late = await e.run(20, assign: false);
      e.storage.data.failAssignRun = true;
      final c = await e.opened();
      expect(await e.assigned(20, late), isFalse);
      expect(c.state.underloadPrompt, PlanUnderloadPrompt.hint);
    });

    test(
      'bei „fix“: Zuordnung beim Öffnen, aber weder Hinweis noch Frage',
      () async {
        final e = await _Env.open(PlanAdaptationMode.fixed);
        await e.run(15);
        final late = await e.run(18, assign: false);
        final c = await e.opened();
        expect(await e.assigned(18, late), isTrue);
        expect(c.state.underloadPrompt, isNull);
        expect(await e.stage(), isNull);
      },
    );

    test('mit Sperre der Wertberechnung: Zuordnung hinter der Sperre, danach '
        'Hinweis beim selben Öffnen', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      final late = await e.run(18, assign: false);
      var locked = 0;
      final c = await e.opened(
        exclusive: (action) async {
          locked++;
          await action();
        },
      );
      expect(locked, 1);
      expect(await e.assigned(18, late), isTrue);
      expect(c.state.underloadPrompt, PlanUnderloadPrompt.hint);
    });

    test('Sperre scheitert: Muster aus schon zugeordneten Läufen zeigt den '
        'Hinweis trotzdem', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      await e.run(18);
      final late = await e.run(20, assign: false);
      final c = await e.opened(
        exclusive: (_) async =>
            throw const StorageException(StorageFailure.failed),
      );
      expect(await e.assigned(20, late), isFalse);
      expect(c.state.underloadPrompt, PlanUnderloadPrompt.hint);
    });
  });

  group('Antwort auf die Frage (PAR-236, PAR-193)', () {
    test('Ja → neue Fassung (feedback, Grund underload), nächste Woche '
        'länger; danach Frage erst nach neuem Muster', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final q = await _toQuestion(e);
      final next = await e.weekMinutes(28);
      expect(await q.answerUnderloadQuestion(true), PlanActionResult.done);
      final last = (await e.plans.history()).last;
      expect(last.trigger, PlanTrigger.feedback);
      expect(last.reason, planReasonUnderload);
      expect(await e.weekMinutes(28), greaterThan(next));
      expect(q.state.underloadPrompt, isNull);
      expect(await e.stage(), 'accepted');
      expect((await e.opened()).state.underloadPrompt, isNull);
    });

    test('Nein → keine Änderung; Frage erst nach neuem Muster aus Läufen '
        'nach dem Nein', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final q = await _toQuestion(e);
      final before = await e.sigs();
      final versions = (await e.plans.history()).length;
      expect(await q.answerUnderloadQuestion(false), PlanActionResult.done);
      expect(await e.sigs(), before);
      expect((await e.plans.history()).length, versions);
      expect((await e.opened()).state.underloadPrompt, isNull);
      await e.run(25);
      expect((await e.opened()).state.underloadPrompt, isNull);
      await e.run(27);
      expect(
        (await e.opened()).state.underloadPrompt,
        PlanUnderloadPrompt.question,
      );
    });

    test(
      'Frage offen, danach „fix“: Ja abgelehnt, keine neue Fassung',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final q = await _toQuestion(e);
        final before = await e.sigs();
        final versions = (await e.plans.history()).length;
        await SettingsPlanAdaptationStore(e.session.settings)
            .set(PlanAdaptationMode.fixed, at: e.clock.now());
        expect(
          await q.answerUnderloadQuestion(true),
          PlanActionResult.rejected,
        );
        expect((await e.plans.history()).length, versions);
        expect(await e.sigs(), before);
        expect(await e.stage(), 'question');
      },
    );

    test(
      'Frage offen, danach Warnsignal: Ja abgelehnt, keine neue Fassung',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final q = await _toQuestion(e);
        expect(await e.controller().reportWarning(), PlanActionResult.done);
        final before = await e.sigs();
        final versions = (await e.plans.history()).length;
        expect(
          await q.answerUnderloadQuestion(true),
          PlanActionResult.rejected,
        );
        expect((await e.plans.history()).length, versions);
        expect(await e.sigs(), before);
        expect(await e.stage(), 'question');
      },
    );

    test(
      'Frage offen, danach wirft die Readiness-Quelle: Ja abgelehnt',
      () async {
        var fail = false;
        final e = await _Env.open(
          PlanAdaptationMode.adaptive,
          readiness: (day) async {
            if (fail) throw StateError('Quelle nicht lesbar');
            return null;
          },
        );
        final q = await _toQuestion(e);
        final before = await e.sigs();
        final versions = (await e.plans.history()).length;
        fail = true;
        expect(
          await q.answerUnderloadQuestion(true),
          PlanActionResult.rejected,
        );
        expect((await e.plans.history()).length, versions);
        expect(await e.sigs(), before);
        expect(q.state.underloadPrompt, isNull);
        expect(await e.stage(), 'question');
      },
    );

    test('ohne offene Frage: abgelehnt, nichts geändert', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final c = await e.opened();
      final before = await e.sigs();
      expect(await c.answerUnderloadQuestion(true), PlanActionResult.rejected);
      expect(await c.answerUnderloadHint(), PlanActionResult.rejected);
      expect(await e.sigs(), before);
      expect(await e.stage(), isNull);
    });
  });

  group('weder Hinweis noch Frage (PAR-236, FR-0216, FR-0203)', () {
    test('bei „fix“', () async {
      final e = await _Env.open(PlanAdaptationMode.fixed);
      await e.run(15);
      await e.run(18);
      final c = await e.opened();
      expect(c.state.underloadPrompt, isNull);
      expect(await e.stage(), isNull);
    });

    test('„fix“ nach offenem Hinweis blendet ihn aus', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await _toHint(e);
      await SettingsPlanAdaptationStore(e.session.settings)
          .set(PlanAdaptationMode.fixed, at: e.clock.now());
      expect((await e.opened()).state.underloadPrompt, isNull);
    });

    test('bei gemeldetem Warnsignal', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      await e.run(18);
      final w = e.controller();
      expect(await w.reportWarning(), PlanActionResult.done);
      final c = await e.opened();
      expect(c.state.warning, isNotNull);
      expect(c.state.underloadPrompt, isNull);
      expect(await e.stage(), isNull);
    });

    test('bei Korrektur nach unten in dieser Woche (PAR-201)', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.run(15);
      await e.run(18);
      // Fassung der Wochenprüfung mit Grund `noIncrease`, Anker diese Woche.
      final last = (await e.plans.history()).last;
      await recalculatePlan(
        plans: e.plans,
        settings: e.session.settings,
        trigger: PlanTrigger.weekly,
        today: calendarDay(e.clock.now()),
        now: e.clock.now(),
        reason: 'noIncrease',
        inputs: last.inputs.copyWith(anchor: _day(14), startWeeklyMinutes: 100),
      );
      expect(
        planCorrectedDownThisWeek(
          await e.plans.history(),
          calendarDay(e.clock.now()),
        ),
        isTrue,
      );
      final c = await e.opened();
      expect(c.state.underloadPrompt, isNull);
      expect(await e.stage(), isNull);
    });

    test('bei Readiness nach PAR-173', () async {
      final e = await _Env.open(
        PlanAdaptationMode.adaptive,
        readiness: (day) async =>
            PlanReadinessDay(day: day, band: ReadinessBand.recoveryAdvised),
      );
      await e.run(15);
      await e.run(18);
      final c = await e.opened();
      expect(c.state.underloadPrompt, isNull);
      expect(await e.stage(), isNull);
    });

    test('wenn die Readiness-Quelle wirft (fail-closed)', () async {
      final e = await _Env.open(
        PlanAdaptationMode.adaptive,
        readiness: (day) async => throw StateError('Quelle nicht lesbar'),
      );
      await e.run(15);
      await e.run(18);
      final c = await e.opened();
      expect(c.state.underloadPrompt, isNull);
      expect(await e.stage(), isNull);
    });

    test('ohne Readiness-Wert für heute nicht gesperrt', () async {
      final e = await _Env.open(
        PlanAdaptationMode.adaptive,
        readiness: (day) async => null,
      );
      await e.run(15);
      await e.run(18);
      expect(
        (await e.opened()).state.underloadPrompt,
        PlanUnderloadPrompt.hint,
      );
    });
  });
}
