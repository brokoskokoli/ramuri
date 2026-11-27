import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Abläufe des Plans ohne Oberfläche ([PlanWorkflowService]): Prüfung beim
/// Öffnen, Wochenprüfung (PAR-201), Heilung bei Warnsignal (FR-0203) und
/// Erholungsprüfung (PAR-173, nur bei „adaptiv“, FR-0216). Synthetische
/// Daten: Ziel, Läufe und Readiness-Bänder sind ausgedacht.

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags Ortszeit (Zone des Testprozesses).
final _now = DateTime(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);
DateTime _day(int n) => _today.add(Duration(days: n));

/// Mittag (oder [hour]) des Kalendertags [d] in Ortszeit.
DateTime _localAt(DateTime d, [int hour = 12]) =>
    DateTime(d.year, d.month, d.day, hour);

TrainingGoal _goal({DateTime? target}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: target ?? DateTime.utc(2027, 6, 1),
  runDays: const {2, 4, 6},
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

DateTime? _parseDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// Lese-Port der Tests: Eingaben aus [runs] ([buildPlanInputs]); Belege der
/// Wochenprüfung aus den Minuten der Läufe und Einheiten der Vorwoche. Die
/// Auswahl der Läufe für RPE und Ermüdung prüft der Lese-Adapter der App.
class _Reader implements PlanWorkflowReader {
  _Reader(this.session);

  final StorageSession session;
  List<RunFigures> runs = [];

  /// Hält jedes Lesen an, bis es abgeschlossen ist.
  Completer<void>? gate;

  /// Jedes Lesen wirft (Lesefehler).
  bool fails = false;

  PlanRepository get _plans => (session as PlanStorage).plans;

  Future<void> _wait() async {
    if (fails) throw StateError('Lesefehler');
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  Future<BuiltPlanInputs> read({
    required TrainingGoal goal,
    required DateTime today,
  }) async {
    await _wait();
    final planned = plannedRunIds(
      await _plans.unitsBetween(DateTime.utc(1, 1, 1), planFarFuture),
    );
    return buildPlanInputs(
      goal: goal,
      today: planDay(today),
      runs: runs,
      easyPlannedRunIds: planned.easy,
      otherPlannedRunIds: planned.other,
    );
  }

  @override
  Future<WeekEvidence> weekEvidence(DateTime today) async {
    await _wait();
    final t = planDay(today);
    final thisMonday = t.subtract(Duration(days: t.weekday - DateTime.monday));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    var done = 0.0;
    for (final r in runs) {
      final d = _parseDay(r.day);
      if (d == null || d.isBefore(lastMonday) || !d.isBefore(thisMonday)) {
        continue;
      }
      final time = r.movingTime ?? r.totalTime;
      if (time != null) done += time.inMicroseconds / 6e7;
    }
    final week = [
      for (final u in await _plans.unitsBetween(lastMonday, thisMonday))
        if (u.day.isBefore(thisMonday)) u,
    ];
    return WeekEvidence(
      doneMinutes: done,
      plannedMinutes: week.isEmpty
          ? null
          : week.fold<int>(0, (a, u) => a + u.minutes),
      recentEasyRpe: const [],
      fatigueReported: false,
    );
  }

  @override
  Future<List<PlanRunFacts>> runFacts(DateTime today) async {
    await _wait();
    return const [];
  }
}

class _Env {
  _Env(this.session) : clock = FakeClock(_now), reader = _Reader(session);

  final StorageSession session;
  final FakeClock clock;
  final _Reader reader;

  bool pauseOpen = false;
  PlanReadinessDay? Function(DateTime day)? readiness;

  late final PlanWorkflowService service = PlanWorkflowService(
    session: session,
    clock: clock,
    reader: reader,
    pauseQuestionOpen: () async => pauseOpen,
    readinessToday: (day) async {
      final r = readiness;
      return r == null ? null : r(day);
    },
  );

  PlanRepository get plans => (session as PlanStorage).plans;
  GoalStore get goals => (session as GoalStorage).goals;
  WarningStore get warning => (session as WarningStorage).warning;

  static Future<_Env> open() async => _Env(await FakeStorage().open(_key));

  /// Prüfung wie beim Öffnen der Plan-Seite; die Fassungen landen in
  /// [results].
  final results = <PlanRecalculation>[];
  Future<PlanDueCheck> runDue() async {
    final due = await service.dueCheck();
    await service.runDue(due, onResult: results.add);
    return due;
  }

  /// Ziel speichern und erste Fassung anlegen (wie das Speichern eines
  /// Ziels ohne Plan).
  Future<void> saveGoal(TrainingGoal goal) async {
    await goals.save(goal, today: planDay(_localDay()));
    expect((await runDue()).kind, PlanDueKind.create);
  }

  /// Zieländerung mit bestehender Fassung (Auslöser `goalChange`).
  Future<void> changeGoal(TrainingGoal goal) async {
    await goals.save(goal, today: planDay(_localDay()));
    final last = (await plans.history()).last;
    await service.recalculate(PlanTrigger.goalChange, goal, last);
  }

  /// Manuelles Neuberechnen (Auslöser `manual`).
  Future<void> manual() async {
    final goal = (await goals.goal())!;
    await service.recalculate(
      PlanTrigger.manual,
      goal,
      (await plans.history()).last,
    );
  }

  /// Warnsignal melden: Signal setzen, dann die Ruhetag-Fassung.
  Future<void> reportWarning() async {
    await service.markWarning();
    await service.recalculateWarned();
  }

  DateTime _localDay() {
    final l = clock.now().toLocal();
    return DateTime.utc(l.year, l.month, l.day);
  }
}

/// Schreibt eine Fassung mit [version] ab [validFrom] direkt.
Future<void> _writeVersion(
  _Env e,
  PlanVersion version,
  DateTime validFrom,
) async {
  await e.plans.writeVersion(
    PlanVersionDraft(
      createdAt: validFrom,
      validFrom: validFrom,
      trigger: PlanTrigger.create,
      reason: 'create',
      version: version,
      inputs: PlanInputs.forNewGoal(_goal(), validFrom),
      summary: const {},
      units: const [],
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
  final day = e._localDay();
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
  group('Prüfung beim Öffnen: Wochenprüfung und Regelversion', () {
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
      expect((await e.runDue()).kind, PlanDueKind.weekly);
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.trigger, PlanTrigger.ruleVersion);
      expect(h.last.version.isCurrent, isTrue);
      expect(h.last.validFrom, _today);
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_today),
      );
    });

    test('alte Regelversion, gleiche Einheiten: neue Fassung ohne Änderung, '
        'Prüftag gesetzt, erneute Prüfung schreibt nichts', () async {
      final e = await _Env.open();
      await e.saveGoal(_goal());
      final units = await e.plans.unitsBetween(_today, planFarFuture);
      await _downgradeLast(e);
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(_day(-7)),
        at: _now,
      );
      e.results.clear();
      await e.runDue();
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.ruleVersion);
      expect(h.last.version.isCurrent, isTrue);
      expect(e.results.single.summary?.isEmpty ?? true, isTrue);
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
      expect((await e.runDue()).kind, PlanDueKind.none);
      expect((await e.plans.history()).length, n);
    });

    test('alte Regelversion unter Warnsignal: neue Fassung, gehaltene '
        'Einheiten bleiben gehalten', () async {
      final e = await _Env.open();
      await e.saveGoal(_goal());
      await e.reportWarning();
      await _downgradeLast(e);
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(_day(-7)),
        at: _now,
      );
      await e.runDue();
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
    });

    test('fällig und aktuelle Regelversion: Auslöser weekly', () async {
      final e = await withOld(
        PlanVersion.current,
        lastCheck: _dayText(_day(-7)),
      );
      await e.runDue();
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.trigger, PlanTrigger.weekly);
    });

    test('nicht fällig (Prüfung diese Woche): keine stille '
        'Neuberechnung', () async {
      final e = await withOld(
        const PlanVersion(method: 'alte-methode'),
        lastCheck: _dayText(_day(-2)), // Montag dieser Woche
      );
      expect((await e.runDue()).kind, PlanDueKind.none);
      expect(await e.plans.history(), hasLength(1));
    });

    test('offene Pausenfrage: keine Wochenprüfung (PAR-202)', () async {
      final e = await withOld(
        PlanVersion.current,
        lastCheck: _dayText(_day(-7)),
      );
      e.pauseOpen = true;
      expect((await e.runDue()).kind, PlanDueKind.none);
      expect(await e.plans.history(), hasLength(1));
      e.pauseOpen = false;
      expect((await e.runDue()).kind, PlanDueKind.weekly);
      expect(await e.plans.history(), hasLength(2));
    });

    test('ohne Ziel: nichts fällig', () async {
      final e = await _Env.open();
      expect((await e.runDue()).kind, PlanDueKind.none);
      expect(await e.plans.history(), isEmpty);
    });

    test('Ziel weicht von der neuesten Fassung ab: goalChange', () async {
      final e = await _Env.open();
      await e.saveGoal(_goal());
      await e.goals.save(
        _goal(target: DateTime.utc(2027, 5, 1)),
        today: _today,
      );
      expect((await e.runDue()).kind, PlanDueKind.goalChange);
      expect((await e.plans.history()).last.trigger, PlanTrigger.goalChange);
    });

    test('weeklyCheckDue nach Kalenderwoche', () {
      expect(weeklyCheckDue(null, _today), isTrue);
      expect(weeklyCheckDue('kaputt', _today), isTrue);
      expect(weeklyCheckDue('2026-11-09', _today), isFalse); // Montag
      expect(weeklyCheckDue('2026-11-08', _today), isTrue); // Sonntag davor
    });
  });

  group('Wochenprüfung und Prüftag', () {
    test('wöchentliche Prüfung: Anker und Startwochenzeit bleiben aus der '
        'Vorfassung, auch wenn Läufe den Stand ändern', () async {
      final e = await _Env.open();
      // 12 Läufe zu 50 min in den letzten 6 Wochen: Stand aus Läufen 100 min.
      e.reader.runs = [
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

      await e.runDue();
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.weekly);
      expect(h.last.inputs.anchor, before.anchor);
      expect(h.last.inputs.startWeeklyMinutes, before.startWeeklyMinutes);
      expect(h.last.inputs.today, _today);
    });

    test('manuelles Neuberechnen setzt den Prüftag nicht: die fällige '
        'Wochenbewertung läuft danach beim Öffnen', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      await _writeVersion(e, PlanVersion.current, _day(-7));
      final lastCheck = _dayText(_day(-7));
      await e.session.settings.set(planLastCheckDayKey, lastCheck, at: _now);
      await e.manual();
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        lastCheck,
        reason: 'manuell bewertet die Woche nicht',
      );
      expect(
        weeklyCheckDue(
          await e.session.settings.get(planLastCheckDayKey),
          _today,
        ),
        isTrue,
      );
      await e.runDue();
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_today),
        reason: 'das Öffnen hat die Woche bewertet',
      );
    });
  });

  group('Wochenprüfung PAR-201', () {
    // Plan seit Mittwoch 21.10.; geprüft wird am Mittwoch 25.11. die Woche
    // 16.-22.11. (monday(0)), die Folgewoche ist monday(1).
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
      final e = await _Env.open();
      e.clock.set(_localAt(_day(-21)));
      await e.saveGoal(_goal());
      final planned = await week(e, monday(0));
      if (share > 0) {
        e.reader.runs = [
          RunFigures(
            runId: 1,
            endedAt: monday(0).add(const Duration(days: 2, hours: 9)),
            day: '2026-11-18',
            movingTime: Duration(minutes: (planned * share).round()),
          ),
        ];
      }
      e.clock.set(_localAt(_day(14)));
      return (e, planned);
    }

    test('Woche ohne Läufe: neue Fassung, Wochenzeit nicht höher '
        '(wiederholen)', () async {
      final (e, planned) = await prepare();
      final before = await week(e, monday(1));
      expect(before, greaterThan(planned), reason: 'sonst belegt es nichts');
      await e.runDue();
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.trigger, PlanTrigger.weekly);
      expect(h.last.reason, 'repeatWeek');
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
      // idempotent: zweite Prüfung schreibt nichts
      await e.runDue();
      expect(await e.plans.history(), hasLength(2));
    });

    test(
      'alte Regelversion: die Prüfung bewertet die Woche wie weekly',
      () async {
        final (e, planned) = await prepare();
        await _downgradeLast(e);
        await e.runDue();
        final h = await e.plans.history();
        expect(h.last.trigger, PlanTrigger.ruleVersion);
        expect(h.last.reason, 'ruleVersion,repeatWeek');
        expect(h.last.version.isCurrent, isTrue);
        expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
      },
    );

    test('Warnsignal und fällige Wochenbewertung: nach dem Aufheben gilt die '
        'Anpassung', () async {
      final (e, planned) = await prepare();
      // Gemeldet am Dienstag, geprüft am Mittwoch derselben Woche: die
      // Wochenprüfung ist fällig, das Melden hat den Prüftag nicht gesetzt.
      e.clock.set(_localAt(_day(13)));
      await e.reportWarning();
      e.clock.set(_localAt(_day(14)));
      await e.runDue();
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
      await e.service.liftWarning();
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
    });

    test('Warnsignal: wiederholtes Prüfen und Neuberechnen ohne Änderung der '
        'Eingaben schreibt keine weitere Fassung', () async {
      final (e, _) = await prepare();
      e.clock.set(_localAt(_day(13)));
      await e.reportWarning();
      e.clock.set(_localAt(_day(14)));
      await e.runDue(); // Wochenbewertung: genau eine neue Fassung
      final n = (await e.plans.history()).length;
      await e.runDue();
      await e.runDue();
      await e.manual();
      await e.manual();
      expect((await e.plans.history()).length, n);
      // Neuer Tag ohne neue Woche: gemessene Werte allein ergeben nichts.
      e.clock.set(_localAt(_day(15)));
      await e.runDue();
      expect((await e.plans.history()).length, n);
    });

    test('Hälfte bis 80 %: keine Steigerung', () async {
      final (e, planned) = await prepare(share: 0.65);
      final before = await week(e, monday(1));
      expect(before, greaterThan(planned), reason: 'sonst belegt es nichts');
      await e.runDue();
      final h = await e.plans.history();
      expect(h, hasLength(2));
      expect(h.last.reason, 'noIncrease');
      expect(await week(e, monday(1)), lessThanOrEqualTo(planned));
    });

    test('mehr als 80 %: keine Änderung', () async {
      final (e, _) = await prepare(share: 0.9);
      await e.runDue();
      final h = await e.plans.history();
      expect(h.length, 1);
    });

    test('goalChange am Montag bewertet die Vorwoche mit '
        '(Grund goalChange mit Gründen)', () async {
      final e = await _Env.open();
      e.clock.set(_localAt(_day(-21)));
      await e.saveGoal(_goal());
      final mon1 = DateTime.utc(2026, 11, 23);
      // Montag der Folgewoche: Ziel geändert, Vorwoche ohne Läufe.
      e.clock.set(_localAt(mon1, 12));
      await e.changeGoal(_goal(target: DateTime.utc(2027, 5, 1)));
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.goalChange);
      expect(h.last.reason, 'goalChange,repeatWeek');
      // Die Bewertung der Vorwoche (0 % geschafft) ist in die Fassung
      // eingegangen.
      expect(h.last.inputs.achievedShare, 0);
      expect(h.last.inputs.lastWeekMinutes, isNotNull);
    });

    test('goalChange am Montag bei offener Pausenfrage: keine Bewertung, '
        'Prüftag bleibt', () async {
      final e = await _Env.open();
      e.clock.set(_localAt(_day(-21)));
      await e.saveGoal(_goal());
      final checked = await e.session.settings.get(planLastCheckDayKey);
      e.clock.set(_localAt(DateTime.utc(2026, 11, 23), 12));
      e.pauseOpen = true;
      await e.changeGoal(_goal(target: DateTime.utc(2027, 5, 1)));
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.goalChange);
      expect(h.last.reason, 'goalChange');
      expect(await e.session.settings.get(planLastCheckDayKey), checked);
    });
  });

  group('Heilung bei Warnsignal (FR-0203): Zeile und Plan stimmen überein', () {
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
      await e.runDue();
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        _dayText(_today),
      );
      return e;
    }

    test('Aufheben scheiterte nach dem Löschen der Zeile: die nächste '
        'Prüfung stellt den Plan her', () async {
      final e = await opened();
      final before = await sigs(e);
      await e.reportWarning();
      expect(await sigs(e), isNot(before));
      await e.warning.lift(); // Schreiben der Fassung scheiterte
      final due = await e.runDue();
      expect(due.kind, PlanDueKind.warningHeal);
      expect(due.warned, isFalse);
      expect(await sigs(e), before);
      final last = (await e.plans.history()).last;
      expect(last.reason, planReasonWarningLifted);
      expect(last.trigger, PlanTrigger.feedback);
    });

    test('Rücknahme der Zeile in report scheiterte: die nächste Prüfung '
        'überlagert den Plan', () async {
      final e = await opened();
      final before = await sigs(e);
      await e.warning.set(
        WarningSignal(reportedOn: _today, source: WarningSource.manual),
      ); // Plan nicht geschrieben, Rücknahme scheiterte
      expect(await sigs(e), before);
      final due = await e.runDue();
      expect(due.kind, PlanDueKind.warningHeal);
      expect(due.warned, isTrue);
      final after = await e.plans.unitsBetween(_day(0), planFarFuture);
      expect(after.every((u) => u.kind == PlanUnitKind.rest), isTrue);
      final last = (await e.plans.history()).last;
      expect(last.reason, planReasonWarning);
      expect(warningHeldFromSummary(last.summary), isNotNull);
    });

    test('Heilung vor der Rechnung erkennbar: dueCheck liest nur, die '
        'Fassung entsteht erst in runDue', () async {
      final e = await opened();
      await e.warning.set(
        WarningSignal(reportedOn: _day(-7), source: WarningSource.manual),
      );
      final versions = (await e.plans.history()).length;
      final gate = e.reader.gate = Completer<void>();
      final due = await e.service.dueCheck();
      expect(due.kind, PlanDueKind.warningHeal);
      expect(await e.plans.history(), hasLength(versions));
      final running = e.service.runDue(due);
      await Future<void>.delayed(Duration.zero);
      expect(await e.plans.history(), hasLength(versions));
      gate.complete();
      await running;
      expect((await e.plans.history()).last.reason, planReasonWarning);
    });

    test('Heilung unter gespeichertem Signal scheitert: Fehler an den '
        'Aufrufer, Signal und Fassungen bleiben', () async {
      final e = await opened();
      await e.warning.set(
        WarningSignal(reportedOn: _today, source: WarningSource.manual),
      );
      final versions = (await e.plans.history()).length;
      e.reader.fails = true;
      final due = await e.service.dueCheck();
      await expectLater(e.service.runDue(due), throwsStateError);
      expect(await e.warning.read(), isNotNull);
      expect(await e.plans.history(), hasLength(versions));
    });

    test('Heilung setzt den Prüftag nicht: eine fällige Wochenprüfung bleibt '
        'fällig', () async {
      final e = await opened();
      final lastCheck = _dayText(_day(-7));
      await e.session.settings.set(planLastCheckDayKey, lastCheck, at: _now);
      await e.warning.set(
        WarningSignal(reportedOn: _today, source: WarningSource.manual),
      );
      expect((await e.runDue()).kind, PlanDueKind.warningHeal);
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
      // Danach läuft die fällige Wochenprüfung.
      expect((await e.runDue()).kind, PlanDueKind.weekly);
    });

    test('ohne Warnspeicher: Melden und Aufheben scheitern, kein '
        'WarningService', () async {
      final e = await opened();
      final s = _NoWarningSession(e.session);
      final service = PlanWorkflowService(
        session: s,
        clock: e.clock,
        reader: e.reader,
        pauseQuestionOpen: () async => false,
      );
      expect(service.warnings, isNull);
      await expectLater(service.markWarning(), throwsStateError);
      expect(service.liftWarning, throwsStateError);
      expect((await service.dueCheck()).kind, PlanDueKind.none);
    });
  });

  group('Erholungsprüfung PAR-173 (nur „adaptiv“, FR-0216)', () {
    /// Plan mit harter Einheit; die Uhr steht am Mittag des ersten Tags mit
    /// harter Einheit ab morgen.
    Future<(_Env, DateTime)> hardDay() async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _today);
      // Mit Laufstand angelegt, damit harte Einheiten früh im Plan liegen.
      await e.service.write(
        trigger: PlanTrigger.create,
        today: _today,
        inputs: PlanInputs.forNewGoal(
          _goal(),
          _today,
        ).copyWith(startWeeklyMinutes: 180),
      );
      for (var n = 1; n < 28; n++) {
        final u = await e.plans.unitOn(_day(n));
        if (u != null && u.isHard) {
          e.clock.set(_localAt(_day(n)));
          return (e, _day(n));
        }
      }
      fail('kein Tag mit harter Einheit');
    }

    PlanReadinessDay band(DateTime day, ReadinessBand b) =>
        PlanReadinessDay(day: day, band: b);

    Future<void> adaptive(_Env e) =>
        SettingsPlanAdaptationStore(e.session.settings)
            .set(PlanAdaptationMode.adaptive, at: e.clock.now());

    test('„adaptiv“ und niedriger Wert heute: die harte Einheit wird locker '
        '(feedback, Grund readiness)', () async {
      final (e, day) = await hardDay();
      await adaptive(e);
      e.readiness = (d) => band(d, ReadinessBand.recoveryAdvised);
      final r = await e.service.recheckRecoveryToday();
      expect(r?.wasWritten, isTrue);
      final last = (await e.plans.history()).last;
      expect(last.trigger, PlanTrigger.feedback);
      expect(last.reason, planReasonReadiness);
      expect((await e.plans.unitOn(day))!.isHard, isFalse);
      expect(
        recoveryEasedFromSummary(last.summary)
            .map((x) => planDay(x.day))
            .toList(),
        [day],
      );
    });

    test('„fix“: niedriger Wert ändert nichts, die Quelle wird nicht '
        'gelesen', () async {
      final (e, day) = await hardDay();
      final asked = <DateTime>[];
      e.readiness = (d) {
        asked.add(d);
        return band(d, ReadinessBand.recoveryAdvised);
      };
      final versions = (await e.plans.history()).length;
      expect(await e.service.recheckRecoveryToday(), isNull);
      expect(await e.plans.history(), hasLength(versions));
      expect((await e.plans.unitOn(day))!.isHard, isTrue);
      expect(asked, isEmpty);
    });

    test('„adaptiv“, Wert gut, ohne Wert, Wert eines anderen Tags oder '
        'Fehler der Quelle: keine Fassung', () async {
      final (e, day) = await hardDay();
      await adaptive(e);
      final versions = (await e.plans.history()).length;
      for (final source in <PlanReadinessDay? Function(DateTime)>[
        (d) => band(d, ReadinessBand.wellRecovered),
        (d) => null,
        (d) => band(
          d.subtract(const Duration(days: 1)),
          ReadinessBand.recoveryAdvised,
        ),
        (d) => throw StateError('Quelle'),
      ]) {
        e.readiness = source;
        expect(await e.service.recheckRecoveryToday(), isNull);
      }
      expect(await e.plans.history(), hasLength(versions));
      expect((await e.plans.unitOn(day))!.isHard, isTrue);
    });

    test('„adaptiv“ ohne harte Einheit heute: keine Fassung', () async {
      final (e, day) = await hardDay();
      await adaptive(e);
      e.readiness = (d) => band(d, ReadinessBand.recoveryAdvised);
      // Am Vortag der harten Einheit liegt keine.
      e.clock.set(_localAt(day.subtract(const Duration(days: 1))));
      final before = await e.plans.unitOn(
        day.subtract(const Duration(days: 1)),
      );
      expect(before == null || !recoveryEasable(before), isTrue);
      expect(await e.service.recheckRecoveryToday(), isNull);
    });

    test('Wochenprüfung nimmt die Erholung über PAR-173 auf: eigene Fassung '
        'nach der Wochenfassung', () async {
      final (e, day) = await hardDay();
      await adaptive(e);
      e.readiness = (d) => band(d, ReadinessBand.elevatedLoad);
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(day.subtract(const Duration(days: 7))),
        at: e.clock.now(),
      );
      e.results.clear();
      expect((await e.runDue()).kind, PlanDueKind.weekly);
      expect(e.results, hasLength(2));
      final h = await e.plans.history();
      expect(h.last.reason, planReasonReadiness);
      // Erst die Wochenfassung, dann die Lockerung als eigene Fassung.
      expect(e.results.last.version?.id, h.last.id);
      expect(e.results.first.version?.id, isNot(h.last.id));
      expect((await e.plans.unitOn(day))!.isHard, isFalse);
    });

    test('Wochenprüfung bei „fix“: keine Erholungsfassung', () async {
      final (e, day) = await hardDay();
      e.readiness = (d) => band(d, ReadinessBand.elevatedLoad);
      await e.session.settings.set(
        planLastCheckDayKey,
        _dayText(day.subtract(const Duration(days: 7))),
        at: e.clock.now(),
      );
      e.results.clear();
      await e.runDue();
      expect(e.results, hasLength(1));
      expect((await e.plans.history()).last.reason, isNot(planReasonReadiness));
      expect((await e.plans.unitOn(day))!.isHard, isTrue);
    });

    test(
      'Wechsel auf „adaptiv“ lockert, zurück auf „fix“ kehrt die Einheit '
      'zurück (Grund adaptationFixed); gleicher Modus ändert nichts',
      () async {
        final (e, day) = await hardDay();
        e.readiness = (d) => band(d, ReadinessBand.recoveryAdvised);
        expect(
          (await e.service.setAdaptation(PlanAdaptationMode.adaptive))
              ?.wasWritten,
          isTrue,
        );
        expect((await e.plans.unitOn(day))!.isHard, isFalse);
        final n = (await e.plans.history()).length;
        expect(
          await e.service.setAdaptation(PlanAdaptationMode.adaptive),
          isNull,
        );
        expect(await e.plans.history(), hasLength(n));
        final back = await e.service.setAdaptation(PlanAdaptationMode.fixed);
        expect(back?.wasWritten, isTrue);
        expect(
          (await e.plans.history()).last.reason,
          planReasonAdaptationFixed,
        );
        expect((await e.plans.unitOn(day))!.isHard, isTrue);
      },
    );
  });
}

/// Sitzung ohne Warnspeicher (andere Sitzungsarten): leitet alles an
/// [inner] weiter.
class _NoWarningSession implements StorageSession, GoalStorage, PlanStorage {
  _NoWarningSession(this.inner);
  final StorageSession inner;

  @override
  GoalStore get goals => (inner as GoalStorage).goals;

  @override
  PlanRepository get plans => (inner as PlanStorage).plans;

  @override
  SettingsStore get settings => inner.settings;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
