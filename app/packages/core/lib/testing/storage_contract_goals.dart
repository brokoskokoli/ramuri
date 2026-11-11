import '../core.dart';
import 'contract_support.dart';

/// Vertrag des Trainingsziels (WP21 Teil B). Der Speicher muss
/// [GoalStorage] sein.
final List<StorageContractCase> goalContractCases = [
  const StorageContractCase(
    'Ziel: anlegen, lesen, ändern, löschen, übersteht Neuöffnen',
    _lifecycle,
  ),
  const StorageContractCase(
    'Ziel: ungültiges wird abgelehnt, das bisherige bleibt',
    _invalid,
  ),
  const StorageContractCase('Ziel: Löschen ohne Ziel meldet notFound', _none),
  const StorageContractCase('Alles löschen entfernt das Ziel', _deleteAll),
];

GoalStore _g(StorageSession s) => (s as GoalStorage).goals;

TrainingGoal _goal({
  GoalType type = GoalType.time,
  GoalDistance? distance = GoalDistance.tenKilometers,
  double? targetSeconds = 3300.5,
  DateTime? targetDate,
  Set<int> runDays = const {1, 3, 6},
  double maxSession = 5400,
  double weeklyCap = 18000,
  double? currentWeekly = 7200,
  ContinuousRun30 canRun30 = ContinuousRun30.unknown,
  bool hard = true,
}) => TrainingGoal(
  hardSessionEnabled: hard,
  currentWeeklySeconds: currentWeekly,
  canRun30: canRun30,
  type: type,
  distance: distance,
  targetSeconds: targetSeconds,
  targetDate: targetDate ?? DateTime(2030, 6, 1),
  runDays: runDays,
  maxSessionSeconds: maxSession,
  weeklyCapSeconds: weeklyCap,
  createdAt: at(5, 7),
);

String _d(TrainingGoal? g) => g == null
    ? 'null'
    : '${g.type.name}/${g.distance?.name}/${g.targetSeconds}/'
          '${g.targetDate == null ? null : calendarDay(g.targetDate!)}/'
          '${(g.runDays.toList()..sort())}/${g.maxSessionSeconds}/'
          '${g.weeklyCapSeconds}/${us(g.createdAt)}/${g.hardSessionEnabled}/'
          '${g.currentWeeklySeconds}/${g.canRun30.name}';

Future<void> _lifecycle(StorageContractHarness h) async {
  var s = await h.open();
  expectTrue(await _g(s).goal() == null, 'ohne Ziel null');
  final time = _goal();
  await _g(s).save(time, today: time.createdAt);
  expectEq(_d(await _g(s).goal()), _d(time), 'Zeitziel gelesen');
  // Offenes Ziel ohne Zielzeit und Datum (FR-0137) ersetzt das Ziel.
  final openOk = TrainingGoal(
    hardSessionEnabled: false,
    canRun30: ContinuousRun30.yes,
    type: GoalType.open,
    runDays: const {1, 2, 3, 4, 5, 6, 7},
    maxSessionSeconds: 1800,
    weeklyCapSeconds: 7200,
    createdAt: at(9),
  );
  await _g(s).save(openOk, today: openOk.createdAt);
  expectEq(_d(await _g(s).goal()), _d(openOk), 'offenes Ziel ersetzt');
  final dist = _goal(
    type: GoalType.distance,
    targetSeconds: null,
    distance: GoalDistance.halfMarathon,
    runDays: const {7},
    currentWeekly: null,
    canRun30: ContinuousRun30.no,
    hard: false,
  );
  await _g(s).save(dist, today: dist.createdAt);
  await s.close();
  s = await h.open();
  expectEq(_d(await _g(s).goal()), _d(dist), 'nach Neuöffnen');
  await _g(s).delete();
  expectTrue(await _g(s).goal() == null, 'nach Löschen null');
  await s.close();
}

Future<void> _invalid(StorageContractHarness h) async {
  final s = await h.open();
  final good = _goal();
  await _g(s).save(good, today: good.createdAt);
  final bad = <String, TrainingGoal>{
    'Zeitziel ohne Zeit': _goal(targetSeconds: null),
    'Datum vor Anlegen': _goal(targetDate: DateTime(2029, 12, 31)),
    'keine Lauftage': _goal(runDays: const {}),
    'Tag 8': _goal(runDays: const {8}),
    'Zeit 0': _goal(maxSession: 0),
    'Regler 0': _goal(weeklyCap: 0),
    'Wochenzeit 0': _goal(currentWeekly: 0),
    'Wochenzeit NaN': _goal(currentWeekly: double.nan),
  };
  for (final e in bad.entries) {
    await expectFails(
      () => _g(s).save(e.value, today: e.value.createdAt),
      StorageFailure.rejected,
      e.key,
    );
  }
  // Ändern: das Datum liegt nach `createdAt`, aber vor heute.
  await expectFails(
    () => _g(s).save(good, today: DateTime(2031, 1, 1)),
    StorageFailure.rejected,
    'Datum vor heute beim Ändern',
  );
  await _g(s).save(good, today: DateTime(2030, 6, 1));
  expectEq(_d(await _g(s).goal()), _d(good), 'bisheriges Ziel bleibt');
  await s.close();
}

Future<void> _none(StorageContractHarness h) async {
  final s = await h.open();
  await expectFails(() => _g(s).delete(), StorageFailure.notFound, 'ohne Ziel');
  await s.close();
}

Future<void> _deleteAll(StorageContractHarness h) async {
  var s = await h.open();
  await _g(s).save(_goal(), today: _goal().createdAt);
  await s.deleteAll();
  expectTrue(await _g(s).goal() == null, 'Ziel nach Alles löschen');
  await s.close();
  s = await h.open();
  expectTrue(await _g(s).goal() == null, 'nach Neuöffnen');
  await s.close();
}
