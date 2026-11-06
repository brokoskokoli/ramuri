import '../../ports/storage.dart';
import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/fitness_result.dart';
import '../fitness/heart_rate_basis.dart';
import '../fitness/vo2max_estimator.dart';
import '../fitness/vo2max_section_selection.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../preprocessing/run_preprocessor.dart';

/// Schlüssel der gespeicherten Werte (`ComputedValue.key`).
const String vo2maxRunValueKey = 'vo2max_run';
const String vo2maxLongTermValueKey = 'vo2max_long_term';
const String aerobicEfficiencyValueKey = 'aerobic_efficiency_change';

const String vo2maxUnit = 'ml/kg/min';
const String percentUnit = '%';

/// Ergebnis der Rechnung für einen Lauf: Abschnittsauswahl und Schätzung aus
/// den gespeicherten Rohdaten (ADR-0004 Punkt 1: Rohdaten sind die Quelle).
class RunAnalysis {
  RunAnalysis({
    required this.run,
    required this.selection,
    required this.estimate,
    required Set<String> sources,
  }) : sources = Set.unmodifiable(sources);

  final StoredRun run;
  final SectionSelection selection;
  final Vo2maxRunEstimate estimate;

  /// Quellgeräte und -quellen der Rohdaten des Laufs (FR-0053).
  final Set<String> sources;

  DateTime get endedAt => run.endedAt!;

  /// Der VO₂max-Laufwert mit den Angaben aus FR-0053 und allen bewerteten
  /// Abschnitten (FR-0073), auch den abgelehnten, in Zeitreihenfolge.
  ComputedValue vo2maxValue(DateTime computedAt) {
    final sections = valueSectionsOf(selection, estimate);
    return toComputedValue(
      key: vo2maxRunValueKey,
      unit: vo2maxUnit,
      value: estimate.result,
      computedAt: computedAt,
      sections: sections,
    );
  }
}

/// Die EINE Stelle, die bewertete Abschnitte in die Speicherform wandelt
/// (FR-0073): alle Abschnitte der Auswahl in Zeitreihenfolge. Mit Schätzung des
/// Schätzers über [ValueSection.fromEstimate], ohne (abgelehnt, oder der
/// Schätzer kam nicht bis dahin) über [ValueSection.withoutEstimate].
List<ValueSection> valueSectionsOf(
  SectionSelection selection,
  Vo2maxRunEstimate estimate,
) {
  final byIdentity = <Object, SectionEstimate>{
    for (final e in estimate.sections) e.section: e,
  };
  return [
    for (final s in selection.sections)
      if (byIdentity[s] case final e?)
        ValueSection.fromEstimate(e)
      else
        ValueSection.withoutEstimate(s),
  ];
}

/// Überträgt einen fortgeschrittenen Wert in die Speicherform. „Nicht
/// bestimmbar“ wird ohne Wert, aber mit Grund gespeichert (FR-0068).
ComputedValue toComputedValue({
  required String key,
  required String unit,
  required AdvancedFitnessValue<double> value,
  required DateTime computedAt,
  List<ValueSection> sections = const [],
  HeartRateBasis? heartRateBasis,
}) {
  final m = value.metadata;
  return ComputedValue(
    key: key,
    value: value.value,
    unavailableReason: value.reason,
    heartRateBasis: heartRateBasis,
    unit: unit,
    computedAt: computedAt,
    dataFrom: m.dataFrom,
    dataTo: m.dataTo,
    measurementCount: m.usableMeasurements,
    sources: (m.dataSources.toList()..sort()),
    method: m.method,
    methodVersion: m.methodVersion,
    parameterVersion: m.parameterVersion,
    quality: switch (m.tier) {
      QualityTier.preliminary => ValueQuality.provisional,
      QualityTier.sufficient => ValueQuality.sufficient,
      QualityTier.good => ValueQuality.good,
      QualityTier.notDeterminable => ValueQuality.undeterminable,
    },
    sections: sections,
  );
}

/// Rückweg für den Langzeitwert: ein gespeicherter Laufwert als Eingabe.
/// `null` für „nicht bestimmbar“ (ändert den Langzeitwert nicht, FR-0080).
AdvancedFitnessValue<double>? toAdvancedValue(ComputedValue v) {
  final tier = switch (v.quality) {
    ValueQuality.provisional => QualityTier.preliminary,
    ValueQuality.sufficient => QualityTier.sufficient,
    ValueQuality.good => QualityTier.good,
    ValueQuality.undeterminable => null,
  };
  final from = v.dataFrom;
  final to = v.dataTo;
  if (tier == null || v.value == null || from == null || to == null) {
    return null;
  }
  return AdvancedFitnessValue<double>(
    value: v.value,
    metadata: FitnessValueMetadata(
      calculatedAt: v.computedAt,
      dataFrom: from,
      dataTo: to,
      usableMeasurements: v.measurementCount,
      dataSources: v.sources.toSet(),
      method: v.method,
      methodVersion: v.methodVersion,
      parameterVersion: v.parameterVersion,
      tier: tier,
    ),
  );
}

/// Rechnet einen beendeten Lauf aus seinen gespeicherten Rohdaten.
///
/// Die Herzfrequenzbasis [basis] geht an die Abschnittsauswahl und an den
/// Schätzer; es gibt nur diese eine Quelle je Rechnung.
class RunAnalyzer {
  RunAnalyzer({
    required this.fitness,
    required this.preprocessing,
    required this.basis,
  });

  final FitnessParameters fitness;
  final PreprocessingParameters preprocessing;
  final HeartRateBasis basis;

  /// Wirft [ArgumentError] bei abweichender Parameterversion zwischen
  /// Vorverarbeitung und Fitness; das wird nicht abgefangen.
  Future<RunAnalysis> analyze(
    StorageSession session,
    StoredRun run, {
    required DateTime calculatedAt,
  }) async {
    final end = run.endedAt;
    if (run.state != RunState.finished || end == null) {
      throw ArgumentError.value(run.id, 'run', 'Lauf ist nicht beendet');
    }
    final raw = await session.rawData.read(run.id);
    final gaps = await session.markers.gaps(run.id);
    final sources = <String>{
      for (final r in raw.positions) r.value.source,
      for (final r in raw.heartRates) r.value.source,
      for (final r in raw.altitudes) r.value.source,
      for (final r in raw.steps) r.value.source,
    };
    final SectionSelection selection;
    if (!end.isAfter(run.startedAt)) {
      // Lauf ohne Dauer: nichts auszuwählen, der Schätzer meldet den Grund.
      selection = SectionSelection(
        parameterVersion: fitness.parameterVersion,
        sections: const [],
        excluded: const [],
      );
    } else {
      final pre = _replay(run, end, raw, gaps);
      selection = Vo2maxSectionSelector(parameters: fitness)
          .select(run: pre, basis: basis, runStart: run.startedAt, until: end);
    }
    final estimate = const AcsmReserveVo2maxEstimator().estimate(
      selection: selection,
      basis: basis,
      p: fitness,
      calculatedAt: calculatedAt,
      runStart: run.startedAt,
      runEnd: end,
      dataSources: sources,
    );
    return RunAnalysis(
      run: run,
      selection: selection,
      estimate: estimate,
      sources: sources,
    );
  }

  /// Spielt die Rohdaten in zeitlicher Reihenfolge durch die Vorverarbeitung,
  /// samt manueller Pausen. Bei gleicher Zeit: erst Fortsetzen, dann Messwerte,
  /// dann Pausieren.
  RunPreprocessing _replay(
    StoredRun run,
    DateTime end,
    StoredRawData raw,
    List<StoredGap> gaps,
  ) {
    final pre = RunPreprocessor(
      start: run.startedAt,
      parameters: preprocessing,
    );
    final events = <({DateTime at, int rank, void Function() apply})>[];
    void add(DateTime at, int rank, void Function() apply) =>
        events.add((at: at, rank: rank, apply: apply));
    for (final g in gaps) {
      if (g.kind != RunGapKind.manualPause) continue;
      add(g.start, 2, () => pre.pause(g.start));
      final resume = g.end ?? end;
      add(resume, 0, () => pre.resume(resume));
    }
    for (final r in raw.positions) {
      add(r.value.time, 1, () => pre.addPosition(r.value));
    }
    for (final r in raw.heartRates) {
      add(r.value.time, 1, () => pre.addHeartRate(r.value));
    }
    for (final r in raw.altitudes) {
      add(r.value.time, 1, () => pre.addAltitude(r.value));
    }
    for (final r in raw.steps) {
      add(r.value.time, 1, () => pre.addSteps(r.value));
    }
    // Dart-Sortierung ist nicht stabil: Reihenfolge der Einfügung als Schlüssel.
    final indexed = [for (var i = 0; i < events.length; i++) (i, events[i])]
      ..sort((a, b) {
        final c = a.$2.at.compareTo(b.$2.at);
        if (c != 0) return c;
        final r = a.$2.rank.compareTo(b.$2.rank);
        return r != 0 ? r : a.$1.compareTo(b.$1);
      });
    for (final e in indexed) {
      e.$2.apply();
    }
    return pre.result(at: end);
  }
}
