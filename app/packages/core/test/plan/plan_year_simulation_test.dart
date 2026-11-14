import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Abschlussprüfung M2, Teil D: ein Jahr Plan im Schnelldurchlauf über die
/// Kernlogik (nur synthetische Läufe, keine Uhr, keine Oberfläche). Die
/// Ablaufsteuerung bildet `PlanController` nach (Wochenprüfung, Lauf,
/// Rückmeldung, Pause, Warnsignal, Zieländerung); alle Zahlen kommen aus
/// [PlanParameters] (PAR-Nummern) und dem Ziel, nicht aus dem Test.

final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));
DateTime _now(int n) => _day(n).add(const Duration(hours: 8));
DateTime _monday(DateTime d) =>
    d.subtract(Duration(days: d.weekday - DateTime.monday));
String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

bool _weeklyDue(String? lastCheck, DateTime today) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(lastCheck ?? '');
  if (m == null) return true;
  final last = DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
  );
  return _monday(last).isBefore(_monday(today));
}

String _sig(PlanUnit u) =>
    '${_iso(u.day)}|${u.kind.name}|${u.phase.name}|${u.weekIndex}|${u.minutes}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.durationSeconds}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

class _Scenario {
  const _Scenario({
    required this.name,
    required this.days,
    required this.goal,
    this.goalChangeDay,
    this.goalChange,
    this.warningDay,
    this.pause,
    this.outageWeeks = const {},
    this.tiredWeeks = const {},
    this.fatigueReportedWeek,
    this.moveDays = const [],
    this.ruleVersionWeek,
  });
  final String name;
  final int days;
  final TrainingGoal goal;
  final int? goalChangeDay;
  final TrainingGoal? goalChange;
  final int? warningDay;

  /// Erster und letzter Tag ohne Lauf (Pause).
  final (int, int)? pause;

  /// Wochen (ab Tag 0, Montag-Zählung) mit Ausfall: höchstens ein Lauf.
  final Set<int> outageWeeks;

  /// Wochen, deren lockere Läufe mit RPE 8 gemeldet werden (Ermüdung).
  final Set<int> tiredWeeks;
  final int? fatigueReportedWeek;
  final List<int> moveDays;
  final int? ruleVersionWeek;
}

TrainingGoal _goal({
  required GoalDistance distance,
  required DateTime date,
  ContinuousRun30 c30 = ContinuousRun30.yes,
  double? stated,
  Set<int> days = const {2, 4, 6},
}) => TrainingGoal(
  type: GoalType.distance,
  distance: distance,
  targetDate: date,
  runDays: days,
  maxSessionSeconds: 120 * 60.0,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: _d0,
  hardSessionEnabled: true,
  currentWeeklySeconds: stated,
  canRun30: c30,
);

class _Result {
  _Result(this.transcript, this.weekly, this.violations, this.stats);
  final List<String> transcript;

  /// Wochenzeit je Montag des zuletzt gerechneten Plans (Plausibilität).
  final Map<String, int> weekly;
  final List<String> violations;
  final Map<String, int> stats;
}

Future<_Result> _simulate(_Scenario sc) async {
  final session = await FakeStorage().open(
    Uint8List.fromList(List.generate(32, (i) => i)),
  );
  final plans = (session as PlanStorage).plans;
  final goals = (session as GoalStorage).goals;
  final warningStore = (session as WarningStorage).warning;
  final settings = session.settings;
  const p = PlanParameters();
  final warnings = WarningService(
    plans: plans,
    settings: settings,
    warning: warningStore,
  );

  var goal = sc.goal;
  final violations = <String>[];
  final transcript = <String>[];
  final stats = <String, int>{};
  void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
  void bad(int day, String rule, String what) =>
      violations.add('Tag $day (${_iso(_day(day))}) $rule: $what');

  final doneByDay = <DateTime, int>{}; // Minuten gelaufen je Tag
  final easyRpe = <int?>[];
  final frozenSigs = <DateTime, String>{};
  final confirmedPins = <DateTime>{};
  DateTime? lastAnswer;
  DateTime? lastTraining;
  String? pauseHandled;
  var pausesAnswered = 0;
  var lcg = 12345;
  int rnd(int n) {
    lcg = (lcg * 1103515245 + 12345) & 0x7fffffff;
    return (lcg >> 8) % n;
  }

  int weekMinutes(DateTime monday, Map<DateTime, int> byDay) {
    var s = 0;
    for (var i = 0; i < 7; i++) {
      s += byDay[monday.add(Duration(days: i))] ?? 0;
    }
    return s;
  }

  Future<List<PlanUnit>> all() => plans.unitsBetween(_day(-30), planFarFuture);

  // Eine Neuberechnung wie im Controller: Prüftag nur bei create, goalChange,
  // weekly, ruleVersion, pause; nie bei run, feedback (Warnsignal, Antwort).
  Future<PlanRecalculation> recalc(
    PlanTrigger t,
    int day, {
    bool evaluate = false,
    PlanInputs? inputs,
    String? reason,
    bool? markChecked,
  }) async {
    final today = _day(day);
    final history = await plans.history();
    final last = history.isEmpty ? null : history.last;
    var use = inputs;
    String? why = reason;
    DateTime? fatigueUntil;
    if (evaluate && last != null) {
      final thisMonday = _monday(today);
      final lastMonday = thisMonday.subtract(const Duration(days: 7));
      final week = await plans.unitsBetween(
        lastMonday,
        lastMonday.add(const Duration(days: 6)),
      );
      final planned = week
          .where((u) => u.kind != PlanUnitKind.rest)
          .fold<int>(0, (a, u) => a + u.minutes);
      final a = evaluateWeekAdjustment(
        goal: goal,
        inputs: last.inputs.copyWith(today: today),
        today: today,
        doneMinutes: weekMinutes(lastMonday, doneByDay).toDouble(),
        plannedMinutes: planned > 0 ? planned : null,
        recentEasyRpe: List.of(easyRpe),
        fatigueReported:
            sc.fatigueReportedWeek != null &&
            lastMonday == _monday(_day(sc.fatigueReportedWeek! * 7)),
      );
      if (a != null) {
        use = a.inputs;
        if (a.reasons.contains(WeekAdjustmentReason.fatigue)) {
          // PAR-201: keine harte Einheit in der nächsten Woche (Mo bis So).
          fatigueUntil = _monday(today).add(const Duration(days: 6));
        }
        why = ([
          ...a.reasons,
        ]..sort((x, y) => x.index - y.index)).map((r) => r.name).join(',');
        count('anpassung_${why.split(',').first}');
      }
    }
    final mark =
        markChecked ??
        (t == PlanTrigger.create ||
            t == PlanTrigger.goalChange ||
            t == PlanTrigger.weekly ||
            t == PlanTrigger.ruleVersion ||
            t == PlanTrigger.pause);
    final before = await settings.get(planLastCheckDayKey);
    final r = await recalculatePlan(
      plans: plans,
      settings: settings,
      trigger: t,
      today: today,
      now: _now(day),
      reason: why,
      inputs: use,
      warning: warningStore,
      markChecked: mark,
    );
    // Prüftag (unabhängig von der Markierung oben): nie in der Zukunft und nie
    // vor dem vorigen Stand; der Tag steht damit für die Wochenprüfung.
    final after = await settings.get(planLastCheckDayKey);
    if (after != null &&
        (after.compareTo(_iso(today)) > 0 ||
            (before != null && after.compareTo(before) < 0))) {
      bad(day, 'Prüftag', '${t.name}: $before -> $after bei ${_iso(today)}');
    }
    if (fatigueUntil != null) {
      final until = (await plans.history()).last.inputs.noHardUntil;
      if (until == null || until.isBefore(fatigueUntil)) {
        bad(
          day,
          'PAR-201',
          'Ermüdung ohne noHardUntil bis $fatigueUntil: $until',
        );
      }
      count('ermuedung_ohne_harte_einheit');
    }
    count('recalc_${t.name}');
    return r;
  }

  Future<void> checkInvariants(int day, PlanTrigger? trigger) async {
    final today = _day(day);
    final units = await all();
    final history = await plans.history();
    if (history.isEmpty) return;
    final inputs = history.last.inputs;
    final warned = await warningStore.read() != null;

    // PAR-203: vergangene und absolvierte Einheiten bleiben unverändert.
    for (final e in frozenSigs.entries) {
      final cur = units.where((u) => u.day == e.key).toList();
      final now = cur.isEmpty ? 'fehlt' : _sig(cur.first);
      if (now != e.value) {
        bad(
          day,
          'PAR-203',
          'eingefroren ${_iso(e.key)} war ${e.value}, ist $now',
        );
      }
    }
    for (final u in units) {
      if (u.day.isBefore(today) || u.runId != null) {
        frozenSigs.putIfAbsent(u.day, () => _sig(u));
      }
    }

    final future = [
      for (final u in units)
        if (!u.day.isBefore(today) && u.runId == null) u,
    ];

    // Warnsignal (FR-0203): alle offenen künftigen Einheiten sind Ruhetage.
    if (warned) {
      for (final u in future) {
        if (u.kind != PlanUnitKind.rest) {
          bad(day, 'FR-0203', 'Lauf unter Warnsignal: ${_sig(u)}');
        }
      }
    }
    // „Keine harte Einheit bis“ (PAR-201, PAR-202).
    final nh = inputs.noHardUntil;
    if (nh != null) {
      for (final u in future) {
        if (u.isHard && !u.day.isAfter(nh) && !u.fixed.keepsKind) {
          bad(day, 'noHardUntil', 'harte Einheit ${_sig(u)} bis ${_iso(nh)}');
        }
      }
    }
    // Lauftage (FR-0141) und Termine nur mit Bestätigung (OQ-0011).
    for (final u in units) {
      if (u.pinned && !confirmedPins.contains(u.day) && !u.isRestDay) {
        bad(day, 'Termin', 'pinned ohne Bestätigung: ${_sig(u)}');
      }
    }
    for (final u in future) {
      if (u.kind == PlanUnitKind.rest || u.pinned) continue;
      if (!goal.runDays.contains(u.day.weekday)) {
        bad(day, 'Lauftage', 'Lauf an gesperrtem Wochentag: ${_sig(u)}');
      }
      if (u.minutes * 60 > goal.maxSessionSeconds + 1) {
        bad(day, 'Dauer je Einheit', 'über Höchstdauer: ${_sig(u)}');
      }
    }
    // Wochenzeit, Regler, Steigerung, harte Einheit je Woche.
    final byWeek = <DateTime, List<PlanUnit>>{};
    for (final u in units) {
      if (u.kind == PlanUnitKind.rest) continue;
      byWeek.putIfAbsent(_monday(u.day), () => []).add(u);
    }
    final cap = goal.weeklyCapSeconds / 60;
    final thisMonday = _monday(today);
    final mondays = byWeek.keys.toList()..sort();
    for (final m in mondays) {
      if (m.isBefore(thisMonday)) continue;
      final us = byWeek[m]!;
      final sum = us.fold<int>(0, (a, u) => a + u.minutes);
      if (sum > cap + 0.5) bad(day, 'Regler', 'Woche ${_iso(m)}: $sum > $cap');
      if (us.where((u) => u.isHard).length > 1) {
        bad(day, 'PAR-198', 'zwei harte Einheiten in Woche ${_iso(m)}');
      }
      if (us.length > goal.runDays.length) {
        bad(day, 'Lauftage', 'Woche ${_iso(m)} hat ${us.length} Läufe');
      }
    }
    final hard = [
      for (final u in future)
        if (u.isHard && !u.pinned) u,
    ];
    for (var i = 1; i < hard.length; i++) {
      if (hard[i].day.difference(hard[i - 1].day).inDays < p.minGapDays) {
        bad(day, 'PAR-059', 'harte Einheiten zu nah: ${_sig(hard[i])}');
      }
    }
    // Steigerung (PAR-193): ab dem Anker, ohne die Ankerwoche selbst (dort
    // gilt die Rückmeldung oder der Neustart); eine leichtere Woche (PAR-194)
    // zählt nicht als Basis, daher der größere der beiden Vorwochen.
    final anchor = inputs.anchor;
    final fullWeeks = [
      for (final m in mondays)
        if (!m.isBefore(thisMonday) && !m.isBefore(anchor)) m,
    ];
    int wm(DateTime m) =>
        (byWeek[m] ?? const <PlanUnit>[]).fold<int>(0, (a, u) => a + u.minutes);
    for (var i = 2; i < fullWeeks.length; i++) {
      final m = fullWeeks[i];
      if (m.difference(fullWeeks[i - 1]).inDays != 7) continue;
      final prev = wm(fullWeeks[i - 1]) > wm(fullWeeks[i - 2])
          ? wm(fullWeeks[i - 1])
          : wm(fullWeeks[i - 2]);
      final rate = prev < p.midThresholdMinutes
          ? p.rateBelowMid
          : (prev < p.highThresholdMinutes ? p.rateMid : p.rateHigh);
      final limit = prev * (1 + rate) + 2; // 2 min Rundung der Einheiten
      if (wm(m) > limit) {
        bad(
          day,
          'PAR-193',
          'Woche ${_iso(m)} ${wm(m)} min nach $prev min (Grenze '
              '${limit.toStringAsFixed(1)}); Wochen ab Anker '
              '${fullWeeks.take(6).map((w) => '${_iso(w)}=${wm(w)}').join(' ')}; '
              'letzte Fassung ${history.last.trigger.name}/'
              '${history.last.reason} Anker ${_iso(anchor)} '
              'Start ${inputs.startWeeklyMinutes} Zählung '
              '${inputs.weekCountOffset}',
        );
      }
    }
  }

  // Tage der künftigen Einheiten vor einer automatischen Neuberechnung.
  Future<Set<DateTime>> futureDays(int day) async => {
    for (final u in await all())
      if (!u.day.isBefore(_day(day)) && u.runId == null) u.day,
  };

  Future<void> autoCheckDays(
    int day,
    PlanTrigger t,
    Set<DateTime> before,
    bool warnedBefore,
  ) async {
    if (warnedBefore) return;
    final warnedNow = await warningStore.read() != null;
    if (warnedNow) return;
    final auto = const {
      PlanTrigger.weekly,
      PlanTrigger.run,
      PlanTrigger.feedback,
      PlanTrigger.ruleVersion,
    }.contains(t);
    if (!auto || before.isEmpty) return;
    final last = before.reduce((a, b) => a.isAfter(b) ? a : b);
    final horizonEnd = _monday(last).add(const Duration(days: 7));
    final now = {
      for (final u in await all())
        if (!u.day.isBefore(_day(day)) && u.runId == null) u.day,
    };
    // Lauftage der bisherigen Planung bleiben (ADR-0010 Punkt 8); Läufe, die
    // heute absolviert wurden, sind eingefroren und zählen nicht mehr mit.
    final kept = {
      for (final d in before)
        if (d.isBefore(horizonEnd) && !d.isBefore(_day(day))) d,
    };
    final nowInside = {
      for (final d in now)
        if (d.isBefore(horizonEnd)) d,
    };
    final done = {
      for (final u in await all())
        if (u.runId != null && !u.day.isBefore(_day(day))) u.day,
    };
    if (!nowInside.containsAll(kept.difference(done)) ||
        !kept.containsAll(nowInside)) {
      bad(
        day,
        'ADR-0010/8',
        '${t.name} änderte Tage im geplanten Zeitraum: '
            'vorher ${(kept.toList()..sort()).map(_iso)} '
            'nachher ${(nowInside.toList()..sort()).map(_iso)}',
      );
    }
  }

  // --- Ablauf -------------------------------------------------------------
  await goals.save(goal, today: _d0);
  await recalc(PlanTrigger.create, 0);
  await checkInvariants(0, PlanTrigger.create);

  // Minuten der geplanten Einheiten der Woche von [d] (ohne Ruhetage).
  Future<int> weekSum(DateTime d) async {
    final m = _monday(d);
    var sum = 0;
    for (final u in await plans.unitsBetween(
      m,
      m.add(const Duration(days: 6)),
    )) {
      if (u.kind != PlanUnitKind.rest) sum += u.minutes;
    }
    return sum;
  }

  // Tage mit manueller Neuberechnung nach einem Lauf auf verschobenem Tag
  // (am selben Tag und zwei Tage später, F1: weder doppelte Einheit noch
  // gekürzte Woche).
  final manualLater = <int>{};
  Future<void> manualCheck(int day, DateTime today) async {
    final before = await weekSum(today);
    await recalc(PlanTrigger.manual, day);
    final after = await weekSum(today);
    count('manuell_nach_verschiebung');
    if ((after - before).abs() > 2) {
      bad(day, 'Wochensumme', 'manuell: $before auf $after min');
    }
    await checkInvariants(day, PlanTrigger.manual);
  }

  var runId = 0;
  for (var day = 0; day < sc.days; day++) {
    final today = _day(day);
    final warnedBefore = await warningStore.read() != null;

    // Zieländerung des Nutzers.
    if (day == sc.goalChangeDay && sc.goalChange != null) {
      goal = sc.goalChange!;
      await goals.save(goal, today: today);
      final before = await futureDays(day);
      await recalc(PlanTrigger.goalChange, day, evaluate: false);
      await checkInvariants(day, PlanTrigger.goalChange);
      before.clear();
    }

    // Wochenprüfung beim Öffnen (FR-0158); nicht bei offener Pausenfrage
    // (PAR-202: erst die Antwort, dann die Prüfung).
    final pauseOpen =
        lastTraining != null &&
        today.difference(lastTraining).inDays >= p.pauseMinDays &&
        pauseHandled != _iso(lastTraining);
    if (!pauseOpen &&
        _weeklyDue(await settings.get(planLastCheckDayKey), today)) {
      final before = await futureDays(day);
      final week = day ~/ 7;
      final t = sc.ruleVersionWeek == week
          ? PlanTrigger.ruleVersion
          : PlanTrigger.weekly;
      await recalc(t, day, evaluate: true);
      await checkInvariants(day, t);
      await autoCheckDays(day, t, before, warnedBefore);
    }

    // Warnsignal melden und aufheben.
    if (sc.warningDay != null && day == sc.warningDay) {
      await warnings.report(
        source: WarningSource.manual,
        today: today,
        now: _now(day),
      );
      count('warnsignal');
      await checkInvariants(day, PlanTrigger.feedback);
    }
    if (sc.warningDay != null && day == sc.warningDay! + 8) {
      await warnings.lift(today: today, now: _now(day));
      await checkInvariants(day, PlanTrigger.feedback);
    }

    // Rückmeldung alle PAR-200-Tage.
    final history = await plans.history();
    if (history.isNotEmpty &&
        planFeedbackDue(created: _d0, lastAnswer: lastAnswer, today: today) &&
        !pauseOpen &&
        await warningStore.read() == null) {
      final answers = [
        PlanFeedback.tooEasy,
        PlanFeedback.tooHard,
        PlanFeedback.fits,
        PlanFeedback.tooEasy,
        PlanFeedback.tooEasy,
      ];
      final answer = answers[(stats['rueckmeldung'] ?? 0) % answers.length];
      count('rueckmeldung');
      final r = applyPlanFeedback(
        goal: goal,
        inputs: history.last.inputs.copyWith(today: today),
        answer: answer,
        today: today,
      );
      if (r.inputs != null) {
        final before = await futureDays(day);
        await recalc(PlanTrigger.feedback, day, inputs: r.inputs);
        await checkInvariants(day, PlanTrigger.feedback);
        await autoCheckDays(day, PlanTrigger.feedback, before, false);
        count('rueckmeldung_${answer.name}_wirksam');
      }
      if (r.raiseGoalSignal) count('rueckmeldung_am_regler');
      lastAnswer = today;
    }

    // Pausenregel (PAR-202), wenn die Pause lang genug ist.
    // Die Antwort kommt abwechselnd nach 14 Tagen (Stufe long) und nach 9 Tagen
    // (Stufe short, 7 bis 13 Tage); bis dahin steht die Pausenfrage offen.
    if (lastTraining != null) {
      final gap = today.difference(lastTraining).inDays;
      final mark = _iso(lastTraining);
      final answerGap = pausesAnswered.isEven ? p.pauseLongDays : 9;
      if (gap == answerGap && pauseHandled != mark) {
        pauseHandled = mark;
        pausesAnswered++;
        final h = await plans.history();
        final base = pauseBaseWeek(lastTraining);
        final restart = planPauseRestart(
          goal: goal,
          inputs: h.last.inputs.copyWith(today: today),
          today: today,
          lastTrainingDay: lastTraining,
          baseWeekMinutes: weekMinutes(base, doneByDay).toDouble(),
        );
        count('pause_${restart.kind.name}');
        if (Platform.environment.containsKey('SIM_DEBUG')) {
          // ignore: avoid_print
          print(
            'PAUSE day $day ${restart.kind.name} anchor '
            '${_iso(h.last.inputs.anchor)} monday ${_iso(_monday(today))} '
            'last ${_iso(lastTraining)} ${h.last.trigger.name}',
          );
        }
        if (restart.inputs != null) {
          await recalc(PlanTrigger.pause, day, inputs: restart.inputs);
          await checkInvariants(day, PlanTrigger.pause);
        }
      }
    }

    // Termin verschieben (nur mit Bestätigung des Nutzers).
    if (sc.moveDays.contains(day)) {
      for (var from = 3; from < 10; from++) {
        final u = await plans.unitOn(_day(day + from));
        if (u == null || u.kind == PlanUnitKind.rest || u.id == null) continue;
        var moved = false;
        for (final to in [-1, 1, 2, -2]) {
          final target = _day(day + from + to);
          if (target.isBefore(today)) continue;
          try {
            await plans.confirmMove(u.id!, target, today: today);
            confirmedPins.add(target);
            moved = true;
            count('termin_verschoben');
            break;
          } on StorageException {
            continue;
          }
        }
        if (moved) break;
      }
      await checkInvariants(day, null);
    }

    // Der Tag: laufen oder nicht.
    final unit = await plans.unitOn(today);
    final week = day ~/ 7;
    final inPause =
        sc.pause != null && day >= sc.pause!.$1 && day <= sc.pause!.$2;
    final warnedNow = await warningStore.read() != null;
    if (unit != null &&
        unit.kind != PlanUnitKind.rest &&
        unit.runId == null &&
        !inPause &&
        !warnedNow) {
      var go = rnd(100) < 85;
      if (sc.outageWeeks.contains(week)) go = rnd(100) < 15;
      if (go) {
        final created = await session.runs.create(
          startedAt: today.add(const Duration(hours: 7)),
        );
        runId = created.id;
        await plans.assignRun(unit.id!, runId);
        doneByDay[today] = unit.minutes;
        lastTraining = today;
        if (!unit.isHard) {
          easyRpe.add(sc.tiredWeeks.contains(week) ? 8 : 4 + rnd(2));
        }
        count('lauf');
        if (unit.pinned) {
          count('lauf_auf_verschobenem_tag');
          manualLater.add(day + 2);
        }
        final before = await futureDays(day);
        // Ein absolvierter Lauf in geplanter Dauer ändert die Wochensumme
        // nicht (auch nicht auf einem verschobenen Tag, F1): Wochensumme nach
        // Verschiebung und Lauf = ohne Verschiebung, bis auf Rundung.
        final weekBefore = await weekSum(today);
        await recalc(PlanTrigger.run, day);
        final weekAfter = await weekSum(today);
        if ((weekAfter - weekBefore).abs() > 2) {
          bad(
            day,
            'Wochensumme',
            'Lauf ändert die Woche von $weekBefore auf $weekAfter min'
                '${unit.pinned ? ' (verschobener Tag)' : ''}',
          );
        }
        await checkInvariants(day, PlanTrigger.run);
        await autoCheckDays(day, PlanTrigger.run, before, warnedNow);
        if (unit.pinned) await manualCheck(day, today);
      } else {
        count('lauf_ausgefallen');
      }
    }
    if (manualLater.remove(day)) await manualCheck(day, today);
    await checkInvariants(day, null);
    if (Platform.environment['SIM_DEBUG'] == '$day') {
      for (final u in await plans.unitsBetween(
        today.subtract(const Duration(days: 21)),
        today.add(const Duration(days: 28)),
      )) {
        // ignore: avoid_print
        print('U ${u.day.weekday} ${_sig(u)}');
      }
    }
    final units = await all();
    transcript.add(
      '$day|${(await plans.history()).length}|'
      '${await settings.get(planLastCheckDayKey)}|'
      '${units.map(_sig).join(';')}',
    );
  }

  final weekly = <String, int>{};
  for (final u in await all()) {
    if (u.kind == PlanUnitKind.rest) continue;
    final k = _iso(_monday(u.day));
    weekly[k] = (weekly[k] ?? 0) + u.minutes;
  }
  final h = await plans.history();
  if (Platform.environment.containsKey('SIM_DEBUG')) {
    for (final v in h) {
      final i = v.inputs;
      // ignore: avoid_print
      print(
        'V${v.id} ${_iso(v.validFrom)} ${v.trigger.name}/${v.reason} '
        'anchor=${_iso(i.anchor)} start=${i.startWeeklyMinutes} '
        'off=${i.weekCountOffset} noHard=${i.noHardUntil} '
        'share=${i.achievedShare} last=${i.lastWeekMinutes}',
      );
    }
  }
  stats['fassungen'] = h.length;
  for (final u in await all()) {
    if (u.isHard) {
      stats['harte_einheiten_im_plan'] =
          (stats['harte_einheiten_im_plan'] ?? 0) + 1;
    }
  }
  for (final v in h) {
    final nh = v.inputs.noHardUntil;
    if (nh != null) {
      stats['fassungen_mit_noHardUntil'] =
          (stats['fassungen_mit_noHardUntil'] ?? 0) + 1;
    }
  }
  return _Result(transcript, weekly, violations, stats);
}

void main() {
  final scenarios = [
    _Scenario(
      name: 'Jahr: 10 km, dann 5 km',
      days: 365,
      goal: _goal(
        distance: GoalDistance.tenKilometers,
        date: _day(380),
        stated: 150 * 60.0,
      ),
      goalChangeDay: 210,
      goalChange: _goal(
        distance: GoalDistance.fiveKilometers,
        date: _day(370),
        stated: 150 * 60.0,
      ),
      warningDay: 75,
      pause: (150, 175),
      outageWeeks: {9, 10, 30, 31, 32},
      tiredWeeks: {20, 21},
      fatigueReportedWeek: 41,
      moveDays: const [20, 45, 100, 130, 190, 240, 280, 330],
      ruleVersionWeek: 25,
    ),
    _Scenario(
      name: 'Einsteiger: 5 km mit Geh-Lauf-Abfolge',
      days: 150,
      goal: _goal(
        distance: GoalDistance.fiveKilometers,
        date: _day(170),
        c30: ContinuousRun30.no,
      ),
      warningDay: 40,
      outageWeeks: {4, 5, 12},
      moveDays: [20],
    ),
  ];

  for (final sc in scenarios) {
    test(
      '${sc.name}: Invarianten je Tag, deterministisch, unter 30 s',
      () async {
        final sw = Stopwatch()..start();
        final a = await _simulate(sc);
        final elapsed = sw.elapsed;
        final b = await _simulate(sc);
        // ignore: avoid_print
        print(
          '${sc.name}: ${elapsed.inMilliseconds} ms, ${a.stats} '
          '| Wochen: ${a.weekly.values.join(' ')}',
        );
        expect(a.violations, isEmpty, reason: a.violations.take(12).join('\n'));
        expect(b.transcript, a.transcript, reason: 'zweiter Durchlauf');
        expect(elapsed, lessThan(const Duration(seconds: 30)));
        expect(a.stats['lauf'], greaterThan(10));
        if (sc.moveDays.isNotEmpty) {
          expect(a.stats['termin_verschoben'], greaterThan(0));
        }
        if (sc.pause != null) {
          // F2: auch mit Anker aus Rückmeldung/Wochenbewertung kommt der
          // Neustart (PAR-202) bei jeder Pause, kurz wie lang (Pausen aus
          // Szenario, Warnsignal und Ausfall).
          expect(a.stats['pause_long'], greaterThanOrEqualTo(1));
          expect(a.stats['pause_short'], greaterThanOrEqualTo(1));
          expect(a.stats['pause_none'], isNull);
        }
        if (sc.moveDays.isNotEmpty) {
          expect(a.stats['manuell_nach_verschiebung'], greaterThan(0));
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  }

  // Befunde der Abschlussprüfung M2 (handoff/m2-abschluss/teil-e.md, teil-f.md).
  group('Befunde', () {
    test(
      'F1: Woche mit verschobenem, absolviertem Lauf behält die Wochenzeit',
      () async {
        final session = await FakeStorage().open(
          Uint8List.fromList(List.generate(32, (i) => i)),
        );
        final plans = (session as PlanStorage).plans;
        final goals = (session as GoalStorage).goals;
        final g = _goal(
          distance: GoalDistance.tenKilometers,
          date: _day(380),
          stated: 150 * 60.0,
        );
        await goals.save(g, today: _d0);
        Future<void> run(PlanTrigger t, int d) => recalculatePlan(
          plans: plans,
          settings: session.settings,
          trigger: t,
          today: _day(d),
          now: _now(d),
        );
        await run(PlanTrigger.create, 0);
        // Woche ab Montag (Tag 68 = Montag), Dienstag auf Montag verschieben.
        final monday = _day(grabMonday(68));
        int sum(List<PlanUnit> us) => us.fold(0, (a, u) => a + u.minutes);
        final week = await plans.unitsBetween(
          monday,
          monday.add(const Duration(days: 6)),
        );
        final before = sum(week);
        final tuesday = week.firstWhere((u) => u.day.weekday == 2);
        await plans.confirmMove(tuesday.id!, monday, today: _day(66));
        final r = (await session.runs.create(startedAt: monday)).id;
        final moved = await plans.unitOn(monday);
        await plans.assignRun(moved!.id!, r);
        await run(PlanTrigger.run, grabMonday(68));
        final after = sum(
          await plans.unitsBetween(monday, monday.add(const Duration(days: 6))),
        );
        expect(after, before);
      },
    );

    test('F2: Pausenneustart trotz Rückmeldung in der Woche davor', () {
      final g = _goal(
        distance: GoalDistance.tenKilometers,
        date: _day(380),
        stated: 150 * 60.0,
      );
      final base = PlanInputs.forNewGoal(g, _d0);
      // Mittwoch Tag 160: „zu leicht“ setzt den Anker auf den nächsten Montag.
      final feedback = applyPlanFeedback(
        goal: g,
        inputs: base.copyWith(today: _day(160)),
        answer: PlanFeedback.tooEasy,
        today: _day(160),
      );
      expect(feedback.inputs, isNotNull);
      // Donnerstag der Woche darauf, letztes Training vor 14 Tagen.
      final today = _day(168);
      final r = planPauseRestart(
        goal: g,
        inputs: feedback.inputs!.copyWith(today: today),
        today: today,
        lastTrainingDay: today.subtract(const Duration(days: 14)),
        baseWeekMinutes: 100,
      );
      expect(r.kind, PauseRestartKind.long);
    });
  });
}

int grabMonday(int d) {
  var x = d;
  while (_day(x).weekday != DateTime.monday) {
    x++;
  }
  return x;
}
