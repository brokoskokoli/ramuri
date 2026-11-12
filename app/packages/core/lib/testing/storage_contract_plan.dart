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
    'Plan: Einheiten zwischen heute und Anker ersetzt die Fassung, die sie '
    'nicht enthält; die übernommenen (Brücke) bleiben',
    _bridge,
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
  const StorageContractCase(
    'Plan: Änderung zwischen Lesen und Schreiben lehnt die Fassung ab (Rennen)',
    _staleRead,
  ),
  const StorageContractCase(
    'Plan: Art ersetzen, Ruhetag festlegen und aufheben (Schema 8)',
    _replaceAndRestDay,
  ),
  const StorageContractCase(
    'Plan: hart -> locker in eine andere Woche verschoben wird kind',
    _moveEasyForHard,
  ),
  const StorageContractCase(
    'Plan: Warnsignal melden und aufheben bei fixed = kind und easyForHard '
    '(Ruhetage in gültiger Form, Festlegung kehrt zurück)',
    _warningFixed,
  ),
  const StorageContractCase('Alles löschen leert den Plan', _deleteAll),
];

/// [u] mit Art [kind] (wie ein Ersatz aus `checkPlanReplace`).
PlanUnit _as(
  PlanUnit u,
  PlanUnitKind kind, {
  int? minutes,
  List<PlanSegment>? segments,
}) => PlanUnit(
  id: u.id,
  day: u.day,
  kind: kind,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: minutes ?? u.minutes,
  segments: segments ?? u.segments,
);

PlanUnit _rest(int day) => PlanUnit(
  day: _day(day),
  kind: PlanUnitKind.rest,
  phase: PlanPhase.build,
  weekIndex: day ~/ 7,
  minutes: 0,
  segments: const [],
  pinned: true,
  fixed: PlanUnitFixed.day,
);

/// Festlegung WP22 (Review E2a Runde 3, Befund 4): Eine Einheit
/// easyForHard bleibt es beim Verschieben in ihrer Woche; in einer anderen
/// Woche wird sie kind (`planMovedFixed`), die Zielwoche behält so ihre harte
/// Einheit.
Future<void> _moveEasyForHard(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  await p.writeVersion(
    await _draft(p, 0, [
      _unit(1, kind: PlanUnitKind.tempo),
      _unit(3),
      _unit(8, week: 1, kind: PlanUnitKind.tempo),
      _unit(10, week: 1),
    ]),
  );
  final u1 = (await p.unitOn(_day(1)))!;
  await p.replaceUnit(u1.id!, _as(u1, PlanUnitKind.easy), today: _day(1));
  expectEq(
    (await p.unitOn(_day(1)))!.fixed,
    PlanUnitFixed.easyForHard,
    'hart -> locker',
  );
  await p.confirmMove(u1.id!, _day(2), today: _day(1));
  final same = (await p.unitOn(_day(2)))!;
  expectEq(same.fixed, PlanUnitFixed.easyForHard, 'gleiche Woche: bleibt');
  await p.confirmMove(u1.id!, _day(9), today: _day(1));
  final other = (await p.unitOn(_day(9)))!;
  expectEq(other.id, u1.id, 'andere Woche: gleiche Einheit');
  expectEq(other.weekIndex, 1, 'andere Woche: Woche folgt dem Tag');
  expectEq(other.kind, PlanUnitKind.easy, 'andere Woche: locker');
  expectEq(other.fixed, PlanUnitFixed.kind, 'andere Woche: kind');
  expectTrue(other.pinned, 'andere Woche: pinned');
  // Zurück in die alte Woche: bleibt ein normaler fester lockerer Lauf.
  await p.confirmMove(u1.id!, _day(4), today: _day(1));
  expectEq(
    (await p.unitOn(_day(4)))!.fixed,
    PlanUnitFixed.kind,
    'zurück: bleibt kind',
  );
  // Die harte Einheit der anderen Woche ist unberührt.
  final u8 = (await p.unitOn(_day(8)))!;
  expectEq(u8.kind, PlanUnitKind.tempo, 'Zielwoche: harte Einheit bleibt');
  expectEq(u8.fixed, PlanUnitFixed.none, 'Zielwoche: Festlegung bleibt');
  await s.close();
}

/// Review E2E 4: Ein Warnsignal über Tagen mit `fixed = kind` und
/// `easyForHard` schreibt Ruhetage, die die Speicherregeln (`fixed = day` nur
/// bei Ruhe, `easyForHard` nur bei locker) erfüllen; Aufheben stellt Art und
/// Festlegung wieder her.
Future<void> _warningFixed(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  final today = _day(0);
  final now = today.add(const Duration(hours: 8));
  final settings = s.settings;
  final warning = (s as WarningStorage).warning;
  await recalculatePlan(
    plans: p,
    settings: settings,
    trigger: PlanTrigger.create,
    today: today,
    now: now,
    warning: warning,
  );
  final goal = (await p.currentGoal())!;
  final inputs = (await p.history()).last.inputs;
  Future<void> replace(bool Function(PlanUnit) pick, PlanUnitKind kind) async {
    final units = await _all(s);
    final c = checkPlanReplace(
      units: units,
      unit: units.firstWhere(pick),
      kind: kind,
      goal: goal,
      inputs: inputs,
      today: today,
    );
    expectTrue(c.blocked == null, 'Ersatz erlaubt');
    await p.replaceUnit(units.firstWhere(pick).id!, c.unit!, today: today);
  }

  await replace(
    (u) => u.kind == PlanUnitKind.easy && u.day.isAfter(_day(14)),
    PlanUnitKind.tempo,
  );
  await replace((u) => u.isHard && u.day.isAfter(_day(30)), PlanUnitKind.easy);
  final fixedKinds = {
    for (final u in await _all(s))
      if (u.fixed != PlanUnitFixed.none) u.fixed,
  };
  expectEq(fixedKinds.map((f) => f.name).toList()..sort(), [
    'easyForHard',
    'kind',
  ], 'Ausgangsplan: kind und easyForHard');
  final before = [for (final u in await _all(s)) _fixedSig(u)];
  final service = WarningService(
    plans: p,
    settings: settings,
    warning: warning,
  );
  await service.report(source: WarningSource.manual, today: today, now: now);
  expectTrue(await warning.read() != null, 'Warnsignal gesetzt');
  expectTrue(
    (await _all(s))
        .where((u) => !u.day.isBefore(today))
        .every((u) => u.kind == PlanUnitKind.rest),
    'ab heute nur Ruhetage',
  );
  await service.lift(today: today, now: now);
  expectEq(
    [for (final u in await _all(s)) _fixedSig(u)],
    before,
    'nach dem Aufheben: Art und Festlegung wie vorher',
  );
  await s.close();
}

String _fixedSig(PlanUnit u) =>
    '${u.day.toIso8601String()}/${u.kind.name}/${u.fixed.name}/${u.pinned}/'
    '${u.minutes}';

/// Zustand samt `fixed` (ändert eine abgelehnte Änderung etwas?).
Future<String> _fixedState(StorageSession s) async =>
    '${await _state(s)}|${[for (final u in await _all(s)) '${u.id}:${u.fixed.name}']}';

Future<void> _replaceAndRestDay(StorageContractHarness h) async {
  var s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  var p = _p(s);
  await expectFails(
    () => p.setRestDay(_rest(4), today: _day(1), expectedUnitId: null),
    StorageFailure.notFound,
    'Ruhetag ohne Fassung',
  );
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(
    await _draft(p, 0, [
      _unit(0),
      _unit(1),
      _unit(2, kind: PlanUnitKind.walkRun),
      _unit(3),
      _unit(5),
      _unit(8, week: 1),
      // Nicht festgelegte Ruhe-Einheit (etwa aus Altdaten).
      _unit(9, week: 1, kind: PlanUnitKind.rest, minutes: 0),
    ]),
  );
  await p.assignRun((await p.unitOn(_day(0)))!.id!, run);
  Future<int?> idOn(int day) async => (await p.unitOn(_day(day)))?.id;
  final u1 = (await p.unitOn(_day(1)))!;
  final u3 = (await p.unitOn(_day(3)))!;

  // Ersetzen: Art, Dauer, Abschnitte aus dem Ersatz; pinned und fixed = kind
  // setzt der Speicher, Tag, Woche und Phase bleiben.
  final tempo = _as(
    u1,
    PlanUnitKind.tempo,
    minutes: 40,
    segments: const [
      PlanSegment(kind: PlanSegmentKind.warmUp, minutes: 10),
      PlanSegment(kind: PlanSegmentKind.tempo, minutes: 20),
      PlanSegment(kind: PlanSegmentKind.coolDown, minutes: 10),
    ],
  );
  await p.replaceUnit(u1.id!, tempo, today: _day(1));
  final r1 = (await p.unitOn(_day(1)))!;
  expectEq(r1.id, u1.id, 'gleiche Einheit');
  expectEq(r1.kind, PlanUnitKind.tempo, 'Art ersetzt');
  expectEq(r1.minutes, 40, 'Dauer aus dem Ersatz');
  expectEq(
    [for (final x in r1.segments) x.kind],
    [PlanSegmentKind.warmUp, PlanSegmentKind.tempo, PlanSegmentKind.coolDown],
    'Abschnitte aus dem Ersatz',
  );
  expectTrue(r1.pinned, 'ersetzt: pinned');
  expectEq(r1.fixed, PlanUnitFixed.kind, 'ersetzt: fixed = kind');
  expectEq(r1.weekIndex, u1.weekIndex, 'Woche bleibt');

  // Harte Einheit wird locker: fixed = easyForHard aus der gespeicherten
  // Einheit (planReplacedFixed), nicht aus dem Ersatz; locker wird wieder
  // hart: fixed = kind.
  await p.replaceUnit(
    u1.id!,
    _as(r1, PlanUnitKind.easy, minutes: 40).copyWith(fixed: PlanUnitFixed.kind),
    today: _day(1),
  );
  final e1 = (await p.unitOn(_day(1)))!;
  expectEq(e1.kind, PlanUnitKind.easy, 'hart -> locker: Art');
  expectEq(e1.fixed, PlanUnitFixed.easyForHard, 'hart -> locker: easyForHard');
  await p.replaceUnit(u1.id!, tempo, today: _day(1));
  expectEq(
    (await p.unitOn(_day(1)))!.fixed,
    PlanUnitFixed.kind,
    'locker -> hart: fixed = kind',
  );
  // Nur eine gespeicherte harte Einheit wird easyForHard: lang -> locker
  // bleibt kind. Danach wieder Tempo wie oben.
  await p.replaceUnit(
    u1.id!,
    _as(r1, PlanUnitKind.long, minutes: 40),
    today: _day(1),
  );
  await p.replaceUnit(
    u1.id!,
    _as(r1, PlanUnitKind.easy, minutes: 40),
    today: _day(1),
  );
  expectEq(
    (await p.unitOn(_day(1)))!.fixed,
    PlanUnitFixed.kind,
    'lang -> locker: fixed = kind',
  );
  await p.replaceUnit(u1.id!, tempo, today: _day(1));

  var before = await _fixedState(s);
  final u0 = (await p.unitOn(_day(0)))!;
  final u2 = (await p.unitOn(_day(2)))!;
  final u3tempo = _as(u3, PlanUnitKind.tempo);
  for (final (what, call, failure) in [
    (
      'Einheit mit Lauf (eingefroren)',
      () => p.replaceUnit(u0.id!, _as(u0, PlanUnitKind.tempo), today: _day(0)),
      StorageFailure.rejected,
    ),
    (
      'Einheit vor heute',
      () => p.replaceUnit(u3.id!, u3tempo, today: _day(4)),
      StorageFailure.rejected,
    ),
    (
      'Geh-Lauf nicht ersetzbar',
      () => p.replaceUnit(u2.id!, _as(u2, PlanUnitKind.tempo), today: _day(1)),
      StorageFailure.rejected,
    ),
    (
      'Art außerhalb der Auswahl',
      () =>
          p.replaceUnit(u3.id!, _as(u3, PlanUnitKind.walkRun), today: _day(1)),
      StorageFailure.rejected,
    ),
    (
      'anderer Tag im Ersatz',
      () =>
          p.replaceUnit(u3.id!, u3tempo.copyWith(day: _day(4)), today: _day(1)),
      StorageFailure.rejected,
    ),
    (
      'Einheit fehlt',
      () => p.replaceUnit(9999, u3tempo, today: _day(1)),
      StorageFailure.notFound,
    ),
  ]) {
    await expectFails(call, failure, 'Ersetzen: $what');
  }
  expectEq(await _fixedState(s), before, 'abgelehntes Ersetzen ändert nichts');

  // Ruhetag auf freiem Tag.
  await p.setRestDay(_rest(4), today: _day(1), expectedUnitId: null);
  final rest4 = (await p.unitOn(_day(4)))!;
  expectTrue(rest4.isRestDay, 'Ruhetag: rest und pinned');
  expectEq(rest4.fixed, PlanUnitFixed.day, 'Ruhetag: fixed = day');
  expectEq(rest4.minutes, 0, 'Ruhetag: 0 min');
  // Ruhetag auf Tag mit Einheit, Einheit auf freien Tag derselben Woche.
  await p.setRestDay(
    _rest(3),
    today: _day(1),
    expectedUnitId: u3.id,
    moveUnitTo: _day(6),
  );
  expectTrue((await p.unitOn(_day(3)))!.isRestDay, 'Ruhetag auf Tag 3');
  final moved = (await p.unitOn(_day(6)))!;
  expectEq(moved.id, u3.id, 'Einheit verschoben, nicht neu');
  expectTrue(moved.pinned, 'verschobene Einheit: pinned');
  // Ohne Zieltag entfällt die Einheit.
  await p.setRestDay(_rest(5), today: _day(1), expectedUnitId: await idOn(5));
  expectTrue((await p.unitOn(_day(5)))!.isRestDay, 'Ruhetag auf Tag 5');
  expectTrue(
    !(await _all(s))
        .any((u) => u.kind == PlanUnitKind.easy && u.day == _day(5)),
    'Einheit entfällt',
  );

  before = await _fixedState(s);
  final u8 = await idOn(8);
  expectTrue(u8 != null, 'Einheit auf Tag 8');
  for (final (what, call, failure) in [
    (
      'Tag vor heute',
      () => p.setRestDay(_rest(1), today: _day(2), expectedUnitId: u1.id),
      StorageFailure.rejected,
    ),
    (
      'Einheit mit Lauf',
      () => p.setRestDay(_rest(0), today: _day(0), expectedUnitId: u0.id),
      StorageFailure.rejected,
    ),
    (
      'schon Ruhetag',
      () => p.setRestDay(_rest(4), today: _day(1), expectedUnitId: rest4.id),
      StorageFailure.rejected,
    ),
    (
      // Tag 10 ist frei; abgelehnt wird nur wegen der anderen Woche.
      'Zieltag in anderer Woche',
      () => p.setRestDay(
        _rest(1),
        today: _day(1),
        expectedUnitId: u1.id,
        moveUnitTo: _day(10),
      ),
      StorageFailure.rejected,
    ),
    (
      'Zieltag belegt',
      () => p.setRestDay(
        _rest(1),
        today: _day(1),
        expectedUnitId: u1.id,
        moveUnitTo: _day(2),
      ),
      StorageFailure.rejected,
    ),
    (
      'Zieltag vor heute',
      () => p.setRestDay(
        _rest(8),
        today: _day(8),
        expectedUnitId: u8,
        moveUnitTo: _day(7),
      ),
      StorageFailure.rejected,
    ),
    (
      'Zieltag ohne Einheit',
      () => p.setRestDay(
        _rest(12),
        today: _day(1),
        expectedUnitId: null,
        moveUnitTo: _day(13),
      ),
      StorageFailure.rejected,
    ),
    (
      'keine Ruhetag-Einheit',
      () => p.setRestDay(
        _unit(12, week: 1, pinned: true),
        today: _day(1),
        expectedUnitId: null,
      ),
      StorageFailure.rejected,
    ),
    // Der Tag hat sich seit der Prüfung geändert (FR-0176): nichts entfällt
    // ohne Bestätigung.
    (
      'Einheit erwartet, Tag frei',
      () => p.setRestDay(_rest(12), today: _day(1), expectedUnitId: u8),
      StorageFailure.rejected,
    ),
    (
      'Tag frei erwartet, Einheit da',
      () => p.setRestDay(_rest(8), today: _day(1), expectedUnitId: null),
      StorageFailure.rejected,
    ),
    (
      'andere Einheit erwartet',
      () => p.setRestDay(_rest(8), today: _day(1), expectedUnitId: u1.id),
      StorageFailure.rejected,
    ),
    (
      // Eine Ruhe-Einheit wird zum Ruhetag, sie wird nicht verlegt.
      'Ruhe-Einheit mit Zieltag',
      () async => p.setRestDay(
        _rest(9),
        today: _day(1),
        expectedUnitId: await idOn(9),
        moveUnitTo: _day(10),
      ),
      StorageFailure.rejected,
    ),
    (
      'Ruhetag nicht ersetzbar',
      () => p.replaceUnit(
        rest4.id!,
        _as(rest4, PlanUnitKind.easy, minutes: 30),
        today: _day(1),
      ),
      StorageFailure.rejected,
    ),
  ]) {
    await expectFails(call, failure, 'Ruhetag: $what');
  }
  expectEq(await _fixedState(s), before, 'abgelehnter Ruhetag ändert nichts');

  // Eine nicht festgelegte Ruhe-Einheit lässt sich festlegen (Schutz vor der
  // Neuberechnung, OQ-0011) und danach aufheben.
  final gen9 = (await p.unitOn(_day(9)))!;
  expectTrue(!gen9.isRestDay, 'Ruhe-Einheit Tag 9 nicht festgelegt');
  await p.setRestDay(_rest(9), today: _day(1), expectedUnitId: gen9.id);
  final rest9 = (await p.unitOn(_day(9)))!;
  expectTrue(rest9.isRestDay, 'Ruhe-Einheit festgelegt');
  expectEq(rest9.fixed, PlanUnitFixed.day, 'Ruhe-Einheit: fixed = day');
  expectEq(
    (await _all(s)).where((u) => u.day == _day(9)).length,
    1,
    'genau eine Einheit auf Tag 9',
  );
  await p.clearRestDay(_day(9), today: _day(1));
  expectTrue(await p.unitOn(_day(9)) == null, 'festgelegte Ruhe aufgehoben');

  // Übersteht Neuöffnen.
  await s.close();
  s = await h.open();
  p = _p(s);
  expectEq((await p.unitOn(_day(1)))!.fixed, PlanUnitFixed.kind, 'kind neu');
  expectEq((await p.unitOn(_day(4)))!.fixed, PlanUnitFixed.day, 'day neu');

  // Aufheben.
  before = await _fixedState(s);
  await expectFails(
    () => p.clearRestDay(_day(1), today: _day(1)),
    StorageFailure.notFound,
    'Aufheben: kein Ruhetag',
  );
  await expectFails(
    () => p.clearRestDay(_day(3), today: _day(4)),
    StorageFailure.rejected,
    'Aufheben: Tag vor heute',
  );
  expectEq(await _fixedState(s), before, 'abgelehntes Aufheben ändert nichts');
  await p.clearRestDay(_day(4), today: _day(1));
  expectTrue(await p.unitOn(_day(4)) == null, 'Ruhetag aufgehoben, Tag frei');
  expectTrue((await p.unitOn(_day(3)))!.isRestDay, 'anderer Ruhetag bleibt');
  await expectFails(
    () => p.clearRestDay(_day(4), today: _day(1)),
    StorageFailure.notFound,
    'Aufheben: schon aufgehoben',
  );
  await s.close();
}

Future<void> _unitMethods(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  await p.writeVersion(
    await _draft(p, 0, [_unit(1), _unit(2, kind: PlanUnitKind.walkRun)]),
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
  PlanUnitFixed fixed = PlanUnitFixed.none,
}) => PlanUnit(
  day: _day(day),
  fixed: fixed,
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

/// Entwurf auf dem jetzigen Stand des Plans (wie der Dienst nach dem Lesen).
Future<PlanVersionDraft> _draft(
  PlanRepository p,
  int validFrom,
  List<PlanUnit> units, {
  PlanTrigger trigger = PlanTrigger.create,
  String reason = 'start',
}) async => PlanVersionDraft(
  createdAt: at(100 + validFrom, 3),
  validFrom: _day(validFrom),
  trigger: trigger,
  reason: reason,
  version: const PlanVersion(),
  inputs: _inputs(validFrom),
  summary: {'larger': false, 'changedUnitCount': units.length},
  units: units,
  readState: planUnitsFingerprint(
    await p.unitsBetween(_inputs(validFrom).anchor, planFarFuture),
  ),
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
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  expectEq((await _p(s).currentGoal())?.runDays, {1, 3, 6}, 'currentGoal');
  expectEq((await _p(s).history()).length, 0, 'noch keine Fassung');

  final units = [
    _unit(2, withIntensity: true),
    _unit(0, kind: PlanUnitKind.intervals, minutes: 40, pinned: true),
    _unit(5, kind: PlanUnitKind.long, minutes: 60, week: 0),
    _unit(7, week: 1),
  ];
  final rec = await _p(s).writeVersion(await _draft(_p(s), 0, units));
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
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(
    await _draft(p, 0, [for (var d = 0; d < 8; d++) _unit(d, week: d ~/ 7)]),
  );
  // Tag 1: Vergangenheit (heute = 3); Tag 5: künftig, aber mit Lauf.
  final past = (await p.unitOn(_day(1)))!;
  final withRun = (await p.unitOn(_day(5)))!;
  await p.assignRun(withRun.id!, run);
  final before = {for (final u in await _all(s)) u.day.day: _u(u)};

  await p.writeVersion(
    await _draft(p, 3, [
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

/// NB5 6: Liegt der Anker der neuen Fassung nach „heute“ (nach „zu schwer“,
/// PAR-200), ersetzt `writeVersion` alle offenen Einheiten ab `validFrom`,
/// auch die zwischen heute und Anker. Was die Fassung nicht mitbringt, ist weg;
/// die Brücke von `recalculatePlan` muss sie also im Entwurf tragen.
Future<void> _bridge(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  await p.writeVersion(
    await _draft(p, 0, [
      for (final d in [1, 3, 5, 8, 10]) _unit(d),
    ]),
  );
  Future<PlanVersionDraft> next(List<PlanUnit> units) async => PlanVersionDraft(
    createdAt: at(103, 3),
    validFrom: _day(3),
    trigger: PlanTrigger.weekly,
    reason: 'noIncrease',
    version: const PlanVersion(),
    inputs: _inputs(3).copyWith(anchor: _day(7)),
    summary: const {},
    units: units,
    readState: planUnitsFingerprint(
      await p.unitsBetween(_day(7), planFarFuture),
    ),
  );
  // Mit Brücke (Tag 3 und 5 unverändert im Entwurf): beide bleiben.
  final bridge = [for (final u in await p.unitsBetween(_day(3), _day(6))) u];
  expectEq(bridge.map((u) => u.day.day), [_day(3).day, _day(5).day], 'Brücke');
  await p.writeVersion(await next([...bridge, _unit(8, minutes: 20)]));
  var days = [for (final u in await _all(s)) u.day.day];
  expectEq(days, [
    for (final d in [1, 3, 5, 8]) _day(d).day,
  ], 'mit Brücke');
  // Ohne Brücke fehlen Tag 3 und 5 danach; Tag 1 (vor heute) bleibt.
  await p.writeVersion(await next([_unit(8, minutes: 25)]));
  days = [for (final u in await _all(s)) u.day.day];
  expectEq(days, [
    for (final d in [1, 8]) _day(d).day,
  ], 'ohne Brücke');
  await s.close();
}

Future<void> _invalid(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(await _draft(p, 0, [_unit(0), _unit(2), _unit(4)]));
  // Ein Lauf kam nach dem Lesen des Dienstes dazu: Tag 4 trägt jetzt einen
  // Lauf; ein Entwurf mit einer neuen Einheit auf Tag 4 wäre ein Doppel.
  await p.assignRun((await p.unitOn(_day(4)))!.id!, run);
  final good = await _state(s);

  final bad = <String, PlanVersionDraft>{
    'negative Dauer': await _draft(p, 1, [
      _unit(1),
      _unit(2),
      _unit(3, minutes: -1),
    ]),
    'Woche -1': await _draft(p, 1, [_unit(1), _unit(3, week: -1)]),
    'Tag vor Beginn': await _draft(p, 2, [_unit(2), _unit(1)]),
    'neue Einheit mit Lauf': await _draft(p, 1, [
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
    'Tag trägt schon eine Einheit mit Lauf': await _draft(p, 1, [
      _unit(1),
      _unit(4),
    ]),
    'leerer Grund': await _draft(p, 1, [_unit(1)], reason: ''),
    // CHECK von plan_units: fixed = day nur bei Ruhe, easyForHard nur bei
    // locker (E2E 4: Der Fake lehnt wie die Datenbank ab).
    'Ruhetag mit fixed = kind': await _draft(p, 1, [
      _unit(
        1,
        kind: PlanUnitKind.rest,
        minutes: 0,
        pinned: true,
        fixed: PlanUnitFixed.kind,
      ),
    ]),
    'nicht bestätigt (pinned = false) mit fixed = kind': await _draft(p, 1, [
      _unit(
        1,
        kind: PlanUnitKind.easy,
        pinned: false,
        fixed: PlanUnitFixed.kind,
      ),
    ]),
    'Tempo mit fixed = easyForHard': await _draft(p, 1, [
      _unit(
        1,
        kind: PlanUnitKind.tempo,
        pinned: true,
        fixed: PlanUnitFixed.easyForHard,
      ),
    ]),
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

Future<void> _staleRead(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(
    await _draft(p, 0, [_unit(0), _unit(2), _unit(4), _unit(6)]),
  );
  final withRun = (await p.unitOn(_day(0)))!;
  await p.assignRun(withRun.id!, run);

  // Jede Änderung nach dem Lesen macht den Entwurf ungültig.
  final changes = <String, Future<void> Function()>{
    'Termin bestätigt': () async =>
        p.confirmMove((await p.unitOn(_day(6)))!.id!, _day(7), today: _day(3)),
    // Gleicher Tag: ändert nur `pinned` (Fingerabdruck, NB4 Soll 2).
    'am selben Tag bestätigt': () async =>
        p.confirmMove((await p.unitOn(_day(5)))!.id!, _day(5), today: _day(3)),
    'Lauf zugeordnet': () async =>
        p.assignRun((await p.unitOn(_day(2)))!.id!, run),
    'Lauf entfernt': () => p.assignRun(withRun.id!, null),
    'andere Fassung': () async {
      await p.writeVersion(
        await _draft(p, 3, [_unit(3)], trigger: PlanTrigger.weekly),
      );
    },
  };
  for (final c in changes.entries) {
    final stale = await _draft(p, 3, [_unit(3), _unit(5)]);
    await c.value();
    final before = await _state(s);
    await expectFails(
      () => p.writeVersion(stale),
      StorageFailure.rejected,
      c.key,
    );
    expectEq(await _state(s), before, 'alter Plan bleibt (${c.key})');
    // Neu gelesen gelingt es.
    await p.writeVersion(
      await _draft(p, 3, [_unit(3), _unit(5)], trigger: PlanTrigger.weekly),
    );
  }

  // Ersetzen einer schon gepinnten Einheit ändert nur Art und `fixed`; auch
  // das macht den Entwurf ungültig (Fingerabdruck).
  final five = (await p.unitOn(_day(5)))!;
  await p.confirmMove(five.id!, _day(5), today: _day(3));
  final stale = await _draft(p, 3, [_unit(3), _unit(5)]);
  await p.replaceUnit(
    five.id!,
    _as((await p.unitOn(_day(5)))!, PlanUnitKind.tempo),
    today: _day(3),
  );
  final before = await _state(s);
  await expectFails(
    () => p.writeVersion(stale),
    StorageFailure.rejected,
    'Art ersetzt (schon gepinnt)',
  );
  expectEq(await _state(s), before, 'alter Plan bleibt (Art ersetzt)');
  await s.close();
}

Future<void> _noGoal(StorageContractHarness h) async {
  final s = await h.open();
  await expectFails(
    () async => _p(s).writeVersion(await _draft(_p(s), 0, [_unit(0)])),
    StorageFailure.notFound,
    'ohne Ziel',
  );
  expectEq((await _p(s).history()).length, 0, 'nichts geschrieben');
  await s.close();
}

Future<void> _edit(StorageContractHarness h) async {
  final s = await h.open();
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final p = _p(s);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await p.writeVersion(
    await _draft(p, 0, [_unit(0), _unit(2), _unit(4), _unit(8)]),
  );
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

  await p.confirmMove(u2.id!, _day(3), today: _day(2));
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
  await expectFails(
    () => p.confirmMove(u8.id!, _day(12), today: _day(10)),
    StorageFailure.rejected,
    'Einheit liegt vor heute (Geschichte)',
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
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final run = (await s.runs.create(startedAt: at(0))).id;
  await _p(s).writeVersion(await _draft(_p(s), 0, [_unit(0), _unit(2)]));
  await _p(s).assignRun((await _p(s).unitOn(_day(0)))!.id!, run);

  // Ziel ändern (ersetzen) lässt den Plan stehen.
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
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
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final run = (await s.runs.create(startedAt: at(0))).id;
  final other = (await s.runs.create(startedAt: at(1))).id;
  await _p(s)
      .writeVersion(await _draft(_p(s), 0, [_unit(0), _unit(2), _unit(4)]));
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
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  await _p(s).writeVersion(await _draft(_p(s), 0, [_unit(0), _unit(2)]));
  await s.settings.set(planLastCheckDayKey, '2030-03-04', at: at(1));
  await s.deleteAll();
  expectTrue(await _p(s).currentGoal() == null, 'Ziel weg');
  expectEq((await _all(s)).length, 0, 'Einheiten weg');
  expectEq((await _p(s).history()).length, 0, 'Fassungen weg');
  await s.close();
  s = await h.open();
  expectEq((await _all(s)).length, 0, 'nach Neuöffnen');
  // Zähler beginnen neu (wie bei den Läufen).
  await (s as GoalStorage).goals.save(_goal(), today: _goal().createdAt);
  final rec = await _p(s).writeVersion(await _draft(_p(s), 0, [_unit(0)]));
  expectEq(rec.id, 1, 'Fassungszähler neu');
  expectEq((await _p(s).unitOn(_day(0)))!.id, 1, 'Einheitenzähler neu');
  await s.close();
}
