import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Daten: Ziel, Plan und Readiness-Reihen sind ausgedacht.
final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));
DateTime _now(int n) => DateTime.utc(2026, 11, 11, 8).add(Duration(days: n));

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.minutes}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

class _Env {
  _Env(this.session) : plans = (session as PlanStorage).plans;
  final StorageSession session;
  final PlanRepository plans;
  SettingsStore get settings => session.settings;
  WarningStore get warning => (session as WarningStorage).warning;

  static Future<_Env> open({
    PlanAdaptationMode mode = PlanAdaptationMode.fixed,
  }) async {
    final e = _Env(
      await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i))),
    );
    await (e.session as GoalStorage).goals.save(_goal(), today: _day(0));
    // Hohe Start-Wochenzeit: jede Woche mit harter Einheit.
    await e.recalc(
      PlanTrigger.create,
      0,
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 180),
    );
    await e.setMode(mode, 0);
    return e;
  }

  Future<void> setMode(PlanAdaptationMode m, int n) =>
      SettingsPlanAdaptationStore(settings).set(m, at: _now(n));

  Future<PlanRecalculation> recalc(
    PlanTrigger t,
    int n, {
    Iterable<PlanReadinessDay> readiness = const [],
    PlanInputs? inputs,
    String? reason,
  }) => recalculatePlan(
    plans: plans,
    settings: settings,
    trigger: t,
    today: _day(n),
    now: _now(n),
    readiness: readiness,
    inputs: inputs,
    reason: reason,
    warning: warning,
  );

  Future<List<PlanUnit>> all() => plans.unitsBetween(_day(-30), _day(400));

  Future<PlanUnit> on(int n) async => (await plans.unitOn(_day(n)))!;
}

/// Erster Tag ab [from] mit einer harten Einheit im gespeicherten Plan.
Future<int> _firstHard(_Env e, {int from = 1}) async {
  for (var n = from; n < from + 28; n++) {
    final u = await e.plans.unitOn(_day(n));
    if (u != null && u.isHard) return n;
  }
  fail('kein harter Tag ab $from');
}

PlanReadinessDay _value(int n, int value) => PlanReadinessDay.number(
  day: _day(n),
  value: value,
  drivers: const [ReadinessFactorId.hrv, ReadinessFactorId.sleep],
);

/// Härte einer Einheit für „steigt nie“: Ruhe < locker/lang < hart.
int _rank(PlanUnit u) => switch (u.kind) {
  PlanUnitKind.rest => 0,
  PlanUnitKind.intervals || PlanUnitKind.tempo || PlanUnitKind.progressive => 2,
  _ => 1,
};

void main() {
  group('Schalter (FR-0216)', () {
    test('Vorgabe ist „fix“; nur `adaptive` ergibt „adaptiv“', () async {
      final e = await _Env.open();
      await e.settings.set('other', 'x', at: _now(0));
      final store = SettingsPlanAdaptationStore(
        (await FakeStorage().open(
          Uint8List.fromList(List.generate(32, (i) => i)),
        )).settings,
      );
      expect(await store.read(), PlanAdaptationMode.fixed);
      expect(PlanAdaptationMode.fromStorage(null), PlanAdaptationMode.fixed);
      expect(PlanAdaptationMode.fromStorage(''), PlanAdaptationMode.fixed);
      expect(
        PlanAdaptationMode.fromStorage('Adaptive'),
        PlanAdaptationMode.fixed,
      );
      expect(
        PlanAdaptationMode.fromStorage('adaptive'),
        PlanAdaptationMode.adaptive,
      );
    });

    test('gespeichert in `settings` unter plan.adaptation und im Archiv '
        '(kein technischer Merker)', () async {
      final e = await _Env.open();
      final store = SettingsPlanAdaptationStore(e.settings);
      await store.set(PlanAdaptationMode.adaptive, at: _now(0));
      expect(await e.settings.get(planAdaptationKey), 'adaptive');
      expect(await store.read(), PlanAdaptationMode.adaptive);
      await store.set(PlanAdaptationMode.fixed, at: _now(1));
      expect(await e.settings.get('plan.adaptation'), 'fixed');
      expect(archiveExcludedSettingKeys, isNot(contains(planAdaptationKey)));
    });
    test(
      '„Alles löschen“ entfernt den Schalter: danach wieder „fix“',
      () async {
        final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
        expect(await e.settings.get(planAdaptationKey), 'adaptive');
        await e.session.deleteAll();
        expect(await e.settings.get(planAdaptationKey), isNull);
        expect(
          await SettingsPlanAdaptationStore(e.settings).read(),
          PlanAdaptationMode.fixed,
        );
      },
    );
  });

  group('Lockerung nach PAR-173', () {
    test('adaptiv, Wert 49 am Tag der harten Einheit: sie wird locker, '
        'gleiche Dauer, Termin bleibt; Begründung im summary', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      final before = await e.on(h);
      final others = [
        for (final u in await e.all())
          if (planDay(u.day) != _day(h)) _sig(u),
      ];
      final r = await e.recalc(
        PlanTrigger.feedback,
        h,
        readiness: [_value(h, 49)],
        reason: planReasonReadiness,
      );
      expect(r.wasWritten, isTrue);
      final after = await e.on(h);
      expect(after.kind, PlanUnitKind.easy);
      expect(after.minutes, before.minutes);
      expect(after.pinned, before.pinned);
      expect(after.fixed, PlanUnitFixed.none);
      expect(after.segments, isNotEmpty);
      expect(
        after.segments.every(
          (s) =>
              s.kind != PlanSegmentKind.interval &&
              s.kind != PlanSegmentKind.tempo &&
              s.kind != PlanSegmentKind.endBlock,
        ),
        isTrue,
      );
      // Nur die Einheit dieses Tags ändert sich.
      expect([
        for (final u in await e.all())
          if (planDay(u.day) != _day(h)) _sig(u),
      ], others);
      final v = (await e.plans.history()).last;
      expect(v.trigger, PlanTrigger.feedback);
      expect(v.reason, planReasonReadiness);
      final eased = recoveryEasedFromSummary(v.summary);
      expect(eased, hasLength(1));
      expect(eased.single.day, _day(h));
      expect(eased.single.unit.kind, before.kind);
      expect(eased.single.band, ReadinessBand.elevatedLoad);
      expect(eased.single.drivers, [
        ReadinessFactorId.hrv,
        ReadinessFactorId.sleep,
      ]);
      // Gesundheitsdaten nur als Band und Faktor, kein Messwert.
      expect(v.summary.toString(), isNot(contains('49')));
    });

    test('Bandgrenze: 50 (normal belastbar) ändert nichts', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      final r = await e.recalc(
        PlanTrigger.feedback,
        h,
        readiness: [_value(h, 50)],
      );
      expect(r.wasWritten, isFalse);
      expect((await e.on(h)).isHard, isTrue);
    });

    for (final v in [0, 24, 25]) {
      test(
        'Band „Erholung empfohlen“/„Erhöhte Belastung“ ($v) lockert',
        () async {
          final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
          final h = await _firstHard(e);
          await e.recalc(PlanTrigger.feedback, h, readiness: [_value(h, v)]);
          expect((await e.on(h)).kind, PlanUnitKind.easy);
        },
      );
    }

    test('ein hoher Wert erhöht nichts', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      final before = (await e.all()).map(_sig).toList();
      final r = await e.recalc(
        PlanTrigger.feedback,
        h,
        readiness: [for (var n = h; n < h + 14; n++) _value(n, 100)],
      );
      expect(r.wasWritten, isFalse);
      expect((await e.all()).map(_sig).toList(), before);
    });

    test('nur der Wert des Tags der Einheit zählt: ein niedriger Wert am '
        'Vortag wird nicht übertragen', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e, from: 2);
      final r = await e.recalc(
        PlanTrigger.feedback,
        h - 1,
        readiness: [_value(h - 1, 10), _value(h + 1, 10)],
      );
      expect(r.wasWritten, isFalse);
      expect((await e.on(h)).isHard, isTrue);
    });

    test('eingeschränkte Einschätzung ohne Zahl wirkt nicht', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      final r = await e.recalc(
        PlanTrigger.feedback,
        h,
        readiness: [PlanReadinessDay(day: _day(h), band: null)],
      );
      expect(r.wasWritten, isFalse);
      expect((await e.on(h)).isHard, isTrue);
    });

    test('„fix“: ein niedriger Wert ändert nichts', () async {
      final e = await _Env.open();
      final h = await _firstHard(e);
      final r = await e.recalc(
        PlanTrigger.feedback,
        h,
        readiness: [_value(h, 5)],
      );
      expect(r.wasWritten, isFalse);
      expect((await e.on(h)).isHard, isTrue);
    });

    test('Warnsignal hat Vorrang: Ruhetag, nicht locker; nach dem Aufheben '
        'am selben Tag gilt die Lockerung', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      await e.warning.set(
        WarningSignal(reportedOn: _day(h), source: WarningSource.manual),
      );
      await e.recalc(PlanTrigger.feedback, h, readiness: [_value(h, 30)]);
      expect((await e.on(h)).kind, PlanUnitKind.rest);
      await e.warning.lift();
      await e.recalc(PlanTrigger.feedback, h);
      expect((await e.on(h)).kind, PlanUnitKind.easy);
    });

    test('vom Nutzer festgelegte Art bleibt (ADR-0010)', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      final u = await e.on(h);
      final other = u.kind == PlanUnitKind.tempo
          ? PlanUnitKind.intervals
          : PlanUnitKind.tempo;
      final goal = (await e.plans.currentGoal())!;
      final check = checkPlanReplace(
        units: await e.all(),
        unit: u,
        kind: other,
        goal: goal,
        inputs: (await e.plans.history()).last.inputs,
        today: _day(h),
      );
      await e.plans.replaceUnit(u.id!, check.unit!, today: _day(h));
      await e.recalc(PlanTrigger.feedback, h, readiness: [_value(h, 10)]);
      final after = await e.on(h);
      expect(after.kind, other);
      expect(after.fixed, PlanUnitFixed.kind);
    });

    test('die Lockerung bleibt für den Tag, auch bei besserem Wert und ohne '
        'Wert; am Folgetag wird die harte Einheit nicht übertragen', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      await e.recalc(PlanTrigger.feedback, h, readiness: [_value(h, 30)]);
      expect((await e.on(h)).kind, PlanUnitKind.easy);
      // Späterer, besserer Wert am selben Tag.
      final r1 = await e.recalc(
        PlanTrigger.feedback,
        h,
        readiness: [_value(h, 90)],
      );
      expect(r1.wasWritten, isFalse);
      expect((await e.on(h)).kind, PlanUnitKind.easy);
      // Neuberechnung aus anderem Grund am selben Tag.
      await e.recalc(PlanTrigger.manual, h);
      expect((await e.on(h)).kind, PlanUnitKind.easy);
      // Folgetage der Woche: keine harte Einheit mehr.
      final monday = _day(h).subtract(Duration(days: _day(h).weekday - 1));
      final end = monday.add(const Duration(days: 7));
      for (var n = h + 1; _day(n).isBefore(end); n++) {
        await e.recalc(PlanTrigger.weekly, n);
        await e.recalc(PlanTrigger.manual, n);
      }
      final week = await e.plans.unitsBetween(monday, end);
      expect(week.where((u) => u.isHard), isEmpty);
    });

    test('Wechsel auf „fix“ am selben Tag: die harte Einheit kehrt zurück; '
        'Vortage bleiben (nicht rückwirkend)', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final h = await _firstHard(e);
      final hard = await e.on(h);
      await e.recalc(PlanTrigger.feedback, h, readiness: [_value(h, 30)]);
      final past = [
        for (final u in await e.all())
          if (u.day.isBefore(_day(h))) _sig(u),
      ];
      await e.setMode(PlanAdaptationMode.fixed, h);
      final r = await e.recalc(
        PlanTrigger.feedback,
        h,
        reason: planReasonAdaptationFixed,
      );
      expect(r.wasWritten, isTrue);
      expect(_sig(await e.on(h)), _sig(hard));
      expect([
        for (final u in await e.all())
          if (u.day.isBefore(_day(h))) _sig(u),
      ], past);
      expect(
        recoveryEasedFromSummary((await e.plans.history()).last.summary),
        isEmpty,
      );
    });
  });

  group('generatePlan(easedHardDays:)', () {
    TrainingGoal goal(Set<int> runDays) => TrainingGoal(
      type: GoalType.distance,
      distance: GoalDistance.tenKilometers,
      targetDate: DateTime(2027, 6, 1),
      runDays: runDays,
      maxSessionSeconds: 7200,
      weeklyCapSeconds: 300 * 60.0,
      createdAt: DateTime.utc(2026, 11, 1),
      hardSessionEnabled: true,
      canRun30: ContinuousRun30.yes,
    );

    (GeneratedPlan, DateTime) afterEase({required bool counted}) {
      final g0 = goal(const {1, 2, 4, 6});
      final inputs = PlanInputs.forNewGoal(
        g0,
        _day(0),
      ).copyWith(startWeeklyMinutes: 240);
      final p0 = generatePlan(g0, inputs, const [], _day(0));
      // Erste harte Einheit am Dienstag.
      final hard = p0.units.firstWhere((u) => u.isHard && u.day.weekday == 2);
      final eased = PlanUnit(
        day: hard.day,
        kind: PlanUnitKind.easy,
        phase: hard.phase,
        weekIndex: hard.weekIndex,
        minutes: hard.minutes,
        segments: const [],
      );
      final frozen = [
        for (final u in p0.units)
          if (u.day.isBefore(hard.day)) u,
        eased,
      ];
      final next = hard.day.add(const Duration(days: 1));
      // Zieländerung am Folgetag: Lauftage Do, Sa, So, so dass die harte
      // Einheit der Woche auf einen späteren Tag fiele.
      final g1 = goal(const {4, 6, 7});
      final p1 = generatePlan(
        g1,
        inputs.copyWith(today: next),
        frozen,
        next,
        easedHardDays: counted ? {planDay(hard.day)} : const {},
      );
      return (p1, hard.day);
    }

    List<PlanUnit> weekOf(GeneratedPlan p, DateTime day) {
      final monday = day.subtract(Duration(days: day.weekday - 1));
      final end = monday.add(const Duration(days: 7));
      return [
        for (final u in p.allUnits)
          if (!u.day.isBefore(monday) && u.day.isBefore(end)) u,
      ];
    }

    test('gelockerte harte Einheit zählt eingefroren als harte Einheit der '
        'Woche: keine neue harte Einheit später in der Woche', () {
      final (eased, day) = afterEase(counted: true);
      final week = weekOf(eased, day);
      expect(week.any((u) => u.day.isAfter(day)), isTrue);
      expect(week.where((u) => u.isHard), isEmpty);
      // Gegenprobe: ohne die Zählung entstünde eine neue harte Einheit.
      final (plain, _) = afterEase(counted: false);
      expect(weekOf(plain, day).where((u) => u.isHard), isNotEmpty);
    });
  });

  group('Eigenschaften über Readiness-Reihen', () {
    // Simulation über 8 Wochen: täglich eine Neuberechnung mit dem Wert des
    // Tags (zufällig, darunter Tage ohne Zahl), dazu ein Warnsignal und eine
    // Anpassung aus Phase 2 (keine harte Einheit bis …).
    Future<void> simulate(
      _Env e,
      Random rnd, {
      required bool withReadiness,
      required List<int?> values,
    }) async {
      for (var n = 1; n <= 56; n++) {
        if (n == 20) {
          await e.warning.set(
            WarningSignal(reportedOn: _day(n), source: WarningSource.manual),
          );
        }
        if (n == 24) await e.warning.lift();
        final v = values[n];
        final readiness = withReadiness
            ? [
                v == null
                    ? PlanReadinessDay(day: _day(n), band: null)
                    : _value(n, v),
              ]
            : const <PlanReadinessDay>[];
        PlanInputs? inputs;
        if (n == 35) {
          inputs = (await e.plans.history()).last.inputs.copyWith(
            today: _day(n),
            noHardUntil: _day(n + 6),
          );
        }
        await e.recalc(
          n % 7 == 0 ? PlanTrigger.weekly : PlanTrigger.feedback,
          n,
          readiness: readiness,
          inputs: inputs,
        );
      }
    }

    List<int?> series(Random rnd) => [
      for (var n = 0; n <= 56; n++)
        rnd.nextInt(5) == 0 ? null : rnd.nextInt(101),
    ];

    for (final seed in [1, 2, 3, 4, 5]) {
      test('„fix“: Plan gleich dem Plan ohne Gesundheitsdaten (Reihe $seed); '
          'Warnsignal und Phase-2-Anpassung wirken', () async {
        final values = series(Random(seed));
        final a = await _Env.open();
        final b = await _Env.open();
        await simulate(a, Random(seed), withReadiness: true, values: values);
        await simulate(b, Random(seed), withReadiness: false, values: values);
        expect(
          (await a.all()).map(_sig).toList(),
          (await b.all()).map(_sig).toList(),
        );
        // Warnsignal (Tag 20–23): nur Ruhetage.
        for (var n = 20; n < 24; n++) {
          final u = await a.plans.unitOn(_day(n));
          if (u != null) expect(u.kind, PlanUnitKind.rest);
        }
        // Phase 2: keine harte Einheit bis Tag 41.
        for (var n = 35; n <= 41; n++) {
          final u = await a.plans.unitOn(_day(n));
          if (u != null) expect(u.isHard, isFalse);
        }
      });

      test('„adaptiv“: keine Einheit steigt, nur Einheiten am Tag mit '
          'niedrigem Wert ändern sich (Reihe $seed)', () async {
        final values = series(Random(seed));
        final a = await _Env.open(mode: PlanAdaptationMode.adaptive);
        final b = await _Env.open(mode: PlanAdaptationMode.adaptive);
        await simulate(a, Random(seed), withReadiness: true, values: values);
        await simulate(b, Random(seed), withReadiness: false, values: values);
        final ua = {for (final u in await a.all()) planDay(u.day): u};
        final ub = {for (final u in await b.all()) planDay(u.day): u};
        expect(ua.keys.toSet(), ub.keys.toSet());
        var changed = 0;
        for (final d in ub.keys) {
          final x = ua[d]!, y = ub[d]!;
          if (_sig(x) == _sig(y)) continue;
          changed++;
          final n = d.difference(_d0).inDays;
          expect(_rank(x), lessThan(_rank(y)), reason: 'Tag $n');
          expect(x.kind, PlanUnitKind.easy, reason: 'Tag $n');
          expect(x.minutes, y.minutes, reason: 'Tag $n');
          final v = n >= 0 && n < values.length ? values[n] : null;
          expect(v, isNotNull, reason: 'Tag $n ohne Zahl');
          expect(v!, lessThan(50), reason: 'Tag $n');
        }
        expect(changed, greaterThan(0), reason: 'die Reihe prüft nichts');
      });
    }
  });

  group('Empfehlung bei „fix“ (recoveryRecommendsEasy)', () {
    PlanUnit unit({
      int n = 0,
      PlanUnitKind kind = PlanUnitKind.intervals,
      int? runId,
      PlanUnitFixed fixed = PlanUnitFixed.none,
    }) => PlanUnit(
      day: _day(n),
      kind: kind,
      phase: PlanPhase.build,
      weekIndex: 1,
      minutes: 40,
      segments: const [],
      runId: runId,
      fixed: fixed,
    );

    bool rec({
      PlanAdaptationMode mode = PlanAdaptationMode.fixed,
      PlanReadinessDay? readiness,
      PlanUnit? u,
      bool noReadiness = false,
      bool noUnit = false,
    }) => recoveryRecommendsEasy(
      mode: mode,
      readiness: noReadiness ? null : readiness ?? _value(0, 30),
      unit: noUnit ? null : u ?? unit(),
      today: _now(0),
    );

    test('„fix“, niedriger Wert heute, harte Einheit heute: Empfehlung', () {
      expect(rec(), isTrue);
      expect(rec(readiness: _value(0, 10)), isTrue);
      expect(rec(u: unit(kind: PlanUnitKind.tempo)), isTrue);
    });

    test('keine Empfehlung bei „adaptiv“ (dort lockert der Plan)', () {
      expect(rec(mode: PlanAdaptationMode.adaptive), isFalse);
    });

    test('keine Empfehlung ohne Wert, ohne Zahl oder mit hohem Wert', () {
      expect(rec(noReadiness: true), isFalse);
      expect(
        rec(readiness: PlanReadinessDay(day: _day(0), band: null)),
        isFalse,
      );
      expect(rec(readiness: _value(0, 60)), isFalse);
      expect(rec(readiness: _value(0, 95)), isFalse);
    });

    test('keine Empfehlung für Wert oder Einheit eines anderen Tags', () {
      expect(rec(readiness: _value(-1, 30)), isFalse);
      expect(rec(u: unit(n: 1)), isFalse);
      expect(rec(readiness: _value(1, 30), u: unit(n: 1)), isFalse);
    });

    test('keine Empfehlung ohne Einheit, für lockere, gelaufene oder vom '
        'Nutzer festgelegte Einheit', () {
      expect(rec(noUnit: true), isFalse);
      expect(rec(u: unit(kind: PlanUnitKind.easy)), isFalse);
      expect(rec(u: unit(kind: PlanUnitKind.rest)), isFalse);
      expect(rec(u: unit(runId: 7)), isFalse);
      expect(rec(u: unit(fixed: PlanUnitFixed.kind)), isFalse);
      expect(rec(u: unit(fixed: PlanUnitFixed.easyForHard)), isFalse);
    });
  });
}
