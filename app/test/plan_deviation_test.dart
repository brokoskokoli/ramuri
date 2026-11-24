import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'helpers/local_clock.dart';

// Abweichung von der Einheit in der App (PAR-235, FR-0216): Der Controller
// gibt die Läufe der Woche an jede Neuberechnung weiter, die Begründung steht
// in der Fassung, bei „fix“ zeigt die Seite den Abstandshinweis (PAR-060).
// Synthetische Daten: Ziel, Plan und Läufe sind ausgedacht.

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i + 3));

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

String _sig(PlanUnit u) =>
    '${_iso(u.day)}|${u.kind.name}|${u.minutes}|${u.pinned}|${u.runId}';

class _Env {
  _Env(this.session, this.clock) {
    reader = PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => [...figures],
    );
    controller = PlanController(session: session, clock: clock, reader: reader);
  }

  final StorageSession session;
  final LocalFakeClock clock;
  final figures = <RunFigures>[];
  late final PlanDataReader reader;
  late final PlanController controller;
  PlanRepository get plans => (session as PlanStorage).plans;

  /// Plan ab Montag [_d0] mit 180 min Wochenzeit, Rechnung der Woche ab
  /// Tag 14 (Di locker, Mi progressiv, Fr locker, So lang); Schalter [mode],
  /// Uhr am Dienstag (Tag 15) abends, Wochenprüfung erledigt.
  static Future<_Env> open(PlanAdaptationMode mode) async {
    final session = await FakeStorage().open(_key);
    final e = _Env(session, LocalFakeClock(DateTime(2026, 12, 1, 20)));
    await (session as GoalStorage).goals.save(_goal(), today: _day(0));
    await recalculatePlan(
      plans: e.plans,
      settings: session.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: DateTime.utc(2026, 11, 16, 20),
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 180),
    );
    await SettingsPlanAdaptationStore(session.settings)
        .set(mode, at: DateTime.utc(2026, 11, 16, 20));
    await recalculatePlan(
      plans: e.plans,
      settings: session.settings,
      trigger: PlanTrigger.manual,
      today: _day(14),
      now: DateTime.utc(2026, 11, 30, 20),
      markChecked: false,
    );
    await session.settings.set(
      planLastCheckDayKey,
      _iso(_day(14)),
      at: DateTime.utc(2026, 11, 30, 20),
    );
    final w = await e.week();
    expect(w.map((u) => '${u.day.weekday}${u.kind.name}'), [
      '2easy',
      '3progressive',
      '5easy',
      '7long',
    ]);
    return e;
  }

  /// Beendeter Lauf am Dienstag (Tag 15) mit [minutes] Bewegungszeit und
  /// [rpe]; noch keiner Einheit zugeordnet.
  Future<int> tuesdayRun({required int minutes, int? rpe}) async {
    final start = DateTime(2026, 12, 1, 7);
    final r = await session.runs.create(startedAt: start);
    final end = start.add(Duration(minutes: minutes));
    await session.runs.setState(
      r.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: end.timeZoneOffset,
    );
    if (rpe != null) {
      await session.subjective.save(r.id, RunSubjective(rpe: rpe));
    }
    figures.add(
      RunFigures(
        runId: r.id,
        endedAt: end.toUtc(),
        day: _iso(_day(15)),
        movingTime: Duration(minutes: minutes),
      ),
    );
    return r.id;
  }

  Future<PlanActionResult> assignTuesday(int runId) async {
    final unit = (await plans.unitOn(_day(15)))!;
    return controller.assignRun(unit.id!, runId);
  }

  Future<List<PlanUnit>> week() => plans.unitsBetween(_day(14), _day(20));

  Future<List<String>> sigs() async => [for (final u in await week()) _sig(u)];

  Future<List<PlanRunNote>> notes() async =>
      planRunNotesFromSummary((await plans.history()).last.summary);
}

void main() {
  group('adaptiv (PAR-235, FR-0216)', () {
    test('intensiv statt locker: Zuordnung macht die harte Einheit am '
        'Mittwoch locker mit Begründung; erneutes Rechnen, Öffnen und das '
        'Warnsignal ändern nichts weiter', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final wed = (await e.plans.unitOn(_day(16)))!;
      final id = await e.tuesdayRun(minutes: 36, rpe: 7);
      expect(await e.assignTuesday(id), PlanActionResult.done);
      final last = (await e.plans.history()).last;
      expect(last.trigger, PlanTrigger.run);
      final now = (await e.plans.unitOn(_day(16)))!;
      expect(now.kind, PlanUnitKind.easy);
      expect(now.minutes, wed.minutes);
      final note = planRunNoteFor(now, await e.notes())!;
      expect(note.change, PlanRunChange.eased);
      expect(note.runDay, _day(15));

      final first = await e.sigs();
      final versions = (await e.plans.history()).length;
      expect(await e.controller.recalculate(), PlanActionResult.done);
      expect(await e.sigs(), first);
      await e.controller.open();
      expect(await e.sigs(), first);
      // Melden und Aufheben des Warnsignals rechnen mit denselben Läufen.
      expect(await e.controller.reportWarning(), PlanActionResult.done);
      expect(await e.controller.liftWarning(), PlanActionResult.done);
      expect(await e.sigs(), first);
      expect(planRunNoteFor(now, await e.notes())?.change, PlanRunChange.eased);
      expect((await e.plans.history()).length, greaterThanOrEqualTo(versions));
    });

    test(
      'deutlich mehr: Zuordnung kürzt den Rest der Woche, Wochensumme mit '
      'der echten Zeit höchstens die Wochenzeit; erneutes Rechnen gleich',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final before = await e.week();
        final weekMinutes = before.fold<int>(0, (a, u) => a + u.minutes);
        final tue = before.first;
        final run = tue.minutes * 2 + 5;
        final id = await e.tuesdayRun(minutes: run, rpe: 3);
        expect(await e.assignTuesday(id), PlanActionResult.done);
        final after = await e.week();
        final rest = after.skip(1).fold<int>(0, (a, u) => a + u.minutes);
        expect(rest + run, lessThanOrEqualTo(weekMinutes));
        expect(
          rest,
          lessThan(before.skip(1).fold<int>(0, (a, u) => a + u.minutes)),
        );
        // Die Vorgabe der erledigten Einheit bleibt (PAR-203).
        expect(after.first.minutes, tue.minutes);
        final notes = await e.notes();
        expect(
          notes.map((n) => n.change),
          everyElement(PlanRunChange.shortened),
        );
        expect(notes, isNotEmpty);
        final first = await e.sigs();
        expect(await e.controller.recalculate(), PlanActionResult.done);
        expect(await e.sigs(), first);
      },
    );

    test('kein Abstandshinweis zu Läufen bei „adaptiv“', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      await e.tuesdayRun(minutes: 36, rpe: 7);
      await e.controller.open();
      final c = e.controller.state.hints!.pinnedConflicts;
      expect(c.where((x) => x.otherDay == _day(15)), isEmpty);
    });
  });

  group('fix (FR-0216, PAR-059, PAR-060)', () {
    test('intensiv gelaufen am Dienstag: Mittwoch und Freitag tauschen, Art '
        'und Dauer bleiben, mit Begründung; erneutes Öffnen gleich', () async {
      final e = await _Env.open(PlanAdaptationMode.fixed);
      final wed = (await e.plans.unitOn(_day(16)))!;
      final fri = (await e.plans.unitOn(_day(18)))!;
      await e.tuesdayRun(minutes: 36, rpe: 7);
      // Öffnen ordnet den Lauf zu (PAR-231) und rechnet neu.
      await e.controller.open();
      final wedNow = (await e.plans.unitOn(_day(16)))!;
      final friNow = (await e.plans.unitOn(_day(18)))!;
      expect(friNow.kind, wed.kind);
      expect(friNow.minutes, wed.minutes);
      expect(wedNow.kind, fri.kind);
      expect(wedNow.minutes, fri.minutes);
      final notes = await e.notes();
      expect(planRunNoteFor(friNow, notes)?.change, PlanRunChange.swapped);
      expect(planRunNoteFor(wedNow, notes)?.otherDay, _day(18));
      expect(
        e.controller.state.hints!.pinnedConflicts.where(
          (x) => x.otherDay == _day(15),
        ),
        isEmpty,
      );
      final first = await e.sigs();
      await e.controller.open();
      expect(await e.controller.recalculate(), PlanActionResult.done);
      expect(await e.sigs(), first);
    });

    test('2,5 × geplante Dauer gelaufen: keine Planänderung', () async {
      final e = await _Env.open(PlanAdaptationMode.fixed);
      final before = (await e.sigs()).skip(1).toList();
      final tue = (await e.plans.unitOn(_day(15)))!;
      final id = await e.tuesdayRun(minutes: (tue.minutes * 2.5).round());
      expect(await e.assignTuesday(id), PlanActionResult.done);
      expect((await e.sigs()).skip(1).toList(), before);
      expect(await e.notes(), isEmpty);
    });

    test('harte Einheit am Mittwoch bestätigt (`pinned`): kein Tausch, '
        'Abstandshinweis zum Lauf am Dienstag', () async {
      final e = await _Env.open(PlanAdaptationMode.fixed);
      final wed = (await e.plans.unitOn(_day(16)))!;
      // Bestätigte Verschiebung von Mittwoch auf Donnerstag.
      await e.controller.open();
      expect(
        await e.controller.confirmMove(wed.id!, _day(17)),
        PlanActionResult.done,
      );
      final thu = (await e.plans.unitOn(_day(17)))!;
      expect(thu.pinned, isTrue);
      // Intensiver Lauf am Mittwoch ohne Einheit (anderer Tag, PAR-059).
      e.clock.set(DateTime(2026, 12, 2, 20));
      final start = DateTime(2026, 12, 2, 7);
      final r = await e.session.runs.create(startedAt: start);
      final end = start.add(const Duration(minutes: 40));
      await e.session.runs.setState(
        r.id,
        RunState.finished,
        endedAt: end,
        endedUtcOffset: end.timeZoneOffset,
      );
      await e.session.subjective.save(r.id, RunSubjective(rpe: 8));
      e.figures.add(
        RunFigures(
          runId: r.id,
          endedAt: end.toUtc(),
          day: _iso(_day(16)),
          movingTime: const Duration(minutes: 40),
        ),
      );
      expect(await e.controller.recalculate(), PlanActionResult.done);
      final thuNow = (await e.plans.unitOn(_day(17)))!;
      expect(thuNow.kind, thu.kind);
      expect(thuNow.pinned, isTrue);
      final c = e.controller.state.hints!.pinnedConflicts
          .where((x) => x.otherDay == _day(16))
          .toList();
      expect(c, hasLength(1));
      expect(c.single.kind, PinnedConflictKind.spacing);
      expect(c.single.day, _day(17));
    });
  });
}
