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
  _Env(this.session, {List<RunFigures> runs = const []})
    : clock = FakeClock(_now) {
    reader = PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => runs,
    );
    controller = PlanController(session: session, clock: clock, reader: reader);
  }
  final StorageSession session;
  final FakeClock clock;
  late final PlanDataReader reader;
  late final PlanController controller;
  PlanRepository get plans => (session as PlanStorage).plans;
  GoalStore get goals => (session as GoalStorage).goals;

  static Future<_Env> open({List<RunFigures> runs = const []}) async =>
      _Env(await FakeStorage().open(_key), runs: runs);
}

PlanUnit _unit(PlanUnitKind k, DateTime day) => PlanUnit(
  day: day,
  kind: k,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: 30,
  segments: const [],
);

/// Schreibt eine Fassung mit [version] ab [validFrom] und [units] direkt.
Future<void> _writeVersion(
  _Env e,
  PlanVersion version,
  DateTime validFrom, {
  List<PlanUnit> units = const [],
}) async {
  await e.plans.writeVersion(
    PlanVersionDraft(
      createdAt: validFrom,
      validFrom: validFrom,
      trigger: PlanTrigger.create,
      reason: 'create',
      version: version,
      inputs: PlanInputs.forNewGoal(_goal(), validFrom),
      summary: const {},
      units: units,
      readState: planUnitsFingerprint(
        await e.plans.unitsBetween(DateTime.utc(2000), planFarFuture),
      ),
    ),
  );
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
}
