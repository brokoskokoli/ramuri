import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/aerobic_efficiency.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/vo2max_long_term.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../profile/heart_rate_resolution.dart';
import 'run_analysis.dart';

/// Die Werte, die nach einem Lauf entstehen.
class RunCalculationResult {
  const RunCalculationResult({
    required this.runValue,
    required this.longTerm,
    required this.efficiency,
    required this.day,
  });

  /// VO₂max-Laufwert (Besitzer: der Lauf).
  final ComputedValue runValue;

  /// Langzeitwert und aerobe Effizienz (Besitzer: der Tag [day]).
  final ComputedValue longTerm;
  final ComputedValue efficiency;
  final String day;
}

/// Zwischenstand einer Neuberechnung: alle neuen Werte, noch nicht gespeichert.
class ValueSnapshot {
  const ValueSnapshot({required this.runValues, required this.dayValues});

  final Map<ValueOwner, List<ComputedValue>> runValues;
  final Map<ValueOwner, List<ComputedValue>> dayValues;
}

/// ISO-Datum (UTC) `JJJJ-MM-TT` eines Zeitpunkts, Besitzer der Tageswerte.
String isoDay(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
}

/// Rechnet VO₂max-Laufwert, Langzeitwert und aerobe Effizienz aus den
/// gespeicherten Rohdaten (FR-0066 bis FR-0087) und speichert sie als
/// `original` und `current` mit den Angaben aus FR-0053 und den bewerteten
/// Abschnitten (FR-0073). Netzwerkfrei (SEC-0006), Zeit nur über [Clock].
///
/// Tageswerte (Langzeitwert, aerobe Effizienz) gehören dem UTC-Tag der
/// Berechnung. Gibt es für den Tag schon einen Wert, wird sein `current`
/// getauscht, das `original` ist dann der erste Wert des Tages.
class ValueCalculationService {
  ValueCalculationService({
    required this.session,
    required this.clock,
    this.fitness = const FitnessParameters.v3(),
    this.preprocessing = const PreprocessingParameters.v3(),
    this.longTerm = const SmoothedVo2maxLongTerm(),
    this.efficiency = const MedianAerobicEfficiency(),
  });

  final StorageSession session;
  final Clock clock;
  final FitnessParameters fitness;
  final PreprocessingParameters preprocessing;
  final Vo2maxLongTerm longTerm;
  final AerobicEfficiency efficiency;

  /// Herzfrequenzbasis des gespeicherten Profils (FR-0003, FR-0004).
  Future<RunAnalyzer> _analyzer() async {
    final resolved = resolveHeartRate(
      await session.profile.read(),
      currentYear: clock.now().year,
      fitness: fitness,
    );
    return RunAnalyzer(
      fitness: fitness,
      preprocessing: preprocessing,
      basis: resolved.basis,
    );
  }

  Future<List<StoredRun>> _finishedRuns() async => [
    for (final r in await session.runs.list())
      if (r.state == RunState.finished && r.endedAt != null) r,
  ];

  /// Rechnet den beendeten Lauf [runId] und speichert seine Werte samt den
  /// Tageswerten. Ein Lauf, der schon Werte hat, ist `rejected` (ein Original
  /// wird nie ersetzt). Eine abweichende Parameterversion wirft
  /// [ArgumentError].
  Future<RunCalculationResult> calculateAfterRun(int runId) async {
    final now = clock.now();
    final run = await session.runs.get(runId);
    if (run == null) throw const StorageException(StorageFailure.notFound);
    final analyzer = await _analyzer();
    final analysis = await analyzer.analyze(session, run, calculatedAt: now);
    final runValue = analysis.vo2maxValue(now);
    await session.values.createOriginals(ValueOwner.run(runId), [runValue]);

    final runValues = <int, ComputedValue>{runId: runValue};
    for (final other in await _finishedRuns()) {
      if (other.id == runId) continue;
      final stored = await _runValue(other.id);
      if (stored != null) runValues[other.id] = stored.current;
    }
    final cache = <int, RunAnalysis>{runId: analysis};
    final day = await _dayValues(
      asOf: now,
      computedAt: now,
      runValues: runValues,
      analysisOf: (r) async =>
          cache[r.id] ??= await analyzer.analyze(session, r, calculatedAt: now),
    );
    await _writeDayValues(isoDay(now), day);
    return RunCalculationResult(
      runValue: runValue,
      longTerm: day.first,
      efficiency: day.last,
      day: isoDay(now),
    );
  }

  /// Nach dem Löschen eines Laufs: Langzeit- und Tageswerte aller Tage mit
  /// einem Lauf neu rechnen (die Speicherschicht hat überlappende Tageswerte
  /// gelöscht). Laufwerte bleiben unverändert (OQ-0065); fehlende Tageswerte
  /// werden neu angelegt, vorhandene im `current` getauscht.
  Future<void> refreshAfterDelete() async {
    final now = clock.now();
    final runs = await _finishedRuns();
    if (runs.isEmpty) return;
    final analyzer = await _analyzer();
    final runValues = <int, ComputedValue>{};
    for (final r in runs) {
      final stored = await _runValue(r.id);
      if (stored != null) runValues[r.id] = stored.current;
    }
    final cache = <int, RunAnalysis>{};
    final days = <String>{for (final r in runs) isoDay(r.endedAt!)};
    for (final day in days.toList()..sort()) {
      final asOf = _asOf(day, now);
      final values = await _dayValues(
        asOf: asOf,
        computedAt: now,
        runValues: runValues,
        analysisOf: (r) async => cache[r.id] ??= await analyzer.analyze(
          session,
          r,
          calculatedAt: now,
        ),
      );
      await _writeDayValues(day, values);
    }
  }

  /// Rechnet alle Läufe mit gespeichertem Laufwert und deren Tageswerte neu,
  /// ohne etwas zu speichern (Zwischenstand der Neuberechnung). Tageswerte
  /// nur für Tage, die schon einen haben.
  Future<ValueSnapshot> buildSnapshot() async {
    final now = clock.now();
    final runs = await _finishedRuns();
    final analyzer = await _analyzer();
    final cache = <int, RunAnalysis>{};
    Future<RunAnalysis> analysisOf(StoredRun r) async =>
        cache[r.id] ??= await analyzer.analyze(session, r, calculatedAt: now);

    final runValues = <int, ComputedValue>{};
    final runOwners = <ValueOwner, List<ComputedValue>>{};
    for (final r in runs) {
      if (await _runValue(r.id) == null) continue;
      final value = (await analysisOf(r)).vo2maxValue(now);
      runValues[r.id] = value;
      runOwners[ValueOwner.run(r.id)] = [value];
    }
    final dayOwners = <ValueOwner, List<ComputedValue>>{};
    final days = <String>{for (final r in runs) isoDay(r.endedAt!)};
    for (final day in days.toList()..sort()) {
      final existing = {
        for (final p in await session.values.read(ValueOwner.day(day)))
          p.original.key,
      };
      if (existing.isEmpty) continue;
      final values = await _dayValues(
        asOf: _asOf(day, now),
        computedAt: now,
        runValues: runValues,
        analysisOf: analysisOf,
      );
      final swappable = [
        for (final v in values)
          if (existing.contains(v.key)) v,
      ];
      if (swappable.isNotEmpty) dayOwners[ValueOwner.day(day)] = swappable;
    }
    return ValueSnapshot(runValues: runOwners, dayValues: dayOwners);
  }

  /// Zeitpunkt, für den der Tageswert des Tages [day] gilt: Ende des Tages,
  /// für den heutigen Tag jetzt.
  DateTime _asOf(String day, DateTime now) {
    final start = DateTime.parse('${day}T00:00:00Z');
    final end = start.add(const Duration(days: 1, microseconds: -1));
    return end.isAfter(now) ? now : end;
  }

  Future<ValuePair?> _runValue(int runId) async {
    for (final p in await session.values.read(ValueOwner.run(runId))) {
      if (p.original.key == vo2maxRunValueKey) return p;
    }
    return null;
  }

  /// Langzeitwert und aerobe Effizienz zum Zeitpunkt [asOf]; in dieser
  /// Reihenfolge.
  Future<List<ComputedValue>> _dayValues({
    required DateTime asOf,
    required DateTime computedAt,
    required Map<int, ComputedValue> runValues,
    required Future<RunAnalysis> Function(StoredRun) analysisOf,
  }) async {
    final long = longTerm.compute(
      runs: [for (final v in runValues.values) ?toAdvancedValue(v)],
      p: fitness,
      now: asOf,
    );
    final span = fitness.aerobicEfficiency.windowLength * 2;
    final from = asOf.subtract(span);
    final inputs = <EfficiencyRun>[];
    final sources = <String>{};
    for (final r in await _finishedRuns()) {
      final end = r.endedAt!;
      if (end.isBefore(from) || end.isAfter(asOf)) continue;
      final a = await analysisOf(r);
      inputs.add(EfficiencyRun(endedAt: end, selection: a.selection));
      sources.addAll(a.sources);
    }
    final eff = efficiency.compute(
      runs: inputs,
      p: fitness,
      now: asOf,
      dataSources: sources,
    );
    return [
      toComputedValue(
        key: vo2maxLongTermValueKey,
        unit: vo2maxUnit,
        value: long,
        computedAt: computedAt,
      ),
      toComputedValue(
        key: aerobicEfficiencyValueKey,
        unit: percentUnit,
        value: eff.change,
        computedAt: computedAt,
      ),
    ];
  }

  Future<void> _writeDayValues(String day, List<ComputedValue> values) async {
    final owner = ValueOwner.day(day);
    final existing = {
      for (final p in await session.values.read(owner)) p.original.key,
    };
    final swap = [
      for (final v in values)
        if (existing.contains(v.key)) v,
    ];
    final create = [
      for (final v in values)
        if (!existing.contains(v.key)) v,
    ];
    if (create.isNotEmpty) await session.values.createOriginals(owner, create);
    if (swap.isNotEmpty) await session.values.swapCurrent(owner, swap);
  }
}
