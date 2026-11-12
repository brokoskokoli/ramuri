import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));
DateTime _now(int n) => DateTime.utc(2026, 11, 11, 8).add(Duration(days: n));

TrainingGoal _goal({int capMin = 240}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: capMin * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.phase.name}|${u.weekIndex}|'
    '${u.minutes}|${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

class _Env {
  _Env(this.session)
    : plans = (session as PlanStorage).plans,
      goals = (session as GoalStorage).goals,
      warning = (session as WarningStorage).warning {
    service = WarningService(
      plans: plans,
      settings: session.settings,
      warning: warning,
    );
  }
  final StorageSession session;
  final PlanRepository plans;
  final GoalStore goals;
  final WarningStore warning;
  late final WarningService service;

  static Future<_Env> open() async => _Env(
    await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i))),
  );

  Future<List<PlanUnit>> all() => plans.unitsBetween(_day(-400), _day(800));

  Future<List<String>> sigs() async => [for (final u in await all()) _sig(u)];

  Future<PlanRecalculation> recalc(PlanTrigger t, int n) => recalculatePlan(
    plans: plans,
    settings: session.settings,
    trigger: t,
    today: _day(n),
    now: _now(n),
    warning: warning,
  );

  /// Plan mit Festlegungen: tempo statt locker (fixed=kind), hart -> locker
  /// (easyForHard), ein Ruhetag des Nutzers (fixed=day).
  static Future<_Env> withFixed() async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.recalc(PlanTrigger.create, 0);
    final goal = (await e.plans.currentGoal())!;
    var inputs = (await e.plans.history()).last.inputs;
    var units = await e.all();
    Future<void> replace(PlanUnit u, PlanUnitKind k) async {
      final c = checkPlanReplace(
        units: units,
        unit: u,
        kind: k,
        goal: goal,
        inputs: inputs,
        today: _day(0),
      );
      expect(c.blocked, isNull);
      await e.plans.replaceUnit(u.id!, c.unit!, today: _day(0));
      units = await e.all();
    }

    await replace(
      units.firstWhere(
        (u) => u.kind == PlanUnitKind.easy && u.day.isAfter(_day(14)),
      ),
      PlanUnitKind.tempo,
    );
    await replace(
      units.firstWhere((u) => u.isHard && u.day.isAfter(_day(30))),
      PlanUnitKind.easy,
    );
    final restOn = units.firstWhere((u) => u.day.isAfter(_day(45)));
    await e.plans.setRestDay(
      planRestDayUnit(
        day: restOn.day,
        goal: goal,
        inputs: inputs,
        today: _day(0),
      ),
      today: _day(0),
      expectedUnitId: restOn.id,
    );
    inputs = (await e.plans.history()).last.inputs;
    return e;
  }
}

Future<PlanUnit> _single(_Env e, bool Function(PlanUnit) f) async =>
    (await e.all()).firstWhere(f);

/// Plan-Speicher, dessen Schreiben der Fassung scheitert (Platte voll u. Ä.).
class _FailingWrite implements PlanRepository {
  _FailingWrite(this.inner);
  final PlanRepository inner;

  @override
  Future<TrainingGoal?> currentGoal() => inner.currentGoal();
  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) =>
      inner.unitsBetween(from, to);
  @override
  Future<PlanUnit?> unitOn(DateTime day) => inner.unitOn(day);
  @override
  Future<List<PlanVersionRecord>> history() => inner.history();
  @override
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft draft) =>
      throw const StorageException(StorageFailure.rejected);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Warnsignal: Vorrang und Wiederherstellung (FR-0203, K58)', () {
    test('Ruhetage ab heute auch bei fixed=kind/easyForHard; nach dem '
        'Aufheben gleicher Plan wie vorher', () async {
      final e = await _Env.withFixed();
      final before = await e.sigs();
      final fixedKinds = {
        for (final u in await e.all())
          if (u.fixed != PlanUnitFixed.none) u.fixed,
      };
      expect(
        fixedKinds,
        containsAll({
          PlanUnitFixed.kind,
          PlanUnitFixed.easyForHard,
          PlanUnitFixed.day,
        }),
      );
      final base = (await e.plans.history()).length;

      final r = await e.service.report(
        source: WarningSource.manual,
        today: _day(3),
        now: _now(3),
      );
      expect(r.version!.trigger, PlanTrigger.feedback);
      expect(r.version!.reason, 'warning');
      final during = await e.all();
      for (final u in during.where((u) => !u.day.isBefore(_day(3)))) {
        expect(u.kind, PlanUnitKind.rest, reason: '${u.day}');
      }
      // Die Überlagerung ist in gültiger Form gespeichert (keine Festlegung,
      // nicht bestätigt; die Festlegung steckt in der Fassung), außer dem
      // Ruhetag des Nutzers.
      final byDay = {for (final u in during) u.day: u};
      for (final u in await _beforeUnits(before)) {
        if (!u.day.isBefore(_day(3)) && u.fixed != PlanUnitFixed.day) {
          expect(byDay[u.day]!.fixed, PlanUnitFixed.none, reason: '${u.day}');
          expect(byDay[u.day]!.pinned, isFalse, reason: '${u.day}');
        }
      }

      // Doppelt melden: idempotent, keine zweite Fassung.
      final again = await e.service.report(
        source: WarningSource.runFeedback,
        today: _day(3),
        now: _now(3),
        runId: 5,
      );
      expect(again.wasWritten, isFalse);
      expect((await e.plans.history()).length, base + 1);
      expect((await e.warning.read())!.source, WarningSource.manual);

      final lifted = await e.service.lift(today: _day(3), now: _now(3));
      expect(lifted.version!.reason, 'warningLifted');
      expect(lifted.version!.trigger, PlanTrigger.feedback);
      expect(await e.warning.read(), isNull);
      expect(await e.sigs(), before);
      // Aufheben ohne Warnsignal: nichts Neues.
      final n = (await e.plans.history()).length;
      expect(
        (await e.service.lift(today: _day(3), now: _now(3))).wasWritten,
        isFalse,
      );
      expect((await e.plans.history()).length, n);
    });

    test('Ruhetag, den der Nutzer unter Warnsignal festlegt, übersteht das '
        'Aufheben (ADR-0010)', () async {
      final e = await _Env.withFixed();
      final before = await e.all();
      await e.service.report(
        source: WarningSource.manual,
        today: _day(3),
        now: _now(3),
      );
      final goal = (await e.plans.currentGoal())!;
      final inputs = (await e.plans.history()).last.inputs;
      final target = (await e.all()).firstWhere(
        (u) =>
            u.day.isAfter(_day(10)) &&
            u.kind == PlanUnitKind.rest &&
            !u.pinned &&
            before.any(
              (b) => b.day == u.day && b.kind != PlanUnitKind.rest && !b.pinned,
            ),
      );
      await e.plans.setRestDay(
        planRestDayUnit(
          day: target.day,
          goal: goal,
          inputs: inputs,
          today: _day(3),
        ),
        today: _day(3),
        expectedUnitId: target.id,
      );
      await e.service.lift(today: _day(3), now: _now(3));
      final after = {for (final u in await e.all()) u.day: u};
      final kept = after[target.day]!;
      expect(kept.kind, PlanUnitKind.rest);
      expect(kept.pinned, isTrue);
      expect(kept.fixed, PlanUnitFixed.day);
      // Die übrigen gehaltenen Tage kehren zurück.
      final other = before.firstWhere(
        (b) =>
            b.day.isAfter(_day(3)) &&
            b.day != target.day &&
            b.kind != PlanUnitKind.rest,
      );
      expect(after[other.day]!.kind, other.kind);
    });

    test('Aufheben mit gemessenen Eingaben: die nächste wöchentliche Prüfung '
        'erzeugt keine zusätzliche Fassung (Befund 4)', () async {
      // Gemessene Werte von heute (langsames lockeres Tempo, 3 Läufe).
      PlanInputs measuredFor(PlanInputs stored, DateTime today) => PlanInputs(
        anchor: stored.anchor,
        startWeeklyMinutes: stored.startWeeklyMinutes,
        today: today,
        easyPaceSecondsPerKm: 600,
        easyRunCount: 3,
      );
      Future<(bool, int)> run({required bool measured}) async {
        final e = await _Env.withFixed();
        PlanInputs? lastMeasured;
        final service = WarningService(
          plans: e.plans,
          settings: e.session.settings,
          warning: e.warning,
          measuredInputs: measured
              ? (goal, today) async => lastMeasured = measuredFor(
                  (await e.plans.history()).last.inputs,
                  today,
                )
              : null,
        );
        await service.report(
          source: WarningSource.manual,
          today: _day(3),
          now: _now(3),
        );
        await service.lift(today: _day(3), now: _now(3));
        final n = (await e.plans.history()).length;
        final stored = (await e.plans.history()).last.inputs;
        final weekly = await recalculatePlan(
          plans: e.plans,
          settings: e.session.settings,
          trigger: PlanTrigger.weekly,
          today: _day(4),
          now: _now(4),
          inputs: refreshMeasuredInputs(
            stored,
            lastMeasured ?? measuredFor(stored, _day(4)),
          ),
          warning: e.warning,
        );
        return (weekly.wasWritten, n);
      }

      // Ohne gemessene Eingaben ist der Plan veraltet: Kontrolle, dass der
      // Test die Wirkung sieht.
      expect((await run(measured: false)).$1, isTrue);
      expect((await run(measured: true)).$1, isFalse);
    });

    test('Neuberechnung unter Warnsignal (manual, weekly, run, '
        'goalChange): bleibt Ruhe, nach Aufheben wie ohne Warnsignal', () async {
      final e = await _Env.withFixed();
      final ref = await _Env.withFixed();
      await e.service.report(
        source: WarningSource.manual,
        today: _day(1),
        now: _now(1),
      );
      var k = 1;
      for (final (t, cap) in [
        (PlanTrigger.manual, 200),
        (PlanTrigger.weekly, 200),
        (PlanTrigger.run, 200),
        (PlanTrigger.goalChange, 260),
      ]) {
        k += 1;
        final g = _goal(capMin: cap);
        await e.goals.save(g, today: g.createdAt);
        await ref.goals.save(g, today: g.createdAt);
        await e.recalc(t, k);
        await ref.warning.lift();
        await ref.recalc(t, k);
        for (final u in (await e.all()).where(
          (u) => !u.day.isBefore(_day(k)),
        )) {
          expect(u.kind, PlanUnitKind.rest, reason: '${t.name} ${u.day}');
        }
      }
      await e.service.lift(today: _day(k), now: _now(k));
      // Tage, die unter dem Warnsignal vergingen, waren Ruhetage (eingefroren).
      List<String> from(List<PlanUnit> us) => [
        for (final u in us)
          if (!u.day.isBefore(_day(k))) _sig(u),
      ];
      expect(from(await e.all()), from(await ref.all()));
    });

    test('absolvierte und zugeordnete Einheiten bleiben unverändert', () async {
      final e = await _Env.withFixed();
      final first = await _single(e, (u) => !u.day.isBefore(_day(0)));
      final run = await e.session.runs.create(startedAt: _now(0));
      await e.plans.assignRun(first.id!, run.id);
      final past = await _single(e, (u) => u.runId == run.id);
      await e.service.report(
        source: WarningSource.manual,
        today: _day(0),
        now: _now(0),
      );
      final after = await e.all();
      expect(_sig(after.firstWhere((u) => u.runId == run.id)), _sig(past));
      expect(
        after
            .where((u) => u.runId == null && !u.day.isBefore(_day(0)))
            .every((u) => u.kind == PlanUnitKind.rest),
        isTrue,
      );
    });

    test('Warnsignal übersteht das Löschen des Laufs (deleteRun)', () async {
      final e = await _Env.withFixed();
      final run = await e.session.runs.create(startedAt: _now(0));
      await e.service.report(
        source: WarningSource.runFeedback,
        today: _day(0),
        now: _now(0),
        runId: run.id,
      );
      await e.session.deleteRun(run.id);
      final w = await e.warning.read();
      expect(w!.source, WarningSource.runFeedback);
      expect(w.runId, run.id);
      expect(
        (await e.all())
            .where((u) => !u.day.isBefore(_day(0)))
            .every((u) => u.kind == PlanUnitKind.rest),
        isTrue,
      );
    });

    test('Scheitert das Schreiben beim Aufheben, stellt die nächste '
        'Neuberechnung die Festlegungen her', () async {
      final e = await _Env.withFixed();
      final before = await e.sigs();
      await e.service.report(
        source: WarningSource.manual,
        today: _day(0),
        now: _now(0),
      );
      await e.warning.lift(); // Dienst nach dem Aufheben abgebrochen
      await e.recalc(PlanTrigger.weekly, 0);
      expect(await e.sigs(), before);
    });
  });

  group('Melden scheitert beim Schreiben des Plans (E2E 4)', () {
    Future<(_Env, WarningService)> failing() async {
      final e = await _Env.withFixed();
      return (
        e,
        WarningService(
          plans: _FailingWrite(e.plans),
          settings: e.session.settings,
          warning: e.warning,
        ),
      );
    }

    test('die eben gesetzte Zeile wird zurückgenommen: Warnsignal und Plan '
        'gelten beide oder keines', () async {
      final (e, service) = await failing();
      final before = await e.sigs();
      await expectLater(
        service.report(
          source: WarningSource.manual,
          today: _day(3),
          now: _now(3),
        ),
        throwsA(isA<StorageException>()),
      );
      expect(await e.warning.read(), isNull);
      expect(await e.sigs(), before);
    });

    test('ein früheres Warnsignal bleibt stehen', () async {
      final (e, service) = await failing();
      await e.warning.set(
        WarningSignal(
          reportedOn: _day(1),
          source: WarningSource.runFeedback,
          runId: 4,
        ),
      );
      await expectLater(
        service.report(
          source: WarningSource.manual,
          today: _day(3),
          now: _now(3),
        ),
        throwsA(isA<StorageException>()),
      );
      expect((await e.warning.read())!.reportedOn, _day(1));
    });
  });

  test('applyWarningRest: Einheit mit Lauf und vergangene bleiben', () {
    PlanUnit u(int n, {int? runId}) => PlanUnit(
      day: _day(n),
      kind: PlanUnitKind.easy,
      phase: PlanPhase.entry,
      weekIndex: 0,
      minutes: 30,
      segments: const [],
      runId: runId,
      fixed: PlanUnitFixed.kind,
      pinned: true,
    );
    final out = applyWarningRest([u(0), u(1, runId: 3), u(2)], _day(1));
    expect(out.map((x) => x.kind), [
      PlanUnitKind.easy,
      PlanUnitKind.easy,
      PlanUnitKind.rest,
    ]);
    expect(out[2].fixed, PlanUnitFixed.none);
    expect(out[2].pinned, isFalse);
  });

  group('Warnsignal und Brücke vor dem Anker (NB7 1)', () {
    test('zu schwer Do, Warnsignal Do, Aufheben Fr: Sa hat wieder Dauer und '
        'Abschnitte', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      await e.recalc(PlanTrigger.create, -2);
      final goal = (await e.plans.currentGoal())!;
      final last = (await e.plans.history()).last;
      final r = applyPlanFeedback(
        goal: goal,
        inputs: last.inputs.copyWith(today: _day(15)),
        answer: PlanFeedback.tooHard,
        today: _day(15),
      );
      await recalculatePlan(
        plans: e.plans,
        settings: e.session.settings,
        trigger: PlanTrigger.feedback,
        today: _day(15),
        now: _now(15),
        inputs: r.inputs,
        warning: e.warning,
      );
      final anchor = r.inputs!.anchor;
      Future<PlanUnit> bridgeDay() async => (await e.plans.unitsBetween(
        _day(15),
        anchor,
      )).lastWhere((u) => u.day.isAfter(_day(15)));
      final planned = await bridgeDay();
      expect(planned.minutes, greaterThan(0));
      expect(planned.segments, isNotEmpty);

      await e.service.report(
        source: WarningSource.manual,
        today: _day(15),
        now: _now(15).add(const Duration(hours: 1)),
      );
      expect((await bridgeDay()).kind, PlanUnitKind.rest);
      await e.service.lift(today: _day(16), now: _now(16));

      final back = await bridgeDay();
      expect(back.day, planned.day);
      expect(back.kind, planned.kind);
      expect(back.minutes, planned.minutes);
      expect(
        [
          for (final s in back.segments)
            '${s.kind.name}:${s.minutes}:${s.seconds}',
        ],
        [
          for (final s in planned.segments)
            '${s.kind.name}:${s.minutes}:${s.seconds}',
        ],
      );
    });
  });

  test('Brücke aus altem Fassungseintrag ohne Dauer und Abschnitte wird '
      'gefüllt (NB8 3)', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.recalc(PlanTrigger.create, -2);
    final goal = (await e.plans.currentGoal())!;
    final last = (await e.plans.history()).last;
    final r = applyPlanFeedback(
      goal: goal,
      inputs: last.inputs.copyWith(today: _day(15)),
      answer: PlanFeedback.tooHard,
      today: _day(15),
    );
    await recalculatePlan(
      plans: e.plans,
      settings: e.session.settings,
      trigger: PlanTrigger.feedback,
      today: _day(15),
      now: _now(15),
      inputs: r.inputs,
      warning: e.warning,
    );
    final anchor = r.inputs!.anchor;
    Future<PlanUnit> bridgeDay() async => (await e.plans.unitsBetween(
      _day(15),
      anchor,
    )).lastWhere((u) => u.day.isAfter(_day(15)));
    expect((await bridgeDay()).minutes, greaterThan(0));
    await e.service.report(
      source: WarningSource.manual,
      today: _day(15),
      now: _now(15).add(const Duration(hours: 1)),
    );
    // Zustand einer alten Fassung: Einträge ohne Dauer und Abschnitte.
    final warned = (await e.plans.history()).last;
    final held = (warned.summary[planWarningKey]! as List).cast<Map>();
    final legacy = {
      ...warned.summary,
      planWarningKey: [
        for (final h in held)
          {
            for (final k in ['day', 'kind', 'fixed', 'pinned']) k: h[k],
          },
      ],
    };
    await e.plans.writeVersion(
      PlanVersionDraft(
        createdAt: _now(15),
        validFrom: _day(15),
        trigger: warned.trigger,
        reason: warned.reason,
        version: warned.version,
        inputs: warned.inputs,
        summary: legacy,
        units: await e.plans.unitsBetween(_day(15), planFarFuture),
        readState: planUnitsFingerprint(
          await e.plans.unitsBetween(warned.inputs.anchor, planFarFuture),
        ),
      ),
    );
    await e.service.lift(today: _day(16), now: _now(16));
    final back = await bridgeDay();
    expect(back.kind, isNot(PlanUnitKind.rest));
    expect(back.minutes, greaterThan(0));
    expect(back.segments, isNotEmpty);
  });

  group('WarningHeld: Speichern und Lesen (NB8 2, 3)', () {
    String sig(PlanSegment s) {
      final i = s.intensity;
      return [
        s.kind.name,
        s.minutes,
        s.seconds,
        if (i == null)
          'ohne'
        else ...[
          i.rpeMin,
          i.rpeMax,
          i.paceFastSecondsPerKm,
          i.paceSlowSecondsPerKm,
          i.basisCode,
          i.hrMinBpm,
          i.hrMaxBpm,
          i.estimated,
          i.maxHrEstimated,
          i.paceIsLimit,
        ],
      ].join('|');
    }

    const intensity = PlanTargetIntensity(
      rpeMin: 3,
      rpeMax: 4,
      paceFastSecondsPerKm: 345.5,
      paceSlowSecondsPerKm: 372,
      basisCode: 'hrZones',
      hrMinBpm: 128,
      hrMaxBpm: 142,
      estimated: true,
      maxHrEstimated: true,
      paceIsLimit: true,
    );

    test('Hin und zurück: Abschnitte mit Intensität, Sekunden, Dauer', () {
      final held = WarningHeld(
        day: _day(3),
        kind: PlanUnitKind.easy,
        fixed: PlanUnitFixed.kind,
        pinned: true,
        minutes: 41,
        segments: const [
          PlanSegment(
            kind: PlanSegmentKind.warmUp,
            minutes: 5,
            seconds: 290,
            intensity: intensity,
          ),
          PlanSegment(kind: PlanSegmentKind.easy, minutes: 36),
        ],
      );
      final back = WarningHeld.fromJson(held.toJson())!;
      expect(back.day, held.day);
      expect(back.kind, held.kind);
      expect(back.fixed, held.fixed);
      expect(back.pinned, isTrue);
      expect(back.minutes, 41);
      expect(
        [for (final x in back.segments) sig(x)],
        [for (final x in held.segments) sig(x)],
      );
      expect(back.segments.first.intensity, isNotNull);
    });

    test('alter Eintrag ohne Dauer und Abschnitte: lesbar, Brückentag wird '
        'aus der Rechnung gefüllt', () {
      final old = WarningHeld.fromJson({
        'day': '2026-11-14',
        'kind': 'easy',
        'fixed': 'none',
        'pinned': false,
      })!;
      expect(old.minutes, 0);
      expect(old.segments, isEmpty);
      PlanUnit unit(
        PlanUnitKind k,
        int day, {
        int min = 0,
        List<PlanSegment> seg = const [],
      }) => PlanUnit(
        day: _day(day),
        kind: k,
        phase: PlanPhase.build,
        weekIndex: 0,
        minutes: min,
        segments: seg,
      );
      final rest = unit(PlanUnitKind.rest, 3);
      final restored = restoreWarningHeld(
        [rest],
        [
          WarningHeld(
            day: _day(3),
            kind: old.kind,
            fixed: old.fixed,
            pinned: old.pinned,
          ),
        ],
      );
      expect(restored.single.kind, PlanUnitKind.easy);
      expect(restored.single.minutes, 0);
      final generated = [
        unit(PlanUnitKind.tempo, 10, min: 50),
        unit(
          PlanUnitKind.easy,
          12,
          min: 33,
          seg: const [PlanSegment(kind: PlanSegmentKind.easy, minutes: 33)],
        ),
      ];
      final filled = fillEmptyRestored(restored, generated);
      expect(filled.single.kind, PlanUnitKind.easy);
      expect(filled.single.minutes, 33);
      expect(filled.single.segments, hasLength(1));
      // Vorlage braucht Dauer und keinen Lauf: Einheiten gleicher Art mit
      // 0 min oder mit runId davor werden übergangen.
      final noMinutes = unit(PlanUnitKind.easy, 8);
      final withRun = unit(PlanUnitKind.easy, 9, min: 40).copyWith(runId: 7);
      final skipped = fillEmptyRestored(restored, [
        noMinutes,
        withRun,
        generated.last,
      ]);
      expect(skipped.single.minutes, 33);
      expect(
        fillEmptyRestored(restored, [noMinutes, withRun]).single.minutes,
        0,
      );
      // Ohne Einheit gleicher Art bleibt es unverändert.
      expect(fillEmptyRestored(restored, [generated.first]).single.minutes, 0);
      // Einheiten mit Dauer bleiben.
      final kept = unit(PlanUnitKind.easy, 3, min: 20);
      expect(fillEmptyRestored([kept], generated).single.minutes, 20);
    });
  });

  group('Erinnerung (reine Funktion)', () {
    test('fällig nach 7 Tagen', () {
      final on = DateTime.utc(2026, 11, 1);
      expect(
        warningReminderDue(reportedOn: on, today: DateTime.utc(2026, 11, 7)),
        isFalse,
      );
      expect(
        warningReminderDue(reportedOn: on, today: DateTime.utc(2026, 11, 8)),
        isTrue,
      );
    });

    test('Dienst: fällig nur mit Warnsignal', () async {
      final e = await _Env.open();
      expect(await e.service.reminderDue(_day(30)), isFalse);
      await e.service.report(
        source: WarningSource.manual,
        today: _day(0),
        now: _now(0),
      );
      expect(await e.service.reminderDue(_day(6)), isFalse);
      expect(await e.service.reminderDue(_day(7)), isTrue);
    });
  });
}

Future<List<PlanUnit>> _beforeUnits(List<String> sigs) async => [
  // Nur für den Vergleich der Festlegungen: aus den Signaturen gelesen.
  for (final s in sigs)
    () {
      final p = s.split('|');
      return PlanUnit(
        day: DateTime.parse(p[0]),
        kind: PlanUnitKind.values.byName(p[1]),
        phase: PlanPhase.values.byName(p[2]),
        weekIndex: int.parse(p[3]),
        minutes: int.parse(p[4]),
        segments: const [],
        pinned: p[6] == 'true',
        fixed: PlanUnitFixed.values.byName(p[7]),
      );
    }(),
];
