import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_started_unit.dart';

import 'helpers/local_clock.dart';

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags Ortszeit (Zone des Testprozesses).
final _now = DateTime(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);
DateTime _day(int n) => _today.add(Duration(days: n));

TrainingGoal _goal({DateTime? target, Set<int> days = const {2, 4, 6}}) =>
    TrainingGoal(
      type: GoalType.distance,
      distance: GoalDistance.tenKilometers,
      targetDate: target ?? DateTime.utc(2027, 6, 1),
      runDays: days,
      maxSessionSeconds: 7200,
      weeklyCapSeconds: 240 * 60.0,
      createdAt: DateTime.utc(2026, 11, 1),
      hardSessionEnabled: true,
      canRun30: ContinuousRun30.yes,
    );

String _dayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _Env {
  _Env(
    this.session, {
    List<RunFigures> runs = const [],
    RunFiguresLoader? loadRuns,
  }) : clock = LocalFakeClock(_now) {
    reader = PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: loadRuns ?? () async => runs,
    );
    controller = PlanController(session: session, clock: clock, reader: reader);
  }
  final StorageSession session;
  final FakeClock clock;
  late final PlanDataReader reader;
  late final PlanController controller;
  PlanRepository get plans => (session as PlanStorage).plans;
  GoalStore get goals => (session as GoalStorage).goals;

  static Future<_Env> open({
    List<RunFigures> runs = const [],
    RunFiguresLoader? loadRuns,
  }) async =>
      _Env(await FakeStorage().open(_key), runs: runs, loadRuns: loadRuns);
}

PlanUnit _unit(PlanUnitKind k, DateTime day) => PlanUnit(
  day: day,
  kind: k,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: 30,
  segments: const [],
);

/// Legt einen beendeten Lauf an, der [ago] Tage vor heute um 9 Uhr endet.
Future<int> _finishedRun(StorageSession s, int ago) async {
  final start = _day(-ago).add(const Duration(hours: 8));
  final r = await s.runs.create(startedAt: start);
  await s.runs.setState(
    r.id,
    RunState.finished,
    endedAt: start.add(const Duration(hours: 1)),
    endedUtcOffset: Duration.zero,
  );
  return r.id;
}

ComputedValue _vo2(String key, ValueQuality q) => ComputedValue(
  key: key,
  value: 45.0,
  unit: 'ml/kg/min',
  computedAt: _now,
  measurementCount: 1,
  sources: const ['strap'],
  method: 'm',
  methodVersion: 1,
  parameterVersion: 1,
  quality: q,
);

/// Schreibt eine Fassung mit [version] ab [validFrom] und [units] direkt.
Future<void> _writeVersion(
  _Env e,
  PlanVersion version,
  DateTime validFrom, {
  List<PlanUnit> units = const [],
  Map<String, Object?> summary = const {},
}) async {
  await e.plans.writeVersion(
    PlanVersionDraft(
      createdAt: validFrom,
      validFrom: validFrom,
      trigger: PlanTrigger.create,
      reason: 'create',
      version: version,
      inputs: PlanInputs.forNewGoal(_goal(), validFrom),
      summary: summary,
      units: units,
      readState: planUnitsFingerprint(
        await e.plans.unitsBetween(DateTime.utc(2000), planFarFuture),
      ),
    ),
  );
}

/// Schreibt die letzte Fassung mit denselben Einheiten, Eingaben und Hinweisen
/// als Fassung einer älteren Regelversion neu (ab heute der Uhr).
Future<void> _downgradeLast(_Env e) async {
  final last = (await e.plans.history()).last;
  final day = DateTime.utc(
    e.clock.now().year,
    e.clock.now().month,
    e.clock.now().day,
  );
  await e.plans.writeVersion(
    PlanVersionDraft(
      createdAt: e.clock.now(),
      validFrom: day,
      trigger: PlanTrigger.weekly,
      reason: 'weekly',
      version: const PlanVersion(method: 'alte-methode'),
      inputs: last.inputs,
      summary: last.summary,
      units: await e.plans.unitsBetween(day, planFarFuture),
      readState: planUnitsFingerprint(
        await e.plans.unitsBetween(DateTime.utc(2000), planFarFuture),
      ),
    ),
  );
  expect((await e.plans.history()).last.version.isCurrent, isFalse);
}

void main() {
  group('today geht an die Schreiber', () {
    test('saveGoal prüft das Zieldatum gegen heute, nicht createdAt', () async {
      final e = await _Env.open();
      // Zieldatum nach createdAt (1.11.), aber vor heute (11.11.).
      final r = await e.controller.saveGoal(
        _goal(target: DateTime.utc(2026, 11, 10)),
      );
      expect(r, PlanActionResult.rejected);
      expect(await e.goals.goal(), isNull);
      expect(await e.plans.history(), isEmpty);
    });

    test('saveGoal legt Ziel und erste Fassung ab heute an', () async {
      final e = await _Env.open();
      expect(await e.controller.saveGoal(_goal()), PlanActionResult.done);
      final h = await e.plans.history();
      expect(h, hasLength(1));
      expect(h.single.trigger, PlanTrigger.create);
      expect(h.single.validFrom, _today);
      final s = e.controller.state;
      expect(s.phase, PlanLoadPhase.ready);
      expect(s.hasPlan, isTrue);
      expect(s.hints, isNotNull);
      expect(s.lastChange, isNotNull);
      expect(s.weekUnits, isNotEmpty);
      // Zweites Speichern (andere Lauftage) ist eine Zieländerung.
      expect(
        await e.controller.saveGoal(_goal(days: const {1, 3, 5})),
        PlanActionResult.done,
      );
      expect((await e.plans.history()).map((v) => v.trigger), [
        PlanTrigger.create,
        PlanTrigger.goalChange,
      ]);
    });

    test('confirmMove: Tag vor heute abgelehnt, künftiger freier Tag gesetzt '
        'und pinned', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal());
      final units = await e.plans.unitsBetween(_day(1), _day(21));
      final u = units.first;
      expect(
        await e.controller.confirmMove(u.id!, _day(-1)),
        PlanActionResult.rejected,
      );
      expect((await e.plans.unitOn(u.day))?.id, u.id);
      final busy = {for (final x in units) x.day};
      final free = [
        for (var i = 1; i < 21; i++)
          if (!busy.contains(_day(i))) _day(i),
      ].first;
      expect(
        await e.controller.confirmMove(u.id!, free),
        PlanActionResult.done,
      );
      final moved = await e.plans.unitOn(free);
      expect(moved?.id, u.id);
      expect(moved?.pinned, isTrue);
    });

    test('replaceUnit: Inhalt wie checkReplace, fixed = kind, keine '
        'Neuberechnung; gesperrt rejected, fehlend notFound, vergangen '
        'rejected (heute aus der Uhr)', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal());
      final easy = (await e.plans.unitsBetween(
        _day(1),
        _day(28),
      )).firstWhere((u) => u.kind == PlanUnitKind.easy);
      final check = await e.controller.checkReplace(easy, PlanUnitKind.tempo);
      expect(check?.allowed, isTrue);
      final versions = (await e.plans.history()).length;
      expect(
        await e.controller.replaceUnit(easy.id!, PlanUnitKind.easy),
        PlanActionResult.rejected,
        reason: 'gleiche Art: gesperrt',
      );
      expect((await e.plans.unitOn(easy.day))?.fixed, PlanUnitFixed.none);
      expect(
        await e.controller.replaceUnit(9999, PlanUnitKind.tempo),
        PlanActionResult.notFound,
      );
      expect(
        await e.controller.replaceUnit(easy.id!, PlanUnitKind.tempo),
        PlanActionResult.done,
      );
      final r = (await e.plans.unitOn(easy.day))!;
      expect(r.id, easy.id);
      expect(r.kind, PlanUnitKind.tempo);
      expect(r.fixed, PlanUnitFixed.kind);
      expect(r.pinned, isTrue);
      expect(r.minutes, check!.unit!.minutes);
      expect(
        [for (final s in r.segments) s.kind],
        [for (final s in check.unit!.segments) s.kind],
      );
      expect((await e.plans.history()).length, versions);
      // Am Tag nach der Einheit ist sie vergangen.
      e.clock.set(localAt(easy.day.add(const Duration(days: 1)), 12));
      expect(
        await e.controller.replaceUnit(easy.id!, PlanUnitKind.long),
        PlanActionResult.rejected,
      );
    });

    test('setRestDay/clearRestDay: Einheit auf Alternativtag oder entfällt, '
        'Ruhetag aufheben, keine Neuberechnung', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal());
      final units = await e.plans.unitsBetween(_day(7), _day(27));
      final versions = (await e.plans.history()).length;
      final first = units.first;
      final rc = (await e.controller.checkRestDay(first.day))!;
      expect(rc.unit?.id, first.id);
      expect(rc.alternatives, isNotEmpty);
      final alt = rc.alternatives.first;
      expect(
        await e.controller.setRestDay(
          first.day,
          expectedUnitId: first.id,
          moveUnitTo: alt,
        ),
        PlanActionResult.done,
      );
      expect((await e.plans.unitOn(first.day))!.isRestDay, isTrue);
      expect((await e.plans.unitOn(first.day))!.fixed, PlanUnitFixed.day);
      expect((await e.plans.unitOn(alt))?.id, first.id);
      expect(
        await e.controller.setRestDay(
          first.day,
          expectedUnitId: (await e.plans.unitOn(first.day))!.id,
        ),
        PlanActionResult.rejected,
        reason: 'schon Ruhetag',
      );
      final second = units.last;
      // Der Tag weicht von der Prüfung ab (FR-0176): nichts entfällt.
      for (final seen in [null, first.id]) {
        expect(
          await e.controller.setRestDay(second.day, expectedUnitId: seen),
          PlanActionResult.rejected,
          reason: 'gesehen: $seen',
        );
        expect((await e.plans.unitOn(second.day))?.id, second.id);
      }
      expect(
        await e.controller.setRestDay(second.day, expectedUnitId: second.id),
        PlanActionResult.done,
      );
      expect((await e.plans.unitOn(second.day))!.isRestDay, isTrue);
      expect(
        (await e.plans.unitsBetween(
          _day(7),
          _day(27),
        )).where((u) => u.id == second.id),
        isEmpty,
        reason: 'ohne Zieltag entfällt die Einheit',
      );
      // Ruhetag auf freiem Tag, aufheben, zweites Aufheben findet nichts.
      final taken = {
        for (final u in await e.plans.unitsBetween(_day(7), _day(27))) u.day,
      };
      final free = [
        for (var i = 7; i < 28; i++)
          if (!taken.contains(_day(i))) _day(i),
      ].first;
      final results = [
        await e.controller.setRestDay(free, expectedUnitId: null),
        await e.controller.clearRestDay(free),
        await e.controller.clearRestDay(free),
      ];
      expect(results, [
        PlanActionResult.done,
        PlanActionResult.done,
        PlanActionResult.notFound,
      ]);
      expect(await e.plans.unitOn(free), isNull);
      expect(await e.controller.clearRestDay(first.day), PlanActionResult.done);
      expect(await e.plans.unitOn(first.day), isNull);
      // Vergangene Ruhetage bleiben (heute aus der Uhr).
      e.clock.set(localAt(second.day.add(const Duration(days: 1)), 12));
      expect(
        await e.controller.clearRestDay(second.day),
        PlanActionResult.rejected,
      );
      expect((await e.plans.history()).length, versions);
    });
  });

  group('Öffnen: wöchentliche Prüfung und Regelversion', () {
    Future<_Env> withOld(PlanVersion v, {required String lastCheck}) async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      await _writeVersion(e, v, _day(-7));
      await e.session.settings.set(planLastCheckDayKey, lastCheck, at: _now);
      return e;
    }

    test('fällig und alte Regelversion: Auslöser ruleVersion', () async {
      final e = await withOld(
        const PlanVersion(method: 'alte-methode'),
        lastCheck: _dayText(_day(-7)),
      );
      await e.controller.open();
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.trigger, PlanTrigger.ruleVersion);
      expect(h.last.version.isCurrent, isTrue);
      expect(h.last.validFrom, _today);
      expect(e.controller.state.ruleVersionPending, isFalse);
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_today),
      );
    });

    test('alte Regelversion, gleiche Einheiten: neue Fassung ohne Karte, '
        'Hinweis weg, Prüftag gesetzt', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal());
      final units = await e.plans.unitsBetween(_today, planFarFuture);
      await _downgradeLast(e);
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(_day(-7)),
        at: _now,
      );
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.ruleVersion);
      expect(h.last.version.isCurrent, isTrue);
      expect(e.controller.state.ruleVersionPending, isFalse);
      expect(e.controller.state.lastChange?.isEmpty ?? true, isTrue);
      expect(
        (await e.plans.unitsBetween(
          _today,
          planFarFuture,
        )).map((u) => '${u.day}${u.kind.name}${u.minutes}').toList(),
        units.map((u) => '${u.day}${u.kind.name}${u.minutes}').toList(),
      );
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_today),
      );
      final n = h.length;
      await e.controller.open();
      expect((await e.plans.history()).length, n);
    });

    test('alte Regelversion unter Warnsignal: neue Fassung, gehaltene '
        'Einheiten bleiben gehalten', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal());
      await e.controller.reportWarning();
      await _downgradeLast(e);
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(_day(-7)),
        at: _now,
      );
      await e.controller.open();
      final last = (await e.plans.history()).last;
      expect(last.trigger, PlanTrigger.ruleVersion);
      expect(last.version.isCurrent, isTrue);
      expect(warningHeldFromSummary(last.summary), isNotNull);
      expect(
        (await e.plans.unitsBetween(
          _today,
          planFarFuture,
        )).every((u) => u.kind == PlanUnitKind.rest),
        isTrue,
      );
      expect(e.controller.state.ruleVersionPending, isFalse);
    });

    test('nicht fällig (Prüfung diese Woche): keine stille Neuberechnung, '
        'alte Regelversion wird gemeldet', () async {
      final e = await withOld(
        const PlanVersion(method: 'alte-methode'),
        lastCheck: _dayText(_day(-2)), // Montag dieser Woche
      );
      await e.controller.open();
      expect(await e.plans.history(), hasLength(1));
      expect(e.controller.state.ruleVersionPending, isTrue);
      expect(e.controller.state.hints, isNotNull);
    });
  });

  test(
    'Lese-Adapter: Lauf an lockerer Einheit zählt als locker, Lauf an '
    'harter Einheit nie (auch mit RPE 3), Lauf ohne Einheit über RPE',
    () async {
      // Läufe ohne Puls, 5 km in 30 min, in den letzten Tagen.
      RunFigures run(int id, int ago) => RunFigures(
        runId: id,
        endedAt: _day(-ago).add(const Duration(hours: 8)),
        day: _dayText(_day(-ago)),
        distanceMeters: 5000,
        movingTime: const Duration(minutes: 30),
        totalTime: const Duration(minutes: 30),
        paceTime: const Duration(minutes: 30),
      );
      final probe = await _Env.open();
      final ids = <int>[];
      for (var i = 0; i < 5; i++) {
        final r = await probe.session.runs.create(startedAt: _day(-5 + i));
        await probe.session.runs.setState(
          r.id,
          RunState.finished,
          endedAt: _day(-5 + i).add(const Duration(hours: 1)),
          endedUtcOffset: Duration.zero,
        );
        ids.add(r.id);
      }
      final e = _Env(
        probe.session,
        runs: [for (var i = 0; i < 5; i++) run(ids[i], 5 - i)],
      );
      await e.goals.save(_goal(), today: _goal().createdAt);
      await _writeVersion(
        e,
        PlanVersion.current,
        _today,
        units: [
          _unit(PlanUnitKind.easy, _day(0)),
          _unit(PlanUnitKind.long, _day(1)),
          _unit(PlanUnitKind.easy, _day(2)),
          _unit(PlanUnitKind.intervals, _day(3)),
        ],
      );
      final units = await e.plans.unitsBetween(_today, _day(3));
      for (var i = 0; i < 4; i++) {
        await e.plans.assignRun(units[i].id!, ids[i], expectedRunId: null);
      }
      await e.session.subjective.save(ids[3], RunSubjective(rpe: 3));
      await e.session.subjective.save(ids[4], RunSubjective(rpe: 3));

      final built = await e.reader.read(goal: _goal(), today: _today);
      // 3 an locker/lang + 1 ohne Einheit mit RPE 3; der Lauf an der harten
      // Einheit zählt trotz RPE 3 nicht.
      expect(built.inputs.easyRunCount, 4);
      expect(built.inputs.easyPaceSecondsPerKm, closeTo(360, 0.01));
    },
  );

  group('Warteschlange, Prüftag und Hinweise der Fassung', () {
    test('Warteschlange: assignRun wartet, bis die laufende Neuberechnung '
        'ihre Fassung geschrieben hat', () async {
      Completer<void>? gate;
      var reads = 0;
      PlanUnit? seenBySecondRead;
      late _Env e;
      e = await _Env.open(
        loadRuns: () async {
          reads++;
          // Je Neuberechnung zwei Lesevorgänge: Eingaben und Läufe der
          // Abweichung (PAR-235).
          if (reads == 3) {
            // Lesen der Neuberechnung nach assignRun.
            seenBySecondRead = await e.plans.unitOn(_day(1));
          }
          if (gate != null && reads == 1) await gate.future;
          return const [];
        },
      );
      expect(await e.controller.saveGoal(_goal()), PlanActionResult.done);
      final unit = (await e.plans.unitsBetween(_day(1), _day(7))).first;
      final runId = await _finishedRun(e.session, 0);
      await e.session.settings.set(planLastCheckDayKey, 'alt', at: _now);
      reads = 0;
      gate = Completer<void>();
      final manual = e.controller.recalculate();
      final assign = e.controller.assignRun(unit.id!, runId);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      // Die Neuberechnung hängt beim Lesen; die Zuordnung ist noch nicht
      // geschrieben.
      expect(reads, 1);
      expect((await e.plans.unitOn(unit.day))?.runId, isNull);
      gate.complete();
      expect(await manual, PlanActionResult.done);
      expect(await assign, PlanActionResult.done);
      expect(reads, 4);
      // assignRun lief erst nach dem Abschluss der Neuberechnung (Prüftag
      // geschrieben) und hat dann zugeordnet.
      expect(seenBySecondRead?.runId, runId);
      // Manuell bewertet die Woche nicht und setzt den Prüftag nicht (ADR-0010
      // Nachtrag WP24).
      expect(await e.session.settings.get(planLastCheckDayKey), 'alt');
      expect((await e.plans.unitOn(unit.day))?.runId, runId);
    });

    test('Rückmeldung „zu schwer“ setzt den Prüftag nicht, nur den eigenen '
        'Merker der 2-Wochen-Frage', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      await _writeVersion(e, PlanVersion.current, _day(-7));
      final lastCheck = _dayText(_day(-7));
      await e.session.settings.set(planLastCheckDayKey, lastCheck, at: _now);
      final before = (await e.plans.history()).length;
      final r = await e.controller.answerFeedback(PlanFeedback.tooHard);
      expect(r.result, PlanActionResult.done);
      expect(r.planChanged, isTrue);
      expect((await e.plans.history()).length, before + 1);
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        lastCheck,
        reason: 'die Rückmeldung bewertet die Woche (PAR-201) nicht',
      );
      expect(
        await e.session.settings.get(planFeedbackKey),
        _dayText(_today),
        reason: 'Abstand der Nachfrage hängt am eigenen Merker',
      );
    });

    test('Rückmeldung „zu schwer“ ohne neue Fassung (Geh-Lauf-Abfolge): '
        'planChanged ist falsch; „passt“ ebenso', () async {
      final e = await _Env.open();
      final g = _goal();
      final walkRun = TrainingGoal(
        type: g.type,
        distance: g.distance,
        targetDate: g.targetDate,
        runDays: g.runDays,
        maxSessionSeconds: g.maxSessionSeconds,
        weeklyCapSeconds: g.weeklyCapSeconds,
        createdAt: g.createdAt,
        hardSessionEnabled: g.hardSessionEnabled,
        canRun30: ContinuousRun30.no,
      );
      e.clock.set(localAt(_day(-3)));
      expect(await e.controller.saveGoal(walkRun), PlanActionResult.done);
      e.clock.set(_now);
      final before = (await e.plans.history()).length;
      final hard = await e.controller.answerFeedback(PlanFeedback.tooHard);
      expect(hard.result, PlanActionResult.done);
      expect((await e.plans.history()).length, before);
      expect(hard.planChanged, isFalse);
      final fits = await e.controller.answerFeedback(PlanFeedback.fits);
      expect(fits.planChanged, isFalse);
    });

    test('Lese-Adapter: Güte aus dem neuesten Laufwert (alt gut, neu '
        'vorläufig: keine Güte)', () async {
      for (final (newest, grade) in [
        (ValueQuality.provisional, null),
        (ValueQuality.good, Vo2maxGrade.good),
      ]) {
        final e = await _Env.open();
        final old = await _finishedRun(e.session, 10);
        final recent = await _finishedRun(e.session, 2);
        await e.session.values.createOriginals(ValueOwner.run(old), [
          _vo2(vo2maxRunValueKey, ValueQuality.good),
        ]);
        await e.session.values.createOriginals(ValueOwner.run(recent), [
          _vo2(vo2maxRunValueKey, newest),
        ]);
        await e.session.values.createOriginals(
          ValueOwner.day(_dayText(_day(-2))),
          [_vo2(vo2maxLongTermValueKey, ValueQuality.good)],
        );
        final built = await e.reader.read(goal: _goal(), today: _today);
        expect(built.inputs.intensity?.vo2max, 45.0);
        expect(built.inputs.intensity?.vo2maxGrade, grade, reason: '$newest');
      }
    });

    test(
      'saveGoal: scheitert die Neuberechnung, bleibt das Ziel gespeichert '
      '(savedNotPlanned) und die nächste Neuberechnung ist goalChange',
      () async {
        var fail = false;
        final e = await _Env.open(
          loadRuns: () async {
            if (fail) throw StateError('Lesen gescheitert');
            return const [];
          },
        );
        expect(await e.controller.saveGoal(_goal()), PlanActionResult.done);
        fail = true;
        final changed = _goal(days: const {1, 3, 5});
        expect(
          await e.controller.saveGoal(changed),
          PlanActionResult.savedNotPlanned,
        );
        expect((await e.goals.goal())?.runDays, changed.runDays);
        expect(await e.plans.history(), hasLength(1));
        fail = false;
        expect(await e.controller.recalculate(), PlanActionResult.done);
        final h = await e.plans.history();
        expect(h.last.trigger, PlanTrigger.goalChange);
        expect(
          {
            for (final u in await e.plans.unitsBetween(_day(0), _day(13)))
              u.day.weekday,
          },
          {1, 3, 5},
        );
      },
    );

    test('Hinweise kommen aus dem summary der Fassung, nicht aus einer '
        'Vorschau', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      final stored = GeneratedPlan(
        version: PlanVersion.current,
        weeks: const [],
        units: const [],
        frozenUnits: const [],
        unplacedByWeek: const {},
        hardOmissions: const {},
        pinnedConflicts: [
          PinnedConflict(kind: PinnedConflictKind.dayTaken, day: _day(2)),
        ],
        walkRunStaysAtWeek: 3,
        walkRunNoWeekFits: true,
      );
      await _writeVersion(
        e,
        PlanVersion.current,
        _today,
        units: [_unit(PlanUnitKind.easy, _day(1))],
        summary: {planHintsKey: planHintsToJson(stored)},
      );
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(_today),
        at: _now,
      );
      await e.controller.open();
      final hints = e.controller.state.hints!;
      expect(hints.walkRunNoWeekFits, isTrue);
      expect(hints.walkRunStaysAtWeek, 3);
      expect(hints.pinnedConflicts.single.day, _day(2));
      expect(hints.units.single.day, _day(1));
    });
  });

  group('Läufe im Zeitraum und Abstand beim Verschieben', () {
    test('runsBetween: RPE 7 ist intensiv, 6 nicht (PAR-058); nur beendete '
        'Läufe, Tag nach Ortszeit des Endes, Grenzen eingeschlossen', () async {
      final e = await _Env.open();
      Future<int> run(
        DateTime end, {
        int? rpe,
        Duration? offset,
        bool finish = true,
      }) async {
        final r = await e.session.runs.create(
          startedAt: end.subtract(const Duration(hours: 1)),
        );
        if (finish) {
          await e.session.runs.setState(
            r.id,
            RunState.finished,
            endedAt: end,
            endedUtcOffset: offset,
          );
        }
        if (rpe != null) {
          await e.session.subjective.save(r.id, RunSubjective(rpe: rpe));
        }
        return r.id;
      }

      final seven = await run(_day(1).add(const Duration(hours: 9)), rpe: 7);
      final six = await run(_day(2).add(const Duration(hours: 9)), rpe: 6);
      // UTC am Vortag des Zeitraums, Ortszeit (+10 h) am ersten Tag.
      final east = await run(
        _day(0).subtract(const Duration(hours: 4)),
        offset: const Duration(hours: 10),
      );
      // UTC im Zeitraum, Ortszeit (-10 h) am Tag davor: fällt weg.
      await run(
        _day(0).add(const Duration(hours: 4)),
        offset: const Duration(hours: -10),
      );
      // Letzter Tag, kurz vor Mitternacht.
      final last = await run(_day(3).add(const Duration(hours: 23)), rpe: 9);
      await run(_day(4).add(const Duration(hours: 1)), rpe: 9); // danach
      await run(_day(1), rpe: 8, finish: false); // nicht beendet
      final runs = await e.controller.runsBetween(_day(0), _day(3));
      expect(
        {for (final r in runs) r.id: (r.day, r.intensive)},
        {
          east: (_day(0), false),
          seven: (_day(1), true),
          six: (_day(2), false),
          last: (_day(3), true),
        },
      );
    });

    test(
      'runsBetween: intensiv durch Zeit bei ≥ 80 % HFmax ohne RPE, durch '
      'RPE ohne Puls, keins von beiden (PAR-058, FR-0152, FR-0177)',
      () async {
        final e = await _Env.open();
        ComputedValue high(double? minutes) => ComputedValue(
          key: highHeartRateTimeValueKey,
          value: minutes,
          unavailableReason: minutes == null
              ? UnavailableReason.missingMaxHeartRate
              : null,
          unit: minutesUnit,
          computedAt: _now,
          measurementCount: minutes == null ? 0 : 600,
          sources: const ['strap'],
          method: HighHeartRateTime.methodId,
          methodVersion: 1,
          parameterVersion: 1,
          quality: minutes == null
              ? ValueQuality.undeterminable
              : ValueQuality.good,
        );
        Future<int> run(
          int day, {
          int? rpe,
          double? minutes,
          bool value = true,
        }) async {
          final r = await e.session.runs.create(
            startedAt: _day(day).add(const Duration(hours: 8)),
          );
          await e.session.runs.setState(
            r.id,
            RunState.finished,
            endedAt: _day(day).add(const Duration(hours: 9)),
            endedUtcOffset: Duration.zero,
          );
          if (rpe != null) {
            await e.session.subjective.save(r.id, RunSubjective(rpe: rpe));
          }
          if (value) {
            await e.session.values.createOriginals(ValueOwner.run(r.id), [
              high(minutes),
            ]);
          }
          return r.id;
        }

        final byHr = await run(0, minutes: 10);
        final byRpe = await run(1, rpe: 7, value: false);
        final neither = await run(2, rpe: 6, minutes: 9);
        final unavailable = await run(3);
        final unavailableRpe = await run(4, rpe: 7);
        final runs = await e.controller.runsBetween(_day(0), _day(4));
        expect(
          {for (final r in runs) r.id: r.intensive},
          {
            byHr: true,
            byRpe: true,
            neither: false,
            unavailable: false,
            unavailableRpe: true,
          },
        );
      },
    );

    test('runsBetween an der Versatzgrenze ±18 h (maxRunEndUtcOffset): '
        'genau 18 h zählt zum Plantag der Ortszeit des Starts (PAR-237), mehr '
        'wird abgewiesen', () async {
      final e = await _Env.open();
      const limit = Duration(hours: 18);
      const second = Duration(seconds: 1);
      // Jeder Lauf dauert 1 h.
      Future<int> run(DateTime start, Duration offset) async {
        final r = await e.session.runs.create(startedAt: start);
        await e.session.runs.setState(
          r.id,
          RunState.finished,
          endedAt: start.add(const Duration(hours: 1)),
          endedUtcOffset: offset,
        );
        return r.id;
      }

      // +18 h: Start UTC 18 h vor dem ersten Tag, Ortszeit genau
      // Mitternacht des ersten Tags.
      final firstMidnight = await run(_day(0).subtract(limit), limit);
      // Eine Sekunde früher: Start am Vortag, Ende im Zeitraum, fällt weg.
      await run(_day(0).subtract(limit + second), limit);
      // −18 h: Start eine Sekunde vor Mitternacht des letzten Tags (Ortszeit),
      // Ende am Folgetag 00:59:59, also UTC fast 19 h nach dem Ende des
      // letzten Tags: nur mit dem Puffer für den Folgetag gefunden.
      final lastSecond = await run(_day(4).add(limit - second), -limit);
      // Genau 18 h danach: Start Mitternacht des Folgetags, fällt weg.
      await run(_day(4).add(limit), -limit);

      final runs = await e.controller.runsBetween(_day(0), _day(3));
      expect(
        {for (final r in runs) r.id: r.day},
        {firstMidnight: _day(0), lastSecond: _day(3)},
      );

      // Knapp über der Grenze: requireRunEnd lehnt das Speichern ab.
      for (final offset in [limit + second, -(limit + second)]) {
        final r = await e.session.runs.create(startedAt: _day(1));
        await expectLater(
          e.session.runs.setState(
            r.id,
            RunState.finished,
            endedAt: _day(1).add(const Duration(hours: 1)),
            endedUtcOffset: offset,
          ),
          throwsA(
            isA<StorageException>().having(
              (x) => x.failure,
              'failure',
              StorageFailure.rejected,
            ),
          ),
        );
        expect((await e.session.runs.get(r.id))!.endedAt, isNull);
      }
    });

    test('confirmMove: Abstandskonflikt der Verschiebung ist ohne '
        'Neuberechnung sichtbar, Konflikte vor heute nicht', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      const empty = GeneratedPlan(
        version: PlanVersion.current,
        weeks: [],
        units: [],
        frozenUnits: [],
        unplacedByWeek: {},
        hardOmissions: {},
      );
      await _writeVersion(
        e,
        PlanVersion.current,
        _today,
        units: [
          _unit(PlanUnitKind.long, _day(1)),
          _unit(PlanUnitKind.long, _day(5)),
        ],
        summary: {
          planHintsKey: planHintsToJson(
            empty.copyWith(
              pinnedConflicts: [
                // Aus der letzten Rechnung, Termin vor heute: fällt weg.
                PinnedConflict(
                  kind: PinnedConflictKind.noMatchingUnit,
                  day: _day(-1),
                ),
                // Gespeicherter Abstandskonflikt, den es nicht mehr gibt.
                PinnedConflict(
                  kind: PinnedConflictKind.spacing,
                  day: _day(5),
                  otherDay: _day(4),
                ),
              ],
            ),
          ),
        },
      );
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(_today),
        at: _now,
      );
      await e.controller.open();
      expect(e.controller.state.hints!.pinnedConflicts, isEmpty);
      final later = await e.plans.unitOn(_day(5));
      expect(
        await e.controller.confirmMove(later!.id!, _day(2)),
        PlanActionResult.done,
      );
      expect(await e.plans.history(), hasLength(1));
      final c = e.controller.state.hints!.pinnedConflicts.single;
      expect(c.kind, PinnedConflictKind.spacing);
      expect(c.day, _day(2));
      expect(c.otherDay, _day(1));
    });
    RunFigures fig(int id, int ago) => RunFigures(
      runId: id,
      endedAt: _day(-ago).add(const Duration(hours: 8)),
      day: _dayText(_day(-ago)),
      distanceMeters: 5000,
      movingTime: const Duration(minutes: 30),
      totalTime: const Duration(minutes: 30),
      paceTime: const Duration(minutes: 30),
    );

    /// Ziel gespeichert, Neuberechnung danach gescheitert; [restart]: neuer
    /// Controller über demselben Speicher (Neustart). Danach wird über
    /// [path] nachgeholt, dann ein Lauf zugeordnet.
    Future<void> catchUp(String path, {required bool restart}) async {
      var fail = false;
      var runs = <RunFigures>[];
      Future<List<RunFigures>> load() async {
        if (fail) throw StateError('Lesen gescheitert');
        return runs;
      }

      final first = await _Env.open(loadRuns: load);
      expect(await first.controller.saveGoal(_goal()), PlanActionResult.done);
      fail = true;
      final changed = _goal(days: const {1, 3, 5});
      expect(
        await first.controller.saveGoal(changed),
        PlanActionResult.savedNotPlanned,
      );
      expect(await first.plans.history(), hasLength(1));
      fail = false;
      final e = restart ? _Env(first.session, loadRuns: load) : first;
      final runId = await _finishedRun(e.session, 0);
      final next = (await e.plans.unitsBetween(_today, _day(13))).first;
      switch (path) {
        case 'open':
          await e.controller.open();
        case 'assignRun':
          expect(
            await e.controller.assignRun(next.id!, runId),
            PlanActionResult.done,
          );
        case 'recalculate':
          expect(await e.controller.recalculate(), PlanActionResult.done);
      }
      var h = await e.plans.history();
      expect(h, hasLength(2), reason: path);
      expect(h.last.trigger, PlanTrigger.goalChange, reason: path);
      expect(
        {
          for (final u in await e.plans.unitsBetween(_day(1), _day(14)))
            if (u.runId == null) u.day.weekday,
        },
        {1, 3, 5},
      );
      expect(planGoalChangedSince(h.last.summary, changed), isFalse);
      // Danach wieder der normale Auslöser. Damit er sichtbar wird, liegen
      // die künftigen Einheiten (ohne pinned) auf Tagen außerhalb der
      // Lauftage; das summary der nachholenden Fassung bleibt. `run` hält
      // die Tage (automatisch), `goalChange` legte sie auf Mo/Mi/Fr.
      final last = h.last;
      await e.plans.writeVersion(
        PlanVersionDraft(
          createdAt: _now,
          validFrom: _today,
          trigger: last.trigger,
          reason: 'test',
          version: last.version,
          inputs: last.inputs,
          summary: last.summary,
          units: [
            _unit(PlanUnitKind.easy, _day(6)),
            _unit(PlanUnitKind.easy, _day(8)),
          ],
          readState: planUnitsFingerprint(
            await e.plans.unitsBetween(DateTime.utc(2000), planFarFuture),
          ),
        ),
      );
      runs = [fig(runId, 0)];
      final tue = await e.plans.unitOn(_day(6));
      expect(
        await e.controller.assignRun(tue!.id!, null),
        PlanActionResult.done,
      );
      h = await e.plans.history();
      expect(h, hasLength(4), reason: path);
      expect(h.last.trigger, PlanTrigger.run, reason: path);
      expect((await e.plans.unitOn(_day(6)))?.id, isNotNull);
      expect(await e.plans.unitOn(_day(5)), isNull);
    }

    for (final restart in [false, true]) {
      for (final path in ['open', 'assignRun', 'recalculate']) {
        test(
          'savedNotPlanned: Nachholen über $path '
          '${restart ? 'nach Neustart' : 'in der Sitzung'}, danach wieder '
          'run',
          () => catchUp(path, restart: restart),
        );
      }
    }
  });

  group('Wochenprüfung PAR-201 beim Öffnen', () {
    // Plan seit Mittwoch 21.10.; geöffnet wird am Mittwoch 25.11., geprüft
    // wird die Woche 16.-22.11. (monday(0)), die Folgewoche ist monday(1).
    DateTime monday(int n) =>
        DateTime.utc(2026, 11, 16).add(Duration(days: 7 * n));

    Future<int> week(_Env e, DateTime from) async => [
      for (final u in await e.plans.unitsBetween(
        from,
        from.add(const Duration(days: 6)),
      ))
        u.minutes,
    ].fold<int>(0, (a, b) => a + b);

    Future<(_Env, int)> prepare({double share = 0}) async {
      final planned = <int>[0];
      final runs = <RunFigures>[];
      final e = await _Env.open(loadRuns: () async => runs);
      e.clock.set(localAt(_day(-21)));
      await e.controller.saveGoal(_goal());
      planned[0] = await week(e, monday(0));
      if (share > 0) {
        runs.add(
          RunFigures(
            runId: 1,
            endedAt: monday(0).add(const Duration(days: 2, hours: 9)),
            day: '2026-11-18',
            movingTime: Duration(minutes: (planned[0] * share).round()),
          ),
        );
      }
      e.clock.set(localAt(_day(14)));
      return (e, planned[0]);
    }

    test('Lauf zuordnen vor der Prüfung (Lauf über Mitternacht in den '
        'Montag): der Prüftag bleibt, das Öffnen bewertet die Woche', () async {
      // Lauf 1 des Belegs (30 % der Woche) ist auch der zugeordnete.
      final (e, planned) = await prepare(share: 0.3);
      // Der Lauf liegt kurz vor heute, sonst hielte die Pausenfrage die
      // Prüfung an.
      final runId = await _finishedRun(e.session, -12);
      expect(runId, 1);
      final lastCheck = await e.session.settings.get(planLastCheckDayKey);
      final unit = (await e.plans.unitsBetween(_day(14), planFarFuture)).first;
      expect(
        await e.controller.assignRun(unit.id!, runId),
        PlanActionResult.done,
      );
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        lastCheck,
        reason: 'ohne Bewertung kein Prüftag',
      );
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.weekly);
      expect(h.last.reason, 'repeatWeek');
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
    });
  });

  group('Wochenprüfung: Belege aus dem Speicher', () {
    // Plan seit Mittwoch 21.10.; bewertet wird die Woche 16.-22.11., geöffnet
    // wird Dienstag 24.11. (letzter Lauf höchstens 3 Tage her).
    DateTime monday(int n) =>
        DateTime.utc(2026, 11, 16).add(Duration(days: 7 * n));

    late _Env e;
    late List<RunFigures> runs;

    Future<void> prepare() async {
      runs = <RunFigures>[];
      e = await _Env.open(loadRuns: () async => runs);
      e.clock.set(localAt(_day(-21)));
      await e.controller.saveGoal(_goal());
      e.clock.set(DateTime(2026, 11, 24, 12));
    }

    Future<List<PlanUnit>> week(int n) async => [
      for (final u in await e.plans.unitsBetween(
        monday(n),
        monday(n).add(const Duration(days: 6)),
      ))
        if (u.kind != PlanUnitKind.rest) u,
    ];

    /// Lauf am Tag [day] (UTC), [minutes] lang; mit [unit] der Einheit
    /// zugeordnet.
    Future<void> addRun(
      DateTime day,
      int minutes, {
      PlanUnit? unit,
      int? rpe,
      int? wellbeing,
    }) async {
      final start = day.add(const Duration(hours: 8));
      final r = await e.session.runs.create(startedAt: start);
      await e.session.runs.setState(
        r.id,
        RunState.finished,
        endedAt: start.add(Duration(minutes: minutes)),
        endedUtcOffset: Duration.zero,
      );
      if (rpe != null || wellbeing != null) {
        await e.session.subjective.save(
          r.id,
          RunSubjective(rpe: rpe, wellbeing: wellbeing),
        );
      }
      if (unit != null) {
        await e.plans.assignRun(unit.id!, r.id, expectedRunId: null);
      }
      runs.add(
        RunFigures(
          runId: r.id,
          endedAt: start.add(Duration(minutes: minutes)),
          day: _dayText(day),
          movingTime: Duration(minutes: minutes),
        ),
      );
    }

    /// Alle Einheiten der Woche voll gelaufen; RPE nach [rpeOf].
    Future<void> runWeek(
      int n, {
      int? Function(PlanUnit u, int index)? rpeOf,
      int? lastWellbeing,
    }) async {
      final units = await week(n);
      for (var i = 0; i < units.length; i++) {
        final u = units[i];
        await addRun(
          u.day,
          u.minutes,
          unit: u,
          rpe: rpeOf?.call(u, i),
          wellbeing: i == units.length - 1 ? lastWellbeing : null,
        );
      }
    }

    bool easy(PlanUnit u) =>
        u.kind == PlanUnitKind.easy || u.kind == PlanUnitKind.long;

    Future<PlanVersionRecord?> opened() async {
      final before = (await e.plans.history()).length;
      await e.controller.open();
      final h = await e.plans.history();
      return h.length > before ? h.last : null;
    }

    test('Ermüdung: Befinden 2 beim letzten Lauf (3 Tage alt) -> fatigue, '
        'Befinden 3 -> keine Anpassung (PAR-188)', () async {
      await prepare();
      await runWeek(0, lastWellbeing: 2);
      final v = await opened();
      expect(v?.reason, 'fatigue');
      expect(v?.inputs.noHardUntil, isNotNull);
    });

    test('Befinden 3 beim letzten Lauf: keine Anpassung', () async {
      await prepare();
      await runWeek(0, lastWellbeing: 3);
      expect(await opened(), isNull);
    });

    test('RPE: 2 von 3 lockeren Läufen mit RPE >= 6, harter Lauf dazwischen '
        '-> fatigue', () async {
      await prepare();
      final units = await week(0);
      expect(units.where(easy).length, greaterThanOrEqualTo(2));
      var n = 0;
      await runWeek(
        0,
        rpeOf: (u, i) {
          if (!easy(u)) return 3;
          return n++ < 2 ? 7 : 4;
        },
      );
      final v = await opened();
      expect(v?.reason, 'fatigue');
    });

    test(
      'RPE: nur 1 von 3 lockeren Läufen mit RPE >= 6 -> keine Ermüdung',
      () async {
        await prepare();
        var n = 0;
        await runWeek(0, rpeOf: (u, i) => easy(u) ? (n++ == 0 ? 7 : 4) : 3);
        expect(await opened(), isNull);
      },
    );

    test('Öffnen erst am Samstag: ein lockerer Lauf der laufenden Woche '
        'verdrängt die bewertete Woche nicht aus dem RPE-Fenster', () async {
      await prepare();
      var n = 0;
      await runWeek(0, rpeOf: (u, i) => easy(u) ? (n++ < 2 ? 7 : 4) : 3);
      // Samstag der laufenden Woche; ein lockerer Lauf (RPE 3) am Dienstag.
      final current = (await week(1)).firstWhere(easy);
      await addRun(current.day, current.minutes, unit: current, rpe: 3);
      e.clock.set(DateTime(2026, 11, 28, 12));
      final v = await opened();
      expect(v?.reason, 'fatigue');
    });

    test('RPE zählt nur lockere Läufe: ein freier Lauf mit RPE 8 macht aus '
        'einem lockeren mit RPE 7 keine Ermüdung', () async {
      await prepare();
      final units = await week(0);
      expect(units.where(easy).length, 3);
      final rpe = [4, 7, 4];
      for (var i = 0; i < units.length; i++) {
        await addRun(
          units[i].day,
          units[i].minutes,
          unit: units[i],
          rpe: rpe[i],
        );
        if (i == 1) {
          // Freier Lauf (keiner Einheit zugeordnet) zwischen den lockeren.
          await addRun(units[i].day.add(const Duration(days: 1)), 20, rpe: 8);
        }
      }
      expect(await opened(), isNull);
    });

    test('Wochengrenze: ein Lauf der laufenden Woche zählt nicht zur '
        'bewerteten Woche', () async {
      await prepare();
      final planned = (await week(0)).fold<int>(0, (a, u) => a + u.minutes);
      await addRun(monday(1), planned);
      final v = await opened();
      expect(v?.reason, 'repeatWeek');
    });

    test('RPE-Fenster: alte Bewertung ohne lockeren Lauf in der bewerteten '
        'Woche löst nicht erneut aus', () async {
      await prepare();
      // Vorwoche: lockere Läufe mit RPE 8 (zählten damals).
      await runWeek(-1, rpeOf: (u, i) => easy(u) ? 8 : 3);
      // Bewertete Woche: voll gelaufen, aber nur freie Läufe (keiner
      // einer lockeren Einheit zugeordnet).
      for (final u in await week(0)) {
        await addRun(u.day, u.minutes);
      }
      expect(await opened(), isNull);
    });
  });

  group('Geh-Lauf wiederholen: Annahme am Donnerstag', () {
    test('die Abfolge beginnt heute, frühere Läufe bleiben und zählen nicht '
        'als Lauf 2 und 3', () async {
      final e = await _Env.open();
      final monday = _day(-2); // 9.11.
      final thursday = _day(1); // 12.11.
      final ids = [
        for (final ago in [3, 1]) await _finishedRun(e.session, ago),
      ];
      for (final id in ids) {
        await e.session.subjective.save(id, RunSubjective(rpe: 7));
      }
      await e.goals.save(_goal(), today: monday);
      final start = const WalkRunPosition(4);
      await e.plans.writeVersion(
        PlanVersionDraft(
          createdAt: monday,
          validFrom: monday,
          trigger: PlanTrigger.create,
          reason: 'create',
          version: const PlanVersion(),
          inputs: PlanInputs.forNewGoal(_goal(), monday).copyWith(
            walkRunStart: start,
            walkRunFrom: monday,
            walkRunWeeks: 8,
            startWeeklyMinutes: 90,
          ),
          summary: const {},
          units: [
            for (final d in [monday, _day(0), _day(2)])
              PlanUnit(
                day: d,
                kind: PlanUnitKind.walkRun,
                phase: PlanPhase.build,
                weekIndex: 4,
                minutes: 30,
                segments: const [],
              ),
          ],
          readState: planUnitsFingerprint(const []),
        ),
      );
      final units = await e.plans.unitsBetween(monday, _day(2));
      await e.plans.assignRun(units[0].id!, ids[0], expectedRunId: null);
      await e.plans.assignRun(units[1].id!, ids[1], expectedRunId: null);

      e.clock.set(localAt(thursday, 12));
      await e.controller.open();
      final proposal = e.controller.state.walkRunProposal;
      expect(proposal?.suggestion.position, const WalkRunPosition(4, 1));

      final opened = (await e.plans.history()).length;
      final oldCheck = _dayText(_day(-30));
      await e.session.settings.set(planLastCheckDayKey, oldCheck, at: _now);
      await e.controller.acceptWalkRunRepeat();
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        oldCheck,
        reason: 'Annehmen bewertet die Woche nicht: Prüftag bleibt',
      );
      final h = await e.plans.history();
      expect(h, hasLength(opened + 1));
      expect(h.last.inputs.walkRunFrom, thursday);
      expect(h.last.inputs.walkRunStart, const WalkRunPosition(4, 1));
      // Mo und Mi bleiben, ab Donnerstag kommen die Läufe 2 und 3.
      final all = await e.plans.unitsBetween(monday, _day(8));
      final days = [for (final u in all) u.day];
      expect(days.take(2), [monday, _day(0)]);
      expect(days.skip(2).every((d) => !d.isBefore(thursday)), isTrue);
      expect(days.length, greaterThanOrEqualTo(4));
      // Kein sofortiger neuer Vorschlag: die früheren Läufe zählen nicht.
      expect(e.controller.state.walkRunProposal, isNull);
    });
  });

  group('Öffnen: Pausenregel vor Wochenprüfung', () {
    Future<_Env> prepared(int pauseDays, {bool recorded = true}) async {
      final e = await _Env.open();
      e.clock.set(localAt(_day(-80)));
      await e.controller.saveGoal(_goal());
      e.clock.set(_now);
      await _finishedRun(e.session, pauseDays);
      // Basiswoche vor der Pause (volle Kalenderwoche, 2 Läufe zu 60 min).
      await _finishedRun(e.session, pauseDays + 7);
      await _finishedRun(e.session, pauseDays + 8);
      if (recorded) {
        await LoadSettings.saveAllRecorded(e.session.settings, true, at: _now);
      }
      // Wochenprüfung fällig (frühere Kalenderwoche), diese Woche ohne Läufe.
      await e.session.settings.set(planLastCheckDayKey, '2026-11-02', at: _now);
      return e;
    }

    test(
      'Pause 10 Tage: genau eine Fassung (pause), 80 % der Basiswoche, '
      'keine harte Einheit; die Wochenprüfung schreibt keine zweite',
      () async {
        final e = await prepared(10);
        final before = (await e.plans.history()).length;
        final q = await HintService(
          session: e.session,
          clock: e.clock,
        ).pauseRestartDue();
        expect(q, isNotNull);
        expect(q!.baseWeekMinutes, greaterThan(0));
        await e.controller.open();
        final h = await e.plans.history();
        expect(h.length, before + 1);
        expect(h.last.trigger, PlanTrigger.pause);
        expect(h.last.inputs.noHardUntil, isNotNull);
        expect(
          h.last.inputs.startWeeklyMinutes,
          (q.baseWeekMinutes * 0.8).round(),
        );
        expect(h.last.inputs.anchor, DateTime.utc(2026, 11, 9));
        // Zweites Öffnen: weiterhin nichts Neues.
        await e.controller.open();
        expect((await e.plans.history()).length, before + 1);
      },
    );

    test('offene Pausenfrage: Öffnen rechnet keine Wochenprüfung; nach „Ja“ '
        'gilt die Pausenregel, danach nichts Neues', () async {
      final e = await prepared(10, recorded: false);
      final before = (await e.plans.history()).length;
      final service = HintService(session: e.session, clock: e.clock);
      final q = await service.pauseQuestion();
      expect(q, isNotNull);
      await e.controller.open();
      expect((await e.plans.history()).length, before);
      expect(await service.pauseQuestion(), isNotNull);
      expect(await e.controller.answerPause(true), PlanActionResult.done);
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.pause);
      expect(
        h.last.inputs.startWeeklyMinutes,
        (q!.baseWeekMinutes * 0.8).round(),
      );
      expect(h.last.inputs.noHardUntil, isNotNull);
      await e.controller.open();
      expect((await e.plans.history()).length, before + 1);
    });

    test('offene Pausenfrage: keine Nachfrage (PAR-200), nach der Antwort '
        'wieder fällig', () async {
      final e = await prepared(10, recorded: false);
      // Die Anlage liegt 80 Tage zurück: die Nachfrage wäre fällig.
      await e.controller.open();
      expect(e.controller.state.feedbackDue, isFalse);
      await e.controller.answerPause(true);
      await e.controller.open();
      expect(e.controller.state.feedbackDue, isTrue);
    });

    test('Rückmeldung am Mittwoch, Pausenfrage am Donnerstag: Neustart mit '
        'Anker dieser Montag (F2, PAR-202)', () async {
      final e = await prepared(6, recorded: false);
      await e.controller.open();
      expect(
        await HintService(session: e.session, clock: e.clock).pauseQuestion(),
        isNull,
      );
      expect(e.controller.state.feedbackDue, isTrue);
      final out = await e.controller.answerFeedback(PlanFeedback.tooEasy);
      expect(out.result, PlanActionResult.done);
      final fb = (await e.plans.history()).last;
      expect(fb.trigger, PlanTrigger.feedback);
      expect(fb.inputs.anchor.isAfter(DateTime.utc(2026, 11, 9)), isTrue);
      // Einen Tag später steht die Pause (7 Tage) fest und die Frage ist offen.
      e.clock.set(_now.add(const Duration(days: 1)));
      expect(
        await HintService(session: e.session, clock: e.clock).pauseQuestion(),
        isNotNull,
      );
      expect(await e.controller.answerPause(true), PlanActionResult.done);
      final h = (await e.plans.history()).last;
      expect(h.trigger, PlanTrigger.pause);
      expect(h.inputs.anchor, DateTime.utc(2026, 11, 9));
      expect(h.inputs.noHardUntil, isNotNull);
    });

    test('„zu leicht“, dann Pause ab pauseMinDays: die Pause startet höchstens mit der '
        'Woche, die vor der Rückmeldung galt', () async {
      final e = await prepared(6, recorded: false);
      await e.controller.open();
      expect(e.controller.state.feedbackDue, isTrue);
      expect(
        (await e.controller.answerFeedback(PlanFeedback.tooEasy)).result,
        PlanActionResult.done,
      );
      final history = await e.plans.history();
      final monday = DateTime.utc(2026, 11, 9);
      int weekMinutes(PlanInputs i) {
        // Wie die Pausenregel: ein späterer Anker gilt ab diesem Montag.
        final from = i.anchor.isAfter(monday) ? i.copyWith(anchor: monday) : i;
        final s = planCourseSetup(_goal(), from);
        return s
            .course(today: monday)
            .weeks
            .firstWhere((w) => w.start == monday)
            .minutes!;
      }

      // Einen Tag später steht die Pause fest.
      e.clock.set(_now.add(const Duration(days: 1)));
      expect(await e.controller.answerPause(true), PlanActionResult.done);
      final h = (await e.plans.history()).last;
      expect(h.trigger, PlanTrigger.pause);
      final shown = weekMinutes(history[history.length - 2].inputs);
      final raised = weekMinutes(history.last.inputs);
      // Die Rückmeldung hat die Woche angehoben, sonst prüft der Test nichts.
      expect(raised, greaterThan(shown));
      expect(h.inputs.startWeeklyMinutes, lessThanOrEqualTo(shown));
    });

    test('Rückmeldung wird bei offener Pausenfrage nicht angenommen (Karte '
        'über Mitternacht offen)', () async {
      final e = await prepared(6, recorded: false);
      await e.controller.open();
      final before = (await e.plans.history()).length;
      e.clock.set(_now.add(const Duration(days: 1)));
      expect(
        await HintService(session: e.session, clock: e.clock).pauseQuestion(),
        isNotNull,
      );
      final out = await e.controller.answerFeedback(PlanFeedback.tooEasy);
      expect(out.result, PlanActionResult.rejected);
      expect((await e.plans.history()).length, before);
    });

    test('Ziel speichern am Prüftag bei offener Pausenfrage, dann „Ja“ -> '
        'Fassung pause, 80 % der Basiswoche, noHardUntil', () async {
      final e = await prepared(10, recorded: false);
      final service = HintService(session: e.session, clock: e.clock);
      final q = await service.pauseQuestion();
      expect(q, isNotNull);
      await e.controller.saveGoal(_goal(target: DateTime.utc(2027, 5, 1)));
      expect(await service.pauseQuestion(), isNotNull);
      expect(await e.controller.answerPause(true), PlanActionResult.done);
      final last = (await e.plans.history()).last;
      expect(last.trigger, PlanTrigger.pause);
      expect(
        last.inputs.startWeeklyMinutes,
        (q!.baseWeekMinutes * 0.8).round(),
      );
      expect(last.inputs.noHardUntil, isNotNull);
    });

    test('Ziel speichern bei offener Pausenfrage, dann „Nein“ -> '
        'Wochenprüfung greift beim nächsten Öffnen', () async {
      final e = await prepared(10, recorded: false);
      final service = HintService(session: e.session, clock: e.clock);
      expect(await service.pauseQuestion(), isNotNull);
      await e.controller.saveGoal(_goal(target: DateTime.utc(2027, 5, 1)));
      expect(await service.pauseQuestion(), isNotNull);
      final before = (await e.plans.history()).length;
      await e.controller.answerPause(false);
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.weekly);
    });

    test('offene Pausenfrage, Antwort „Nein“: die nächste Wochenprüfung läuft '
        'normal', () async {
      final e = await prepared(10, recorded: false);
      final before = (await e.plans.history()).length;
      await e.controller.open();
      expect((await e.plans.history()).length, before);
      await e.controller.answerPause(false);
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.weekly);
    });

    test('ohne Pause greift die Wochenprüfung wie bisher', () async {
      final e = await prepared(2);
      final before = (await e.plans.history()).length;
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.weekly);
    });
  });

  group('Neuer Einstieg: Neustart möglich', () {
    Future<bool> possible(DateTime target) async {
      final e = await _Env.open();
      e.clock.set(localAt(_day(-80)));
      expect(
        await e.controller.saveGoal(_goal(target: target)),
        PlanActionResult.done,
      );
      e.clock.set(_now);
      await _finishedRun(e.session, 70);
      await LoadSettings.saveAllRecorded(e.session.settings, true, at: _now);
      return e.controller.newStartPossible();
    }

    test(
      'ja bei langer Pause und weitem Termin, nein kurz vor dem Termin',
      () async {
        expect(await possible(DateTime.utc(2027, 6, 1)), isTrue);
        expect(await possible(DateTime.utc(2026, 11, 14)), isFalse);
      },
    );

    test('nein ohne anstehenden Einstieg (keine lange Pause)', () async {
      final e = await _Env.open();
      e.clock.set(localAt(_day(-80)));
      await e.controller.saveGoal(_goal());
      e.clock.set(_now);
      await _finishedRun(e.session, 20);
      await LoadSettings.saveAllRecorded(e.session.settings, true, at: _now);
      expect(await e.controller.newStartPossible(), isFalse);
    });

    test('Einschätzung des neuen Einstiegs rechnet mit dem neuen Stand, auch '
        'nach der vorläufigen Vorgabe', () async {
      final e = await _Env.open();
      e.clock.set(localAt(_day(-80)));
      await e.controller.saveGoal(_goal());
      e.clock.set(_now);
      await _finishedRun(e.session, 70);
      await LoadSettings.saveAllRecorded(e.session.settings, true, at: _now);
      // Die wöchentliche Prüfung gilt als erledigt (sonst käme ihre Fassung
      // mit dem Anker dieser Woche zuerst und der Neustart entfiele).
      await e.session.settings.set(planLastCheckDayKey, '2026-11-11', at: _now);
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.map((r) => r.trigger), contains(PlanTrigger.pause));
      // Neuer Stand: nicht 30 min am Stück -> Geh-Lauf-Abfolge im Neustart.
      final draft = TrainingGoal(
        type: GoalType.distance,
        distance: GoalDistance.tenKilometers,
        targetDate: DateTime.utc(2027, 6, 1),
        runDays: const {2, 4, 6},
        maxSessionSeconds: 7200,
        weeklyCapSeconds: 240 * 60.0,
        createdAt: DateTime.utc(2026, 11, 1),
        hardSessionEnabled: true,
        canRun30: ContinuousRun30.no,
      );
      final check = await e.controller.checkGoal(draft, newStart: true);
      expect(check.walkRun, isTrue);
    });
  });

  group('Öffnen: Warnsignal-Zeile und Plan stimmen überein', () {
    /// Plan angelegt und geprüft (Prüftag heute: die Wochenprüfung ist nicht
    /// fällig, nur die Übereinstimmung kann hier neu rechnen).
    Future<_Env> opened() async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      await e.controller.open();
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_today),
      );
      return e;
    }

    WarningStore warningOf(_Env e) => (e.session as WarningStorage).warning;

    test('Öffnen mit Signal ohne passende Fassung zeigt das Warnsignal vor '
        'der Neuberechnung (Heute und Plan)', () async {
      final e = await opened();
      await warningOf(
        e,
      ).set(WarningSignal(reportedOn: _day(-7), source: WarningSource.manual));
      final gate = Completer<List<RunFigures>>();
      final reopened = _Env(e.session, loadRuns: () => gate.future);
      final versions = (await e.plans.history()).length;
      final opening = reopened.controller.open();
      while (reopened.controller.state.warning == null) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(reopened.controller.state.warningReminderDue, isTrue);
      expect(gate.isCompleted, isFalse);
      expect(await e.plans.history(), hasLength(versions));
      gate.complete(const []);
      await opening;
      expect((await e.plans.history()).last.reason, planReasonWarning);
      expect(reopened.controller.state.warning, isNotNull);
    });

    test('Nachholen unter gespeichertem Signal: warningRecalculating, '
        'solange die Rechnung läuft; danach die Ruhetag-Fassung', () async {
      final e = await opened();
      await warningOf(e)
          .set(WarningSignal(reportedOn: _today, source: WarningSource.manual));
      final gate = Completer<List<RunFigures>>();
      final reopened = _Env(e.session, loadRuns: () => gate.future);
      expect(reopened.controller.warningRecalculating, isFalse);
      final opening = reopened.controller.open();
      while (reopened.controller.state.warning == null) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(reopened.controller.warningRecalculating, isTrue);
      expect(gate.isCompleted, isFalse);
      gate.complete(const []);
      await opening;
      expect(reopened.controller.warningRecalculating, isFalse);
      final last = (await e.plans.history()).last;
      expect(last.reason, planReasonWarning);
      expect(warningHeldFromSummary(last.summary), isNotNull);
      // Die Seite hat die Ruhetag-Fassung geladen.
      final loaded = reopened.controller.state.version!;
      expect(loaded.id, last.id);
      expect(loaded.reason, planReasonWarning);
      final week = reopened.controller.state.weekUnits
          .where((u) => !u.day.isBefore(_today))
          .toList();
      expect(week.every((u) => u.kind == PlanUnitKind.rest), isTrue);
    });

    test('Nachholen unter gespeichertem Signal scheitert: '
        'warningRecalculating danach false, Signal bleibt', () async {
      final e = await opened();
      await warningOf(e)
          .set(WarningSignal(reportedOn: _today, source: WarningSource.manual));
      final versions = (await e.plans.history()).length;
      final reopened = _Env(
        e.session,
        loadRuns: () async => throw StateError('Lesefehler'),
      );
      await reopened.controller.open();
      expect(reopened.controller.warningRecalculating, isFalse);
      expect(await warningOf(e).read(), isNotNull);
      expect(await e.plans.history(), hasLength(versions));
      expect(reopened.controller.state.warning, isNotNull);
    });

    test(
      'Nachholen nach aufgehobenem Signal: keine Fortschrittsanzeige',
      () async {
        final e = await opened();
        await e.controller.reportWarning();
        await warningOf(e).lift(); // Schreiben der Fassung scheiterte
        final gate = Completer<List<RunFigures>>();
        final reopened = _Env(e.session, loadRuns: () => gate.future);
        final seen = <bool>[];
        reopened.controller.addListener(
          () => seen.add(reopened.controller.warningRecalculating),
        );
        final opening = reopened.controller.open();
        while (seen.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(reopened.controller.warningRecalculating, isFalse);
        gate.complete(const []);
        await opening;
        expect(seen, everyElement(isFalse));
        expect((await e.plans.history()).last.reason, planReasonWarningLifted);
      },
    );
  });

  group('Zieldatum gegen den Ortstag (FR-0136), auch westlich von UTC', () {
    /// Lokaler Kalendertag (lokale Mitternacht) [days] Tage nach dem Ortstag
    /// der Uhr, so wie ihn Formular und Speicher liefern.
    DateTime localDay(_Env e, int days) {
      final l = e.clock.now().toLocal();
      return DateTime(l.year, l.month, l.day + days);
    }

    test('saveGoal: gestern abgelehnt, heute angenommen', () async {
      final e = await _Env.open();
      expect(
        await e.controller.saveGoal(_goal(target: localDay(e, -1))),
        PlanActionResult.rejected,
      );
      expect(await e.goals.goal(), isNull);
      expect(
        await e.controller.saveGoal(_goal(target: localDay(e, 0))),
        PlanActionResult.done,
      );
      expect((await e.goals.goal())!.targetDate, localDay(e, 0));
    });

    /// Lange Pause mit anstehendem neuem Einstieg (PAR-181).
    Future<_Env> pausing() async {
      final e = await _Env.open();
      e.clock.set(localAt(_day(-80)));
      await e.controller.saveGoal(_goal());
      e.clock.set(_now);
      await _finishedRun(e.session, 70);
      await LoadSettings.saveAllRecorded(e.session.settings, true, at: _now);
      expect(await e.controller.newStartPossible(), isTrue);
      return e;
    }

    test(
      'restartAfterLongPause: gestern abgelehnt, heute angenommen',
      () async {
        final past = await pausing();
        final before = await past.goals.goal();
        expect(
          await past.controller.restartAfterLongPause(
            _goal(target: localDay(past, -1)),
          ),
          PlanActionResult.rejected,
        );
        expect((await past.goals.goal())!.targetDate, before!.targetDate);
        final ok = await pausing();
        expect(
          await ok.controller.restartAfterLongPause(
            _goal(target: localDay(ok, 0)),
          ),
          isNot(PlanActionResult.rejected),
        );
        expect((await ok.goals.goal())!.targetDate, localDay(ok, 0));
      },
    );
  });

  group('PAR-231: Läufe zählen automatisch für die offene Einheit', () {
    /// Beendeter Lauf, der am Tag [d] um [h]:[m] Ortszeit beginnt und
    /// [minutes] dauert (Versatz der Prozesszone).
    Future<int> runAt(
      StorageSession s,
      DateTime d,
      int h,
      int m, {
      int minutes = 40,
    }) async {
      final start = localAt(d, h, m);
      final end = start.add(Duration(minutes: minutes));
      final r = await s.runs.create(startedAt: start);
      await s.runs.setState(
        r.id,
        RunState.finished,
        endedAt: end,
        endedUtcOffset: end.timeZoneOffset,
      );
      return r.id;
    }

    Future<Map<int, int?>> assigned(_Env e) async => {
      for (final u in await e.plans.unitsBetween(
        DateTime.utc(2000),
        planFarFuture,
      ))
        if (u.runId != null) u.id!: u.runId,
    };

    test('Lauf um 17:30, Plan um 19:00 desselben Tags: die heutige Einheit '
        'ist erledigt (FR-0156)', () async {
      final e = await _Env.open();
      final run = await runAt(e.session, _today, 17, 30);
      e.clock.set(localAt(_today, 19));
      expect(
        await e.controller.saveGoal(_goal(days: {1, 3, 5})),
        PlanActionResult.done,
      );
      final unit = await e.controller.unitOn(_today);
      expect(unit, isNotNull);
      expect(unit!.runId, run);
    });

    test('Lauf gestern, Plan heute: keine Einheit gestern, nichts '
        'zugeordnet', () async {
      final e = await _Env.open();
      await runAt(e.session, _day(-1), 17, 30);
      await e.controller.saveGoal(_goal(days: {2, 3, 5}));
      expect(await e.controller.unitOn(_day(-1)), isNull);
      expect(await assigned(e), isEmpty);
      expect((await e.plans.history()).map((v) => v.trigger), [
        PlanTrigger.create,
      ]);
    });

    test('Idempotenz: Plan und App erneut öffnen ändert nichts und rechnet '
        'nicht noch einmal', () async {
      final e = await _Env.open();
      final run = await runAt(e.session, _today, 7, 0);
      await e.controller.saveGoal(_goal(days: {1, 3, 5}));
      final before = await assigned(e);
      final versions = (await e.plans.history()).length;
      expect(before.values, [run]);
      await e.controller.open();
      await e.controller.open();
      // Neuer Controller wie nach einem Neustart der App.
      final again = PlanController(
        session: e.session,
        clock: e.clock,
        reader: e.reader,
      );
      await again.open();
      again.dispose();
      expect(await assigned(e), before);
      expect((await e.plans.history()).length, versions);
    });

    test('Öffnen ordnet einen Lauf der Woche nachträglich zu', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal(days: {1, 3, 5}));
      expect(await assigned(e), isEmpty);
      final run = await runAt(e.session, _today, 7, 0);
      await e.controller.open();
      expect((await e.controller.unitOn(_today))!.runId, run);
    });

    test('Verschobene Einheit: Lauf am neuen Tag zählt, die Einheit am '
        'alten Tag bleibt ohne Lauf', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal());
      expect(await e.controller.unitOn(_today), isNull);
      final run = await runAt(e.session, _today, 7, 0);
      await e.controller.open();
      expect(await assigned(e), isEmpty);
      final tomorrow = (await e.controller.unitOn(_day(1)))!;
      expect(
        await e.controller.confirmMove(tomorrow.id!, _today),
        PlanActionResult.done,
      );
      final moved = (await e.controller.unitOn(_today))!;
      expect(moved.kind, tomorrow.kind);
      expect(moved.runId, run);
      expect((await e.controller.unitOn(_day(1)))?.runId, isNull);
      expect((await assigned(e)).values, [run]);
    });

    test('Bestehende Zuordnung bleibt, auch wenn später ein längerer Lauf '
        'folgt', () async {
      final e = await _Env.open();
      await e.controller.saveGoal(_goal(days: {1, 3, 5}));
      final short = await runAt(e.session, _today, 6, 0, minutes: 20);
      final unit = (await e.controller.unitOn(_today))!;
      expect(
        await e.controller.assignRun(unit.id!, short),
        PlanActionResult.done,
      );
      await runAt(e.session, _today, 10, 0, minutes: 90);
      await e.controller.open();
      expect((await e.controller.unitOn(_today))!.runId, short);
      expect((await assigned(e)).values, [short]);
    });

    test('Zwei Läufe am Tag der Einheit: der längere zählt', () async {
      final e = await _Env.open();
      await runAt(e.session, _today, 6, 0, minutes: 20);
      final long = await runAt(e.session, _today, 9, 0, minutes: 50);
      await e.controller.saveGoal(_goal(days: {1, 3, 5}));
      expect((await e.controller.unitOn(_today))!.runId, long);
    });

    test(
      'Ein Lauf seit „Einheit starten“ bleibt dem Merker überlassen',
      () async {
        final e = await _Env.open();
        await e.controller.saveGoal(_goal(days: {1, 3, 5}));
        final unit = (await e.controller.unitOn(_today))!;
        e.clock.set(localAt(_today, 13));
        await PlanStartedUnitStore(
          session: e.session,
          clock: e.clock,
        ).remember(unit.id!, _dayText(_today));
        await runAt(e.session, _today, 13, 1);
        await e.controller.open();
        expect((await e.controller.unitOn(_today))!.runId, isNull);
      },
    );

    test(
      'Lauf Sonntag 23:50 bis Montag 00:20: die Einheit vom Sonntag '
      'trägt den Lauf, auch wenn die Zuordnung erst am Montag läuft',
      () async {
        final e = await _Env.open();
        final sunday = _day(4);
        expect(sunday.weekday, DateTime.sunday);
        await e.controller.saveGoal(_goal(days: {3, 5, 7}));
        expect((await e.controller.unitOn(sunday))?.runId, isNull);
        final run = await runAt(e.session, sunday, 23, 50, minutes: 30);
        // Uhr am Montag kurz nach Mitternacht: die Woche beginnt heute, der
        // Starttag des Laufs liegt davor.
        e.clock.set(localAt(_day(5), 0, 25));
        expect(
          await e.controller.autoAssignRuns(since: sunday),
          PlanActionResult.done,
        );
        expect((await e.controller.unitOn(sunday))!.runId, run);
        expect((await e.controller.unitOn(_day(5)))?.runId, isNull);
      },
    );

    group('Öffnen holt ab dem Sonntag der Vorwoche nach (PAR-231)', () {
      final sunday = _day(4);
      final monday = _day(5);

      /// Plan mit Einheiten am Mittwoch, Samstag und Sonntag; noch kein Lauf.
      Future<_Env> planned() async {
        expect(sunday.weekday, DateTime.sunday);
        final e = await _Env.open();
        expect(
          await e.controller.saveGoal(_goal(days: {3, 6, 7})),
          PlanActionResult.done,
        );
        expect((await e.controller.unitOn(sunday))?.runId, isNull);
        expect(await assigned(e), isEmpty);
        return e;
      }

      test('Lauf Sonntag 23:50 bis Montag 00:20 ohne Zuordnung nach dem '
          'Lauf: Öffnen am Montag 00:25 ordnet ihn der Einheit vom Sonntag '
          'zu, nicht der vom Montag', () async {
        final e = await planned();
        final run = await runAt(e.session, sunday, 23, 50, minutes: 30);
        e.clock.set(localAt(monday, 0, 25));
        await e.controller.open();
        expect((await e.controller.unitOn(sunday))!.runId, run);
        expect((await e.controller.unitOn(monday))?.runId, isNull);
        expect((await assigned(e)).values, [run]);
      });

      test('Lauf Sonntag 18:00 bis 18:40, Öffnen erst am Dienstag: '
          'zugeordnet', () async {
        final e = await planned();
        final run = await runAt(e.session, sunday, 18, 0);
        e.clock.set(localAt(_day(6), 9));
        await e.controller.open();
        expect((await e.controller.unitOn(sunday))!.runId, run);
        expect((await assigned(e)).values, [run]);
      });

      test('Lauf am Samstag der Vorwoche, Öffnen am Montag: außerhalb des '
          'Fensters, die Einheit bleibt offen', () async {
        final e = await planned();
        final saturday = _day(3);
        expect(saturday.weekday, DateTime.saturday);
        final unit = (await e.controller.unitOn(saturday))!;
        expect(unit.kind, isNot(PlanUnitKind.rest));
        await runAt(e.session, saturday, 9, 0);
        e.clock.set(localAt(monday, 9));
        await e.controller.open();
        final after = (await e.controller.unitOn(saturday))!;
        expect(after.kind, unit.kind);
        expect(after.runId, isNull);
        expect(await assigned(e), isEmpty);
      });

      test('Lauf am Samstag der Vorwoche, Zuordnung am Montag mit dem '
          'Starttag des Laufs: die Einheit vom Samstag trägt den Lauf; ohne '
          'Starttag bleibt sie offen', () async {
        final saturday = _day(3);
        expect(saturday.weekday, DateTime.saturday);

        // Gegenprobe: ohne Starttag beginnt das Fenster am Sonntag.
        final plain = await planned();
        final unit = (await plain.controller.unitOn(saturday))!;
        expect(unit.kind, isNot(PlanUnitKind.rest));
        await runAt(plain.session, saturday, 9, 0);
        plain.clock.set(localAt(monday, 9));
        expect(await plain.controller.autoAssignRuns(), PlanActionResult.done);
        expect((await plain.controller.unitOn(saturday))!.runId, isNull);
        expect(await assigned(plain), isEmpty);

        // Mit dem Starttag des Laufs (Samstag) reicht das Fenster zurück.
        final e = await planned();
        final run = await runAt(e.session, saturday, 9, 0);
        e.clock.set(localAt(monday, 9));
        expect(
          await e.controller.autoAssignRuns(since: saturday),
          PlanActionResult.done,
        );
        final after = (await e.controller.unitOn(saturday))!;
        expect(after.kind, unit.kind);
        expect(after.runId, run);
        expect((await assigned(e)).values, [run]);
      });

      test('Starttag nach dem Sonntag der Vorwoche (Montag): das Fenster '
          'beginnt weiter am Sonntag, der Lauf vom Sonntag wird '
          'zugeordnet', () async {
        final e = await planned();
        final run = await runAt(e.session, sunday, 18, 0);
        e.clock.set(localAt(monday, 9));
        expect(
          await e.controller.autoAssignRuns(since: monday),
          PlanActionResult.done,
        );
        expect((await e.controller.unitOn(sunday))!.runId, run);
        expect((await assigned(e)).values, [run]);
      });

      test('Idempotenz: erneutes Öffnen ordnet nichts weiter zu und schreibt '
          'keine weitere Fassung', () async {
        final e = await planned();
        final run = await runAt(e.session, sunday, 23, 50, minutes: 30);
        e.clock.set(localAt(monday, 0, 25));
        await e.controller.open();
        final before = await assigned(e);
        final versions = (await e.plans.history()).length;
        expect(before.values, [run]);
        expect((await e.plans.history()).last.trigger, PlanTrigger.run);
        await e.controller.open();
        final again = PlanController(
          session: e.session,
          clock: e.clock,
          reader: e.reader,
        );
        await again.open();
        again.dispose();
        expect(await assigned(e), before);
        expect((await e.plans.history()).length, versions);
      });

      test('Zuordnung über „Einheit starten“ am Sonntag bleibt, auch mit '
          'einem längeren freien Lauf am Sonntag', () async {
        final e = await planned();
        final unit = (await e.controller.unitOn(sunday))!;
        e.clock.set(localAt(sunday, 8));
        final store = PlanStartedUnitStore(session: e.session, clock: e.clock);
        await store.remember(unit.id!, _dayText(sunday));
        final short = await runAt(e.session, sunday, 8, 1, minutes: 20);
        expect(
          await store.settle(serialize: (action) => action()),
          PlanActionResult.done,
        );
        expect((await e.controller.unitOn(sunday))!.runId, short);
        final long = await runAt(e.session, sunday, 18, 0, minutes: 90);
        e.clock.set(localAt(monday, 9));
        await e.controller.open();
        expect((await e.controller.unitOn(sunday))!.runId, short);
        expect((await assigned(e)).values, [short]);
        expect((await assigned(e)).values, isNot(contains(long)));
      });
    });

    test('Lauf über Mitternacht am Starttag beendet die lange Pause', () async {
      // Lange Pause (PAR-181) mit anstehendem neuem Einstieg.
      final e = await _Env.open();
      e.clock.set(localAt(_day(-80)));
      await e.controller.saveGoal(_goal());
      e.clock.set(_now);
      await _finishedRun(e.session, 70);
      await LoadSettings.saveAllRecorded(e.session.settings, true, at: _now);
      expect(await e.controller.newStartPossible(), isTrue);
      // Ein Lauf, der heute nach Ortszeit des Laufs (UTC+14) um 22:00
      // beginnt und nach Mitternacht endet, zählt am Starttag (PAR-237):
      // Die Pause endet heute, ein Neustart steht nicht mehr an.
      final start = _today.add(const Duration(hours: 8));
      final r = await e.session.runs.create(startedAt: start);
      await e.session.runs.setState(
        r.id,
        RunState.finished,
        endedAt: start.add(const Duration(hours: 3)),
        endedUtcOffset: const Duration(hours: 14),
      );
      expect(await e.controller.newStartPossible(), isFalse);
    });
  });
}
