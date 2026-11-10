import '../core.dart';
import 'contract_support.dart';

/// Vertrag des gespeicherten Plans (WP21 Teil C). Der Speicher muss
/// [GoalStorage] und [PlanStorage] sein.
final List<StorageContractCase> planContractCases = [
  const StorageContractCase(
    'Plan: Fassung schreiben, Einheiten und Verlauf lesen, übersteht Neuöffnen',
    _roundTrip,
  ),
  const StorageContractCase(
    'Plan: neue Fassung ersetzt nur offene künftige Einheiten',
    _replaceOpenFuture,
  ),
  const StorageContractCase(
    'Plan: ungültige Fassung wird abgelehnt, der alte Plan bleibt',
    _invalid,
  ),
  const StorageContractCase('Plan: ohne Ziel meldet notFound', _noGoal),
  const StorageContractCase('Plan: Lauf zuordnen und Termin bestätigen', _edit),
  const StorageContractCase(
    'Plan: Ziel löschen kaskadiert, Ziel ersetzen nicht',
    _goalCascade,
  ),
  const StorageContractCase(
    'Plan: Lauf löschen hebt nur die Zuordnung auf',
    _runDeleted,
  ),
  const StorageContractCase(
    'Plan: Einheit trägt beim Lesen ihre Methode, Geh-Lauf-Einheit die der Abfolge',
    _unitMethods,
  ),
  const StorageContractCase('Alles löschen leert den Plan', _deleteAll),
];

Future<void> _unitMethods(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal());
  final p = _p(s);
  await p.writeVersion(
    _draft(0, [_unit(1), _unit(2, kind: PlanUnitKind.walkRun)]),
  );
  Future<void> check(StorageSession s, String when) async {
    final q = _p(s);
    final easy = (await q.unitOn(_day(1)))!;
    final walk = (await q.unitOn(_day(2)))!;
    expectEq(easy.method, planMethod, 'Methode locker $when');
    expectEq(easy.methodVersion, planMethodVersion, 'Version locker $when');
    expectEq(walk.method, walkRunMethod, 'Methode Geh-Lauf $when');
    expectEq(walk.methodVersion, walkRunMethodVersion, 'Version GL $when');
    final v = (await q.history()).single.version;
    expectEq(v.parameterVersion, planRuleVersion, 'Gesamtversion $when');
  }

  await check(s, 'direkt');
  await s.close();
  final again = await h.open();
  await check(again, 'nach Neuöffnen');
  await again.close();
}

PlanRepository _p(StorageSession s) => (s as PlanStorage).plans;

final DateTime _d0 = DateTime.utc(2030, 3, 4); // Montag

DateTime _day(int n) => _d0.add(Duration(days: n));

TrainingGoal _goal() => TrainingGoal(
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2031, 6, 1),
  runDays: const {1, 3, 6},
  maxSessionSeconds: 5400,
  weeklyCapSeconds: 18000,
  createdAt: at(5, 7),
);

PlanUnit _unit(
  int day, {
  PlanUnitKind kind = PlanUnitKind.easy,
  int minutes = 30,
  int week = 0,
  bool withIntensity = false,
  bool pinned = false,
}) => PlanUnit(
  day: _day(day),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: week,
  minutes: minutes,
  pinned: pinned,
  segments: [
    PlanSegment(
      kind: PlanSegmentKind.warmUp,
      minutes: 5,
      intensity: withIntensity
          ? const PlanTargetIntensity(
              rpeMin: 2,
              rpeMax: 3,
              paceFastSecondsPerKm: 330.5,
              paceSlowSecondsPerKm: 360,
              basisCode: 'basisX',
              hrMinBpm: 130,
              hrMaxBpm: 148,
              estimated: true,
              maxHrEstimated: true,
              paceIsLimit: true,
            )
          : null,
    ),
    PlanSegment(kind: PlanSegmentKind.easy, minutes: minutes - 5),
    if (withIntensity)
      const PlanSegment(kind: PlanSegmentKind.walk, minutes: 2, seconds: 90),
  ],
);

PlanInputs _inputs(int day) => PlanInputs(
  anchor: _d0,
  startWeeklyMinutes: 90,
  today: _day(day),
  easyPaceSecondsPerKm: 345.5,
  easyRunCount: 4,
);

PlanVersionDraft _draft(
  int validFrom,
  List<PlanUnit> units, {
  PlanTrigger trigger = PlanTrigger.create,
  String reason = 'start',
}) => PlanVersionDraft(
  createdAt: at(100 + validFrom, 3),
  validFrom: _day(validFrom),
  trigger: trigger,
  reason: reason,
  version: const PlanVersion(),
  inputs: _inputs(validFrom),
  summary: {'larger': false, 'changedUnitCount': units.length},
  units: units,
);

String _u(PlanUnit u) =>
    '${u.day.toIso8601String()}/${u.kind.name}/${u.phase.name}/${u.weekIndex}/'
    '${u.minutes}/${u.runId}/${u.pinned}/${u.method}/${u.methodVersion}/'
    '${[for (final s in u.segments) '${s.kind.name}:${s.minutes}:${s.seconds}:${s.intensity == null ? '-' : '${s.intensity!.rpeMin}'
                ',${s.intensity!.rpeMax},${s.intensity!.paceFastSecondsPerKm}'
                ',${s.intensity!.paceSlowSecondsPerKm},${s.intensity!.basisCode},'
                '${s.intensity!.hrMinBpm},${s.intensity!.hrMaxBpm},${s.intensity!.estimated},'
                '${s.intensity!.maxHrEstimated},${s.intensity!.paceIsLimit}'}']}';

Future<List<PlanUnit>> _all(StorageSession s) =>
    _p(s).unitsBetween(_day(-400), _day(400));

Future<String> _state(StorageSession s) async {
  final units = await _all(s);
  final hist = await _p(s).history();
  return '${units.map(_u).toList()}|${hist.map((h) => h.id).toList()}';
}

Future<void> _roundTrip(StorageContractHarness h) async {
  var s = await h.open();
  expectTrue(await _p(s).currentGoal() == null, 'ohne Ziel null');
  await (s as GoalStorage).goals.save(_goal());
  expectEq((await _p(s).currentGoal())?.runDays, {1, 3, 6}, 'currentGoal');
  expectEq((await _p(s).history()).length, 0, 'noch keine Fassung');

  final units = [
    _unit(2, withIntensity: true),
    _unit(0, kind: PlanUnitKind.intervals, minutes: 40, pinned: true),
    _unit(5, kind: PlanUnitKind.long, minutes: 60, week: 0),
    _unit(7, week: 1),
  ];
  final rec = await _p(s).writeVersion(_draft(0, units));
  expectEq(rec.id, 1, 'Kennung der Fassung');
  expectEq(rec.goalId, 1, 'Ziel');
  expectEq(rec.trigger.name, 'create', 'Auslöser');
  expectEq(rec.reason, 'start', 'Grund');
  expectEq(rec.validFrom.toIso8601String(), _day(0).toIso8601String(), 'ab');

  Future<void> check(StorageSession s, String when) async {
    final got = await _all(s);
    final want = [...units]..sort((a, b) => a.day.compareTo(b.day));
    expectEq(got.map(_u), want.map(_u), 'Einheiten $when');
    expectTrue(got.every((u) => u.id != null), 'Kennungen $when');
    expectEq(
      (await _p(s).unitsBetween(_day(2), _day(5))).map((u) => u.day.day),
      [_day(2).day, _day(5).day],
      'unitsBetween schließt Grenzen ein $when',
    );
    expectEq(_u((await _p(s).unitOn(_day(2)))!), _u(want[1]), 'unitOn $when');
    expectTrue(await _p(s).unitOn(_day(3)) == null, 'unitOn leer $when');
    final hist = await _p(s).history();
    expectEq(hist.length, 1, 'Verlauf $when');
    final r = hist.single;
    expectEq(us(r.createdAt), us(at(100, 3)), 'Zeitpunkt $when');
    expectEq(r.version == const PlanVersion(), true, 'Version $when');
    expectEq(
      r.inputs.toJson().toString(),
      _inputs(0).toJson().toString(),
      'Eingaben $when',
    );
    expectEq(r.summary['changedUnitCount'], 4, 'Zusammenfassung $when');
  }

  await check(s, 'direkt');
  await s.close();
  s = await h.open();
  await check(s, 'nach Neuöffnen');
  await s.close();
}

Future<void> _replaceOpenFuture(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal());
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(
    _draft(0, [for (var d = 0; d < 8; d++) _unit(d, week: d ~/ 7)]),
  );
  // Tag 1: Vergangenheit (heute = 3); Tag 5: künftig, aber mit Lauf.
  final past = (await p.unitOn(_day(1)))!;
  final withRun = (await p.unitOn(_day(5)))!;
  await p.assignRun(withRun.id!, run);
  final before = {for (final u in await _all(s)) u.day.day: _u(u)};

  await p.writeVersion(
    _draft(3, [
      _unit(3, kind: PlanUnitKind.tempo, minutes: 45),
      _unit(4, minutes: 25),
      _unit(6, minutes: 20, week: 0),
      _unit(10, week: 1),
    ], trigger: PlanTrigger.weekly),
  );
  final after = {for (final u in await _all(s)) u.day.day: u};
  expectEq(after.keys.toList()..sort(), [
    for (final d in [0, 1, 2, 3, 4, 5, 6, 10]) _day(d).day,
  ], 'Tage nach der Neuberechnung');
  for (final d in [0, 1, 2]) {
    expectEq(_u(after[_day(d).day]!), before[_day(d).day], 'Tag $d bleibt');
  }
  expectEq(after[_day(1).day]!.id, past.id, 'Vergangenes behält die Kennung');
  expectEq(_u(after[_day(5).day]!), before[_day(5).day], 'Lauf-Tag bleibt');
  expectEq(after[_day(5).day]!.runId, run, 'Zuordnung bleibt');
  expectEq(after[_day(3).day]!.kind, PlanUnitKind.tempo, 'Tag 3 ersetzt');
  expectEq(after[_day(4).day]!.minutes, 25, 'Tag 4 ersetzt');
  expectEq(after[_day(6).day]!.minutes, 20, 'Tag 6 ersetzt');
  final hist = await p.history();
  expectEq(hist.map((x) => x.id), [1, 2], 'Verlauf');
  expectEq(hist.last.trigger.name, 'weekly', 'Auslöser der zweiten Fassung');
  await s.close();
}

Future<void> _invalid(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal());
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(_draft(0, [_unit(0), _unit(2), _unit(4)]));
  final good = await _state(s);

  final bad = <String, PlanVersionDraft>{
    'negative Dauer': _draft(1, [_unit(1), _unit(2), _unit(3, minutes: -1)]),
    'Woche -1': _draft(1, [_unit(1), _unit(3, week: -1)]),
    'Tag vor Beginn': _draft(2, [_unit(2), _unit(1)]),
    'neue Einheit mit Lauf': _draft(1, [
      _unit(1),
      PlanUnit(
        day: _day(3),
        kind: PlanUnitKind.easy,
        phase: PlanPhase.build,
        weekIndex: 0,
        minutes: 30,
        segments: const [],
        runId: run,
      ),
    ]),
    'leerer Grund': _draft(1, [_unit(1)], reason: ''),
  };
  for (final e in bad.entries) {
    await expectFails(
      () => p.writeVersion(e.value),
      StorageFailure.rejected,
      e.key,
    );
    expectEq(await _state(s), good, 'alter Plan bleibt (${e.key})');
  }
  await s.close();
}

Future<void> _noGoal(StorageContractHarness h) async {
  final s = await h.open();
  await expectFails(
    () => _p(s).writeVersion(_draft(0, [_unit(0)])),
    StorageFailure.notFound,
    'ohne Ziel',
  );
  expectEq((await _p(s).history()).length, 0, 'nichts geschrieben');
  await s.close();
}

Future<void> _edit(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal());
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(_draft(0, [_unit(0), _unit(2), _unit(4), _unit(8)]));
  final u0 = (await p.unitOn(_day(0)))!;
  final u2 = (await p.unitOn(_day(2)))!;
  final u8 = (await p.unitOn(_day(8)))!;

  await p.assignRun(u0.id!, run);
  expectEq((await p.unitOn(_day(0)))!.runId, run, 'zugeordnet');
  await expectFails(
    () => p.assignRun(u0.id!, run + 99),
    StorageFailure.notFound,
    'Lauf fehlt',
  );
  await expectFails(
    () => p.assignRun(9999, run),
    StorageFailure.notFound,
    'Einheit fehlt',
  );
  await p.assignRun(u0.id!, null);
  expectTrue((await p.unitOn(_day(0)))!.runId == null, 'Zuordnung aufgehoben');
  await p.assignRun(u0.id!, run);

  await p.confirmMove(u2.id!, _day(3), today: _day(3));
  final moved = (await p.unitOn(_day(3)))!;
  expectEq(moved.id, u2.id, 'verschoben');
  expectTrue(moved.pinned, 'pinned gesetzt');
  expectEq(moved.weekIndex, 0, 'gleiche Woche');
  expectTrue(await p.unitOn(_day(2)) == null, 'alter Tag frei');
  await p.confirmMove(u2.id!, _day(9), today: _day(0));
  final next = (await p.unitOn(_day(9)))!;
  expectEq(next.weekIndex, 1, 'Woche folgt dem Tag');
  await expectFails(
    () => p.confirmMove(u8.id!, _day(9), today: _day(0)),
    StorageFailure.rejected,
    'Tag belegt',
  );
  await expectFails(
    () => p.confirmMove(u0.id!, _day(1), today: _day(0)),
    StorageFailure.rejected,
    'Einheit mit Lauf',
  );
  await expectFails(
    () => p.confirmMove(9999, _day(1), today: _day(0)),
    StorageFailure.notFound,
    'Einheit fehlt',
  );
  await expectFails(
    () => p.confirmMove(u2.id!, _day(1), today: _day(2)),
    StorageFailure.rejected,
    'Tag vor heute',
  );
  expectTrue(
    (await p.unitOn(_day(9))) != null && await p.unitOn(_day(1)) == null,
    'abgelehnte Verschiebung ändert nichts',
  );
  expectTrue(await p.unitOn(_day(0)) != null, 'Lauf-Einheit blieb');
  await s.close();
}

Future<void> _goalCascade(StorageContractHarness h) async {
  var s = await h.open();
  await (s as GoalStorage).goals.save(_goal());
  final run = (await s.runs.create(startedAt: at(0))).id;
  await _p(s).writeVersion(_draft(0, [_unit(0), _unit(2)]));
  await _p(s).assignRun((await _p(s).unitOn(_day(0)))!.id!, run);

  // Ziel ändern (ersetzen) lässt den Plan stehen.
  await (s as GoalStorage).goals.save(_goal());
  expectEq((await _all(s)).length, 2, 'Ziel ersetzt: Einheiten bleiben');
  expectEq((await _p(s).history()).length, 1, 'Ziel ersetzt: Fassung bleibt');

  await (s as GoalStorage).goals.delete();
  expectEq((await _all(s)).length, 0, 'Einheiten weg');
  expectEq((await _p(s).history()).length, 0, 'Fassungen weg');
  expectTrue(await s.runs.get(run) != null, 'Lauf bleibt');
  await s.close();
  s = await h.open();
  expectEq((await _all(s)).length, 0, 'nach Neuöffnen');
  await s.close();
}

Future<void> _runDeleted(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal());
  final run = (await s.runs.create(startedAt: at(0))).id;
  final other = (await s.runs.create(startedAt: at(1))).id;
  await _p(s).writeVersion(_draft(0, [_unit(0), _unit(2), _unit(4)]));
  await _p(s).assignRun((await _p(s).unitOn(_day(0)))!.id!, run);
  await _p(s).assignRun((await _p(s).unitOn(_day(2)))!.id!, other);
  await s.deleteRun(run);
  final units = await _all(s);
  expectEq(units.length, 3, 'alle Einheiten bleiben');
  expectEq(units.map((u) => u.runId), [null, other, null], 'nur Zuordnung weg');
  expectEq((await _p(s).history()).length, 1, 'Fassung bleibt');
  await s.close();
}

Future<void> _deleteAll(StorageContractHarness h) async {
  var s = await h.open();
  await (s as GoalStorage).goals.save(_goal());
  await _p(s).writeVersion(_draft(0, [_unit(0), _unit(2)]));
  await s.settings.set(planLastCheckDayKey, '2030-03-04', at: at(1));
  await s.deleteAll();
  expectTrue(await _p(s).currentGoal() == null, 'Ziel weg');
  expectEq((await _all(s)).length, 0, 'Einheiten weg');
  expectEq((await _p(s).history()).length, 0, 'Fassungen weg');
  await s.close();
  s = await h.open();
  expectEq((await _all(s)).length, 0, 'nach Neuöffnen');
  // Zähler beginnen neu (wie bei den Läufen).
  await (s as GoalStorage).goals.save(_goal());
  final rec = await _p(s).writeVersion(_draft(0, [_unit(0)]));
  expectEq(rec.id, 1, 'Fassungszähler neu');
  expectEq((await _p(s).unitOn(_day(0)))!.id, 1, 'Einheitenzähler neu');
  await s.close();
}
