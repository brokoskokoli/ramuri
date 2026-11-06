import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_derived.dart';
import '../../ports/storage_runs.dart';
import '../preprocessing/gap_moving_time.dart' show overlapDuration;
import '../preprocessing/movement_time_processor.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../preprocessing/run_preprocessor.dart';
import '../recalculation/run_analysis.dart';
import '../recalculation/run_load_values.dart';
import '../recalculation/value_calculation_service.dart' show dayOfRun;
import 'run_figures.dart';

/// Kennung der gespeicherten Kurzfassung (`PreprocessingSummary.method`).
const String runOverviewMethod = 'run-overview';
const int runOverviewMethodVersion = 1;

/// Die Kurzfassung eines Laufs für Listen und Vergleiche, abgeleitet aus der
/// Vorverarbeitung (ADR-0004 Punkt 1: jederzeit aus den Rohdaten neu
/// berechenbar). Gespeichert werden die Zusammenfassung und die Spannen
/// `moving` und `positionGap`; Messwert-Zeilen nicht.
StoredPreprocessing overviewOf(
  RunPreprocessing pre, {
  required DateTime computedAt,
}) => StoredPreprocessing(
  summary: PreprocessingSummary(
    method: runOverviewMethod,
    methodVersion: runOverviewMethodVersion,
    parameterVersion: pre.parameterVersion,
    computedAt: computedAt,
    totalTime: pre.movement.totalTime,
    movingTime: pre.movement.movingTime,
    distanceMeters: pre.position.distanceMeters,
    bridgedDistanceMeters: pre.position.bridgedDistanceMeters,
    averageBpm: pre.heartRate.averageBpm,
    maxBpm: pre.heartRate.maxBpm,
  ),
  spans: [
    for (final m in pre.movement.movingIntervals)
      PreprocessedSpan(
        kind: PreprocessedSpanKind.moving,
        start: m.start,
        end: m.end,
      ),
    for (final g in pre.position.gaps)
      PreprocessedSpan(
        kind: PreprocessedSpanKind.positionGap,
        start: g.start,
        end: g.end,
      ),
  ],
);

/// Kennzahlen eines beendeten Laufs für die Liste. Was fehlt, ist `null`
/// (nie 0).
class RunOverview {
  RunOverview({
    required this.run,
    this.distanceMeters,
    this.movingTime,
    this.totalTime,
    this.paceTime,
    this.averageHeartRateBpm,
    this.maxHeartRateBpm,
    this.readFailed = false,
    this.load = StoredRunLoad.none,
  });

  final StoredRun run;

  /// Zonenzeiten und TRIMP, wie am Lauf gespeichert (nicht mit dem aktuellen
  /// Profil gerechnet).
  final StoredRunLoad load;

  /// Die Rohdaten des Laufs ließen sich nicht lesen; alle Kennzahlen fehlen.
  final bool readFailed;
  final double? distanceMeters;
  final Duration? movingTime;
  final Duration? totalTime;

  /// Zeit, die zur Durchschnittspace zählt (K20): Bewegungszeit ohne die Zeit
  /// in Positionslücken. `null`, wenn nichts übrig bleibt.
  final Duration? paceTime;
  final double? averageHeartRateBpm;
  final int? maxHeartRateBpm;

  /// Dieselbe Rechnung wie [RunFigures.averagePaceSecondsPerKm].
  double? get averagePaceSecondsPerKm => toFigures().averagePaceSecondsPerKm;

  /// Gewicht des Durchschnittspulses im Mittel über mehrere Läufe. Die
  /// Kurzfassung trägt die Zahl der akzeptierten Pulswerte nicht; als Näherung
  /// gilt die Bewegungszeit in Sekunden (Pulswerte kommen etwa im Sekundentakt).
  /// Ohne Durchschnittspuls 0 (der Lauf geht nicht ein). Ob die Anzahl
  /// gespeichert werden soll, entscheidet der Maintainer.
  int get _heartRateWeight {
    if (averageHeartRateBpm == null) return 0;
    final seconds = (movingTime ?? totalTime)?.inSeconds ?? 0;
    return seconds > 0 ? seconds : 1;
  }

  /// Für Vergleich ([classifyRun]) und Zeitraumstatistik; ohne Teile, die die
  /// Kurzfassung nicht trägt (Bestpace, Runden). Die Pulsanzahl ist eine
  /// Näherung ([_heartRateWeight]). Zonen und TRIMP
  /// kommen aus den gespeicherten Werten ([load]).
  RunFigures toFigures() => RunFigures(
    runId: run.id,
    endedAt: run.endedAt!,
    day: dayOfRun(run),
    distanceMeters: distanceMeters,
    movingTime: movingTime,
    totalTime: totalTime,
    paceTime: paceTime,
    heartRateAverageBpm: averageHeartRateBpm,
    heartRateMaxBpm: maxHeartRateBpm,
    heartRateSampleCount: _heartRateWeight,
    zoneTimes: load.zoneTimes,
    belowZone1Time: load.belowZone1Time,
    trimpPoints: load.trimpPoints,
    trimpIncomplete: load.trimpIncomplete,
  );

  /// Aus der gespeicherten Kurzfassung. Die Zeit in Positionslücken ist die
  /// Überlappung der Spannen (K20, wie `movingTimeInPositionGaps`).
  factory RunOverview.fromStored(
    StoredRun run,
    StoredPreprocessing stored, {
    StoredRunLoad load = StoredRunLoad.none,
  }) {
    final s = stored.summary;
    List<TimeSpan> spans(PreprocessedSpanKind kind) => [
      for (final p in stored.spans)
        if (p.kind == kind && p.end != null)
          TimeSpan(start: p.start, end: p.end!),
    ];
    final moving = s.movingTime;
    Duration? paceTime;
    if (moving != null) {
      final loss = overlapDuration(
        spans(PreprocessedSpanKind.moving),
        spans(PreprocessedSpanKind.positionGap),
      );
      final t = moving - loss;
      paceTime = t > Duration.zero ? t : null;
    }
    return RunOverview(
      run: run,
      distanceMeters: s.distanceMeters,
      movingTime: moving,
      totalTime: s.totalTime,
      paceTime: paceTime,
      averageHeartRateBpm: s.averageBpm,
      maxHeartRateBpm: s.maxBpm,
      load: load,
    );
  }
}

/// Liefert die Läufe für die Historie mit ihren Kennzahlen. Gelesen wird in
/// einer Abfrage für alle Läufe (`runs.list`, `preprocessing.readOverviews`,
/// `values.readRunValues`),
/// nicht je Lauf. Nur für Läufe ohne gespeicherte Kurzfassung (Berechnung nach
/// dem Lauf fehlgeschlagen, ältere Parameterversion) werden die Rohdaten
/// gelesen, neu gerechnet und die Kurzfassung gespeichert.
class RunOverviewService {
  RunOverviewService({
    required this.session,
    required this.clock,
    this.parameters = const PreprocessingParameters.v4(),
  });

  final StorageSession session;
  final Clock clock;
  final PreprocessingParameters parameters;

  /// Beendete Läufe, neuester Start zuerst (Reihenfolge von `runs.list`).
  /// Unfertige Läufe fehlen.
  Future<List<RunOverview>> load() async {
    final runs = [
      for (final r in await session.runs.list())
        if (r.state == RunState.finished && r.endedAt != null) r,
    ];
    final stored = await session.preprocessing.readOverviews();
    // Zonenzeiten und TRIMP: eine Abfrage für alle Läufe.
    final loads = await session.values.readRunValues(runLoadValueKeys);
    final result = <RunOverview>[];
    for (final run in runs) {
      final s = stored[run.id];
      final load = StoredRunLoad.fromValues(loads[run.id] ?? const {});
      if (s != null && _isCurrent(s.summary)) {
        result.add(RunOverview.fromStored(run, s, load: load));
      } else {
        result.add(await _recompute(run, load));
      }
    }
    return result;
  }

  /// Gespeichert in dem Format und mit den Parametern, die wir lesen können.
  bool _isCurrent(PreprocessingSummary s) =>
      s.method == runOverviewMethod &&
      s.methodVersion == runOverviewMethodVersion &&
      s.parameterVersion == parameters.parameterVersion;

  Future<RunOverview> _recompute(StoredRun run, StoredRunLoad load) async {
    final end = run.endedAt!;
    if (!end.isAfter(run.startedAt)) return RunOverview(run: run, load: load);
    final RunPreprocessing pre;
    try {
      pre = replayRunPreprocessing(
        run: run,
        end: end,
        raw: await session.rawData.read(run.id),
        gaps: await session.markers.gaps(run.id),
        parameters: parameters,
      );
    } on StorageException {
      // Ein Lauf, der nicht lesbar ist, lässt die Historie nicht scheitern.
      return RunOverview(run: run, readFailed: true, load: load);
    }
    final stored = overviewOf(pre, computedAt: clock.now());
    try {
      await session.preprocessing.replace(run.id, stored);
    } on StorageException {
      // Nur das Merken scheitert; die Anzeige gilt.
    }
    return RunOverview.fromStored(run, stored, load: load);
  }
}
