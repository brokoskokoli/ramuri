import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags (Ortstag in Europa derselbe).
final _now = DateTime.utc(2026, 11, 11, 12);
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
  }) : clock = FakeClock(_now) {
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
      e.clock.set(easy.day.add(const Duration(days: 1, hours: 12)));
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
      e.clock.set(second.day.add(const Duration(days: 1, hours: 12)));
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
        'Hinweis weg, Prüftag gesetzt (NB6 1)', () async {
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
        'Einheiten bleiben gehalten (NB6 1)', () async {
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

    test('fällig und aktuelle Regelversion: Auslöser weekly', () async {
      final e = await withOld(
        PlanVersion.current,
        lastCheck: _dayText(_day(-7)),
      );
      await e.controller.open();
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.trigger, PlanTrigger.weekly);
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

    test('weeklyCheckDue nach Kalenderwoche', () {
      expect(weeklyCheckDue(null, _today), isTrue);
      expect(weeklyCheckDue('kaputt', _today), isTrue);
      expect(weeklyCheckDue('2026-11-09', _today), isFalse); // Montag
      expect(weeklyCheckDue('2026-11-08', _today), isTrue); // Sonntag davor
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
        await e.plans.assignRun(units[i].id!, ids[i]);
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

  group('Nachbesserung 1', () {
    test('Warteschlange: assignRun wartet, bis die laufende Neuberechnung '
        'ihre Fassung geschrieben hat', () async {
      Completer<void>? gate;
      var reads = 0;
      PlanUnit? seenBySecondRead;
      late _Env e;
      e = await _Env.open(
        loadRuns: () async {
          reads++;
          if (reads == 2) {
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
      expect(reads, 2);
      // assignRun lief erst nach dem Abschluss der Neuberechnung (Prüftag
      // geschrieben) und hat dann zugeordnet.
      expect(seenBySecondRead?.runId, runId);
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_today),
      );
      expect((await e.plans.unitOn(unit.day))?.runId, runId);
    });

    test('wöchentliche Prüfung: Anker und Startwochenzeit bleiben aus der '
        'Vorfassung, auch wenn Läufe den Stand ändern', () async {
      // 12 Läufe zu 50 min in den letzten 6 Wochen: Stand aus Läufen 100 min.
      final runs = [
        for (var i = 0; i < 12; i++)
          RunFigures(
            runId: i + 1,
            endedAt: _day(-1 - 3 * i).add(const Duration(hours: 8)),
            day: _dayText(_day(-1 - 3 * i)),
            distanceMeters: 8000,
            movingTime: const Duration(minutes: 50),
            totalTime: const Duration(minutes: 50),
          ),
      ];
      final e = await _Env.open(runs: runs);
      await e.goals.save(_goal(), today: _goal().createdAt);
      await _writeVersion(e, PlanVersion.current, _day(-7));
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(_day(-7)),
        at: _now,
      );
      final before = (await e.plans.history()).last.inputs;
      final measured = await e.reader.read(goal: _goal(), today: _today);
      expect(measured.inputs.anchor, isNot(before.anchor));
      expect(
        measured.inputs.startWeeklyMinutes,
        isNot(before.startWeeklyMinutes),
      );

      await e.controller.open();
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.weekly);
      expect(h.last.inputs.anchor, before.anchor);
      expect(h.last.inputs.startWeeklyMinutes, before.startWeeklyMinutes);
      expect(h.last.inputs.today, _today);
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

  group('Nachbesserung 2', () {
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

  group('Wochenprüfung PAR-201 beim Öffnen (NB4 2)', () {
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
      e.clock.set(_day(-21));
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
      e.clock.set(_day(14));
      return (e, planned[0]);
    }

    test('Woche ohne Läufe: beim Öffnen neue Fassung, Wochenzeit nicht höher '
        '(wiederholen)', () async {
      final (e, planned) = await prepare();
      final before = await week(e, monday(1));
      expect(before, greaterThan(planned), reason: 'sonst belegt es nichts');
      await e.controller.open();
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.trigger, PlanTrigger.weekly);
      expect(h.last.reason, 'repeatWeek');
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
      // idempotent: zweites Öffnen schreibt nichts
      await e.controller.open();
      expect(await e.plans.history(), hasLength(2));
    });

    test('alte Regelversion: die Prüfung bewertet die Woche wie weekly '
        '(NB6 1)', () async {
      final (e, planned) = await prepare();
      await _downgradeLast(e);
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.ruleVersion);
      expect(h.last.reason, 'ruleVersion,repeatWeek');
      expect(h.last.version.isCurrent, isTrue);
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
    });

    test('Lauf zuordnen vor der Prüfung (Lauf über Mitternacht in den '
        'Montag): der Prüftag bleibt, das Öffnen bewertet die Woche '
        '(NB7 1)', () async {
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

    test('Warnsignal und fällige Wochenbewertung: nach dem Aufheben gilt die '
        'Anpassung (NB7 2)', () async {
      final (e, planned) = await prepare();
      // Gemeldet am Dienstag, geöffnet am Mittwoch derselben Woche: die
      // Wochenprüfung ist fällig, das Melden hat den Prüftag nicht gesetzt.
      e.clock.set(_day(13));
      await e.controller.reportWarning();
      e.clock.set(_day(14));
      await e.controller.open();
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_day(14)),
      );
      expect(
        (await e.plans.unitsBetween(
          _day(14),
          planFarFuture,
        )).every((u) => u.kind == PlanUnitKind.rest),
        isTrue,
      );
      await e.controller.liftWarning();
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
    });

    test('Warnsignal: wiederholtes Öffnen und Aufheben ohne Änderung der '
        'Eingaben schreibt keine weitere Fassung (NB7 2)', () async {
      final (e, _) = await prepare();
      // Gemeldet am Dienstag, geöffnet am Mittwoch derselben Woche: die
      // Wochenprüfung ist fällig, das Melden hat den Prüftag nicht gesetzt.
      e.clock.set(_day(13));
      await e.controller.reportWarning();
      e.clock.set(_day(14));
      await e.controller.open(); // Wochenbewertung: genau eine neue Fassung
      final n = (await e.plans.history()).length;
      await e.controller.open();
      await e.controller.open();
      await e.controller.recalculate();
      await e.controller.recalculate();
      expect((await e.plans.history()).length, n);
      // Neuer Tag ohne neue Woche: gemessene Werte allein ergeben nichts.
      e.clock.set(_day(15));
      await e.controller.open();
      expect((await e.plans.history()).length, n);
    });

    test('Hälfte bis 80 %: keine Steigerung', () async {
      final (e, planned) = await prepare(share: 0.65);
      final before = await week(e, monday(1));
      expect(before, greaterThan(planned), reason: 'sonst belegt es nichts');
      await e.controller.open();
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.reason, 'noIncrease');
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
    });

    test('mehr als 80 %: keine Änderung', () async {
      final (e, _) = await prepare(share: 0.9);
      await e.controller.open();
      final h = await e.plans.history();
      expect(h.length, 1);
    });
  });

  group('Wochenprüfung: Belege aus dem Speicher (NB7 4 bis 6)', () {
    // Plan seit Mittwoch 21.10.; bewertet wird die Woche 16.-22.11., geöffnet
    // wird Dienstag 24.11. (letzter Lauf höchstens 3 Tage her).
    DateTime monday(int n) =>
        DateTime.utc(2026, 11, 16).add(Duration(days: 7 * n));

    late _Env e;
    late List<RunFigures> runs;

    Future<void> prepare() async {
      runs = <RunFigures>[];
      e = await _Env.open(loadRuns: () async => runs);
      e.clock.set(_day(-21));
      await e.controller.saveGoal(_goal());
      e.clock.set(DateTime.utc(2026, 11, 24, 12));
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
      if (unit != null) await e.plans.assignRun(unit.id!, r.id);
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

    test('RPE: nur 1 von 3 lockeren Läufen mit RPE >= 6 -> keine Ermüdung '
        '(NB8 5)', () async {
      await prepare();
      var n = 0;
      await runWeek(0, rpeOf: (u, i) => easy(u) ? (n++ == 0 ? 7 : 4) : 3);
      expect(await opened(), isNull);
    });

    test(
      'Öffnen erst am Samstag: ein lockerer Lauf der laufenden Woche '
      'verdrängt die bewertete Woche nicht aus dem RPE-Fenster (NB8 5)',
      () async {
        await prepare();
        var n = 0;
        await runWeek(0, rpeOf: (u, i) => easy(u) ? (n++ < 2 ? 7 : 4) : 3);
        // Samstag der laufenden Woche; ein lockerer Lauf (RPE 3) am Dienstag.
        final current = (await week(1)).firstWhere(easy);
        await addRun(current.day, current.minutes, unit: current, rpe: 3);
        e.clock.set(DateTime.utc(2026, 11, 28, 12));
        final v = await opened();
        expect(v?.reason, 'fatigue');
      },
    );

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
        'Woche löst nicht erneut aus (NB7 5)', () async {
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

  group('Zieländerung am Prüftag (NB7 6)', () {
    test('goalChange am Montag bewertet die Vorwoche mit '
        '(Grund goalChange mit Gründen, NB8 6)', () async {
      final e = await _Env.open();
      e.clock.set(_day(-21));
      await e.controller.saveGoal(_goal());
      final mon1 = DateTime.utc(2026, 11, 23);
      // Montag der Folgewoche: Ziel geändert, Vorwoche ohne Läufe.
      e.clock.set(mon1.add(const Duration(hours: 12)));
      await e.controller.saveGoal(_goal(target: DateTime.utc(2027, 5, 1)));
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.goalChange);
      expect(h.last.reason, 'goalChange,repeatWeek');
      // Die Bewertung der Vorwoche (0 % geschafft) ist in die Fassung
      // eingegangen.
      expect(h.last.inputs.achievedShare, 0);
      expect(h.last.inputs.lastWeekMinutes, isNotNull);
    });
  });

  group('Geh-Lauf wiederholen: Annahme am Donnerstag (NB5 2)', () {
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
      await e.plans.assignRun(units[0].id!, ids[0]);
      await e.plans.assignRun(units[1].id!, ids[1]);

      e.clock.set(thursday.add(const Duration(hours: 12)));
      await e.controller.open();
      final proposal = e.controller.state.walkRunProposal;
      expect(proposal?.suggestion.position, const WalkRunPosition(4, 1));

      final opened = (await e.plans.history()).length;
      await e.controller.acceptWalkRunRepeat();
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

  group('Öffnen: Pausenregel vor Wochenprüfung (NB6)', () {
    Future<_Env> prepared(int pauseDays, {bool recorded = true}) async {
      final e = await _Env.open();
      e.clock.set(_day(-80));
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
        'gilt die Pausenregel, danach nichts Neues (NB7 2)', () async {
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

    test('Ziel speichern am Prüftag bei offener Pausenfrage, dann „Ja“ -> '
        'Fassung pause, 80 % der Basiswoche, noHardUntil (NB8 1)', () async {
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
        'Wochenprüfung greift beim nächsten Öffnen (NB9 1)', () async {
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
        'normal (NB7 2)', () async {
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

  group('Neuer Einstieg: Neustart möglich (NB5 5)', () {
    Future<bool> possible(DateTime target) async {
      final e = await _Env.open();
      e.clock.set(_day(-80));
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
      e.clock.set(_day(-80));
      await e.controller.saveGoal(_goal());
      e.clock.set(_now);
      await _finishedRun(e.session, 20);
      await LoadSettings.saveAllRecorded(e.session.settings, true, at: _now);
      expect(await e.controller.newStartPossible(), isFalse);
    });

    test('Einschätzung des neuen Einstiegs rechnet mit dem neuen Stand, auch '
        'nach der vorläufigen Vorgabe', () async {
      final e = await _Env.open();
      e.clock.set(_day(-80));
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

  group('Öffnen: Warnsignal-Zeile und Plan stimmen überein (NB11 2)', () {
    String sig(PlanUnit u) =>
        '${u.day}|${u.kind.name}|${u.minutes}|${u.pinned}|${u.fixed.name}';
    Future<List<String>> sigs(_Env e) async => [
      for (final u in await e.plans.unitsBetween(_day(0), planFarFuture))
        sig(u),
    ];

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

    test('Aufheben scheiterte nach dem Löschen der Zeile: das nächste Öffnen '
        'stellt den Plan her', () async {
      final e = await opened();
      final before = await sigs(e);
      await e.controller.reportWarning();
      expect(await sigs(e), isNot(before));
      await warningOf(e).lift(); // Schreiben der Fassung scheiterte
      final reopened = _Env(e.session);
      await reopened.controller.open();
      expect(await sigs(e), before);
      final last = (await e.plans.history()).last;
      expect(last.reason, planReasonWarningLifted);
      expect(last.trigger, PlanTrigger.feedback);
    });

    test('Rücknahme der Zeile in report scheiterte: das nächste Öffnen '
        'überlagert den Plan', () async {
      final e = await opened();
      final before = await sigs(e);
      await warningOf(e).set(
        WarningSignal(reportedOn: _today, source: WarningSource.manual),
      ); // Plan nicht geschrieben, Rücknahme scheiterte
      expect(await sigs(e), before);
      final reopened = _Env(e.session);
      await reopened.controller.open();
      final after = await e.plans.unitsBetween(_day(0), planFarFuture);
      expect(after.every((u) => u.kind == PlanUnitKind.rest), isTrue);
      final last = (await e.plans.history()).last;
      expect(last.reason, planReasonWarning);
      expect(warningHeldFromSummary(last.summary), isNotNull);
    });

    test('Heilung setzt den Prüftag nicht: eine fällige Wochenprüfung bleibt '
        'fällig', () async {
      final e = await opened();
      final lastCheck = _dayText(_day(-7));
      await e.session.settings.set(planLastCheckDayKey, lastCheck, at: _now);
      await warningOf(e)
          .set(WarningSignal(reportedOn: _today, source: WarningSource.manual));
      final reopened = _Env(e.session);
      await reopened.controller.open();
      expect(
        (await e.plans.history()).last.reason,
        planReasonWarning,
        reason: 'die Heilung hat neu gerechnet',
      );
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        lastCheck,
        reason: 'der Prüftag bleibt in der Vorwoche',
      );
    });
  });
}
