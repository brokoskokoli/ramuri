import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_recovery_trigger.dart';

import 'helpers/local_clock.dart';

/// Eine Schreibreihe des Plans je Sitzung (ADR-0010): mehrere
/// Plan-Controller, der Erholungs-Auslöser und die automatische Zuordnung
/// (PAR-231) überholen sich nicht; eine abgelehnte Fassung wird einmal neu
/// gerechnet und sonst nicht still verworfen. Synthetische Daten: Ziel, Plan,
/// Läufe und Readiness-Bänder sind ausgedacht.

final Uint8List _k = Uint8List.fromList(List.generate(32, (i) => i));
final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));

TrainingGoal _goal({double maxSessionSeconds = 7200}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: maxSessionSeconds,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

/// Einfache Sperre wie `RecalculationController.exclusive`: Aktionen laufen
/// nacheinander; [held] zählt, wie viele gerade laufen oder warten.
class _Lock {
  Future<void> _tail = Future<void>.value();
  int held = 0;

  Future<void> call(Future<void> Function() action) {
    held++;
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {}).whenComplete(() => held--);
    return run;
  }
}

class _Env {
  _Env(this.storage, this.session);

  final FakeStorage storage;
  final StorageSession session;
  late final LocalFakeClock clock;

  PlanReadinessDay? Function(DateTime day) readiness = (_) => null;

  PlanRepository get plans => (session as PlanStorage).plans;

  /// Plan mit harter Einheit in jeder Woche, angelegt am Mittwoch [_d0]
  /// (Prüftag gesetzt); die Uhr steht am Mittag der ersten harten Einheit ab
  /// dem Tag [from].
  static Future<_Env> open({int from = 1}) async {
    final storage = FakeStorage();
    final s = await storage.open(_k);
    await (s as GoalStorage).goals.save(_goal(), today: _day(0));
    await recalculatePlan(
      plans: (s as PlanStorage).plans,
      settings: s.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: _day(0).add(const Duration(hours: 8)),
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 180),
      warning: (s as WarningStorage).warning,
    );
    final e = _Env(storage, s);
    e.clock = LocalFakeClock(localAt(_day(await e.hardFrom(from)), 12));
    return e;
  }

  Future<int> hardFrom(int from) async {
    for (var n = from; n < from + 28; n++) {
      final u = await plans.unitOn(_day(n));
      if (u != null && u.isHard) return n;
    }
    fail('keine harte Einheit');
  }

  DateTime get today => calendarDay(clock.now());

  Future<void> mode(PlanAdaptationMode m) =>
      SettingsPlanAdaptationStore(session.settings).set(m, at: clock.now());

  Future<PlanReadinessDay?> source(DateTime day) async => readiness(day);

  PlanController controller({
    Future<void> Function(Future<void> Function())? exclusive,
  }) => PlanController(
    session: session,
    clock: clock,
    reader: PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => const [],
    ),
    readinessToday: source,
    exclusive: exclusive,
  );

  PlanRecoveryTrigger trigger() => PlanRecoveryTrigger(
    session: session,
    clock: clock,
    readinessToday: source,
  );

  Future<List<PlanTrigger>> triggers() async => [
    for (final v in await plans.history()) v.trigger,
  ];

  Future<List<PlanUnit>> units() =>
      plans.unitsBetween(DateTime.utc(2000), planFarFuture);

  /// Beendeter Lauf heute um [h]:00 Ortszeit, 40 Minuten.
  Future<int> runToday(int h) async {
    final start = localAt(today, h);
    final end = start.add(const Duration(minutes: 40));
    final r = await session.runs.create(startedAt: start);
    await session.runs.setState(
      r.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: end.timeZoneOffset,
    );
    return r.id;
  }
}

PlanReadinessDay _band(DateTime day, ReadinessBand band) => PlanReadinessDay(
  day: day,
  band: band,
  drivers: const [ReadinessFactorId.hrv],
);

void main() {
  group('PlanWriteQueue', () {
    test(
      'eine Reihe je Sitzungsobjekt, eine andere Sitzung hat ihre eigene',
      () async {
        final a = await FakeStorage().open(_k);
        final b = await FakeStorage().open(_k);
        expect(identical(PlanWriteQueue.of(a), PlanWriteQueue.of(a)), isTrue);
        expect(identical(PlanWriteQueue.of(a), PlanWriteQueue.of(b)), isFalse);
      },
    );

    test('Aktionen laufen nacheinander in Aufrufreihenfolge; ein Fehler hält '
        'die Reihe nicht an', () async {
      final q = PlanWriteQueue();
      final log = <String>[];
      final gate = Completer<void>();
      final first = q.run(() async {
        log.add('1 an');
        await gate.future;
        log.add('1 aus');
        return 1;
      });
      final failing = q.run<int>(() async {
        log.add('2');
        throw StateError('x');
      });
      final third = q.run(() async {
        log.add('3');
        return 3;
      });
      await Future<void>.delayed(Duration.zero);
      expect(log, ['1 an']);
      gate.complete();
      expect(await first, 1);
      await expectLater(failing, throwsStateError);
      expect(await third, 3);
      expect(log, ['1 an', '1 aus', '2', '3']);
    });
  });

  test('zwei Controller und der Erholungs-Auslöser ändern gleichzeitig: alle '
      'Änderungen in Aufrufreihenfolge gespeichert, keine Fassung '
      'abgelehnt oder verworfen (ADR-0010)', () async {
    final e = await _Env.open();
    await e.mode(PlanAdaptationMode.adaptive);
    e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
    final today = e.today;
    expect((await e.plans.unitOn(today))!.isHard, isTrue);
    final units = await e.units();
    final busy = {for (final u in units) u.day};
    final later = units.firstWhere(
      (u) => u.day.isAfter(today) && u.runId == null,
    );
    final free = [
      for (var i = 1; i < 7; i++)
        if (!busy.contains(today.add(Duration(days: i))))
          today.add(Duration(days: i)),
    ].first;
    final before = await e.triggers();
    // Zwischen Lesen und Schreiben jeder Fassung vergeht Zeit (mehrere
    // Runden der Ereignisschleife): Ohne gemeinsame Reihe läse ein anderer
    // Schreiber in dieser Lücke den alten Stand.
    e.storage.data.beforePlanWrite = () async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    };
    final c1 = e.controller();
    final c2 = e.controller();
    // Ohne `await` dazwischen: alle drei laufen zugleich an.
    final results = await Future.wait<Object>([
      c1.confirmMove(later.id!, free),
      e.trigger().recheck(),
      c2.saveGoal(_goal(maxSessionSeconds: 6600)),
    ]);
    expect(results, [PlanActionResult.done, true, PlanActionResult.done]);
    expect(await e.triggers(), [
      ...before,
      PlanTrigger.feedback,
      PlanTrigger.goalChange,
    ]);
    expect(e.storage.data.rejectedPlanWrites, 0);
    // Die Verschiebung überlebt die Neuberechnung (pinned), die Lockerung
    // von heute ebenso, und das neue Ziel ist gespeichert.
    final moved = await e.plans.unitOn(free);
    expect(moved?.pinned, isTrue);
    expect(moved?.kind, later.kind);
    expect((await e.plans.unitOn(today))!.isHard, isFalse);
    expect(
      (await (e.session as GoalStorage).goals.goal())!.maxSessionSeconds,
      6600,
    );
    c1.dispose();
    c2.dispose();
  });

  group('PAR-231: Zuordnung beim Öffnen hinter der Sperre der '
      'Wertberechnung', () {
    test('Lauf gleichzeitig aus open() und nach dem Lauf-Ende zugeordnet: '
        'genau eine Zuordnung', () async {
      final e = await _Env.open();
      final run = await e.runToday(8);
      final lock = _Lock();
      final c1 = e.controller(exclusive: lock.call);
      final c2 = e.controller();
      await Future.wait([
        c1.open(),
        lock(() async {
          await c2.autoAssignRuns(since: e.today);
        }),
      ]);
      final carrying = [
        for (final u in await e.units())
          if (u.runId == run) u,
      ];
      expect(carrying, hasLength(1));
      expect(carrying.single.day, e.today);
      expect(e.storage.data.planAssignWrites, 1);
      expect(
        [
          for (final u in c1.state.weekUnits)
            if (u.runId == run) u.day,
        ],
        [e.today],
      );
      c1.dispose();
      c2.dispose();
    });

    test('open() ordnet erst zu, wenn die laufende Wertberechnung die Sperre '
        'freigibt', () async {
      final e = await _Env.open();
      final run = await e.runToday(8);
      final lock = _Lock();
      final release = Completer<void>();
      final busy = lock(() => release.future);
      final c = e.controller(exclusive: lock.call);
      final opened = c.open();
      // Die Seite lädt schon, die Zuordnung wartet auf die Sperre.
      for (var i = 0; i < 1000 && c.state.phase != PlanLoadPhase.ready; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.state.phase, PlanLoadPhase.ready);
      expect(e.storage.data.planAssignWrites, 0);
      expect((await e.plans.unitOn(e.today))!.runId, isNull);
      release.complete();
      await busy;
      await opened;
      expect(e.storage.data.planAssignWrites, 1);
      expect((await e.plans.unitOn(e.today))!.runId, run);
      c.dispose();
    });
  });

  group('abgelehnte Planfassung (ADR-0010)', () {
    test('einmal abgelehnt: neu gelesen und einmal wiederholt, die Fassung '
        'ist gespeichert', () async {
      final e = await _Env.open();
      final before = await e.triggers();
      e.storage.data.rejectPlanWrites = 1;
      final c = e.controller();
      expect(
        await c.saveGoal(_goal(maxSessionSeconds: 6600)),
        PlanActionResult.done,
      );
      expect(e.storage.data.rejectedPlanWrites, 1);
      expect(e.storage.data.rejectPlanWrites, 0);
      expect(await e.triggers(), [...before, PlanTrigger.goalChange]);
      c.dispose();
    });

    test('zweimal abgelehnt: Ziel gespeichert, Plan nicht (savedNotPlanned), '
        'gespeicherter Plan bleibt; das nächste Öffnen holt die Fassung '
        'nach', () async {
      final e = await _Env.open();
      final before = await e.triggers();
      final units = await e.units();
      e.storage.data.rejectPlanWrites = 2;
      final c = e.controller();
      expect(
        await c.saveGoal(_goal(maxSessionSeconds: 6600)),
        PlanActionResult.savedNotPlanned,
      );
      expect(e.storage.data.rejectedPlanWrites, 2);
      expect(await e.triggers(), before);
      expect(
        [for (final u in await e.units()) u.id],
        [for (final u in units) u.id],
      );
      await c.open();
      expect(e.storage.data.rejectedPlanWrites, 2);
      expect(await e.triggers(), [...before, PlanTrigger.goalChange]);
      c.dispose();
    });
  });
}
