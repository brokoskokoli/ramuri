import '../health/health_processing.dart';
import '../health/health_types.dart';
import '../load/training_load.dart' show LoadDay;
import '../morning/morning_logic.dart' show sleepBandHours;
import '../morning/morning_marks.dart' show MorningRmssdMark;
import '../../ports/storage_morning.dart' show SleepBand;
import '../subjective/subjective_limits.dart' show checkWellbeing;
import 'readiness_deviation.dart';
import 'readiness_explanation.dart';
import 'readiness_level.dart';
import 'readiness_parameters.dart';
import 'readiness_precedence.dart';
import 'readiness_release.dart';
import 'readiness_result.dart';
import 'readiness_scales.dart';

/// Befinden beim letzten Lauf (PAR-169): Stufe 1 bis 5 und Ortstag des Laufs.
class ReadinessWellbeing {
  const ReadinessWellbeing({required this.level, required this.day});

  final int level;

  /// Ortstag des Laufs als UTC-Datum (nur Jahr, Monat, Tag zählen).
  final DateTime day;

  @override
  String toString() => 'ReadinessWellbeing()';
}

/// TSB% für PAR-168 aus einem Tag des Belastungsverlaufs: fehlt, solange
/// PAR-073 oder PAR-090 das Maß sperren ([LoadDay.tsbThresholdsLocked]) oder
/// das 7-Tage-Mittel fehlt.
double? readinessTsbPercent(LoadDay? day) {
  if (day == null || day.tsbThresholdsLocked) return null;
  return day.tsbPercentMean7;
}

/// Eingaben des Modells. Alles kommt über Parameter, nichts wird gelesen.
class ReadinessInputs {
  const ReadinessInputs({
    required this.today,
    required this.now,
    this.hrvHealthConnect,
    this.restingHrHealthConnect,
    this.cameraDeviations = const [],
    this.release = const CameraRelease(developerMode: false, rmssdOptIn: false),
    this.sleepSessions = const [],
    this.sleepBand,
    this.tsbPercent,
    this.wellbeing,
    this.processing = const HealthProcessing(),
    this.hrvSourceSpanDays = 0,
  });

  /// Ortstag als UTC-Datum.
  final DateTime today;

  /// Zeitpunkt für die Hauptschlafphase (PAR-164: Ende in den letzten 16 h).
  final DateTime now;

  /// Health-Connect-Reihe je Faktor (Teil A, PAR-189).
  final DeviationResult? hrvHealthConnect;
  final DeviationResult? restingHrHealthConnect;

  /// Alle Kamerareihen (Teil A, `cameraDeviations`).
  final Iterable<DeviationResult> cameraDeviations;

  /// Validierungssperre (Teil B).
  final CameraRelease release;

  /// Schlafsitzungen aus Health Connect (alle Quellen); die Hauptschlafphase
  /// wählt [HealthProcessing.mainSleep].
  final Iterable<SleepSession> sleepSessions;

  /// Selbstangabe der Schlafdauer der letzten Nacht (PAR-164K/165K), gilt nur,
  /// wenn Health Connect keine Hauptschlafphase liefert. Die Zuordnung zur
  /// letzten Nacht (Messung heute) macht der Aufrufer.
  final SleepBand? sleepBand;

  /// TSB% nach PAR-073, `null` bei Sperre ([readinessTsbPercent]).
  final double? tsbPercent;

  final ReadinessWellbeing? wellbeing;
  final HealthProcessing processing;

  /// Tage vom ersten gültigen Wert der gewählten HRV-Reihe bis heute
  /// (PAR-150, [readinessSourceSpanDays]); 0 heißt unbekannt und erfüllt
  /// „gleiche Datenquelle seit 28 Tagen“ nicht.
  final int hrvSourceSpanDays;
}

ReadinessBand readinessBandOf(int value) {
  if (value >= readinessBandWellRecoveredFrom) {
    return ReadinessBand.wellRecovered;
  }
  if (value >= readinessBandNormalFrom) return ReadinessBand.normal;
  if (value >= readinessBandElevatedFrom) return ReadinessBand.elevatedLoad;
  return ReadinessBand.recoveryAdvised;
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

bool _fresh(DeviationResult? r) =>
    r != null &&
    (r.hasZ ||
        (r.reason != NoDeviationReason.noSeries &&
            r.reason != NoDeviationReason.noValueToday));

/// Berechnet Zahl, eingeschränkte Einschätzung oder „Unzureichende Daten“
/// (FR-0109 bis FR-0111, FR-0116, PAR-163 bis PAR-171K, OQ-0006). Rein und
/// deterministisch.
ReadinessResult computeReadiness(ReadinessInputs input) {
  final cams = input.cameraDeviations.toList();
  final hrv = chooseFactor(
    factor: ReadinessFactor.hrv,
    healthConnect: input.hrvHealthConnect,
    camera: cams,
    cameraReleased: true,
    seriesReleased: input.release.isReleased,
  );
  final rhr = chooseFactor(
    factor: ReadinessFactor.restingHeartRate,
    healthConnect: input.restingHrHealthConnect,
    camera: cams,
    cameraReleased: true,
    seriesReleased: input.release.isReleased,
  );

  final factors = <ReadinessFactorValue>[];
  final facts = <ReadinessFact>[];
  final marked = <ReadinessFact>[];

  void deviationFactor(
    FactorEvaluation e,
    ReadinessFactorId id,
    double weight,
    ReadinessFactKind kind,
  ) {
    final c = e.chosen;
    if (c != null) {
      final mark = _markOf(input.release, c);
      factors.add(
        ReadinessFactorValue(
          id: id,
          source: factorSourceOf(c.source),
          weight: weight,
          score: readinessScaleZ(c.z!),
          mark: mark,
          fewMeasurements: c.fewMeasurements,
          referenceCount: c.referenceCount,
        ),
      );
      facts.add(
        ReadinessFact(
          kind: kind,
          source: factorSourceOf(c.source),
          z: c.z,
          mark: mark,
          fewMeasurements: c.fewMeasurements,
        ),
      );
    }
    for (final o in e.others) {
      // Nur gesperrte Kamerareihen mit `z` werden als markierte Tatsache
      // gezeigt; sie gehen nie in Faktor oder Zahl. Vor der Freischaltung der
      // Morgenmessung ohne Entwicklermodus gibt es gar keine Kamerawerte
      // (K62 Punkt 1), auch keine Tatsache.
      if (input.release.cameraValuesAllowed &&
          o.source == ReadinessSource.camera &&
          o.hasZ &&
          !input.release.isReleased(o)) {
        marked.add(
          ReadinessFact(
            kind: kind,
            source: ReadinessFactorSource.camera,
            z: o.z,
            mark: input.release
                .forFactor(o.factor, o.cameraSeries!.posture)
                .mark,
            fewMeasurements: o.fewMeasurements,
          ),
        );
      }
    }
  }

  deviationFactor(
    hrv,
    ReadinessFactorId.hrv,
    readinessWeightHrv,
    ReadinessFactKind.hrvDeviation,
  );
  deviationFactor(
    rhr,
    ReadinessFactorId.restingHeartRate,
    readinessWeightRestingHr,
    ReadinessFactKind.restingHeartRateDeviation,
  );

  double? sleepHoursForExplanation;

  // Schlaf: Health Connect (PAR-164, 166, 167) vor Selbstangabe (PAR-164K).
  final main = input.processing.mainSleep(input.sleepSessions, input.now);
  if (main != null) {
    final s = input.processing.sleepSummary(main);
    final hours = s.sleepDuration.inMicroseconds / Duration.microsecondsPerHour;
    sleepHoursForExplanation = hours;
    factors.add(
      ReadinessFactorValue(
        id: ReadinessFactorId.sleep,
        source: ReadinessFactorSource.healthConnect,
        weight: readinessWeightSleep,
        score: readinessScaleSleep(
          hours: hours,
          efficiencyPercent: s.efficiencyPercent,
          processing: input.processing,
        ),
        estimated: s.isEstimate,
      ),
    );
    facts.add(
      ReadinessFact(
        kind: ReadinessFactKind.sleepDuration,
        source: ReadinessFactorSource.healthConnect,
        hours: hours,
        estimated: s.isEstimate,
      ),
    );
  } else if (input.sleepBand != null) {
    final hours = sleepBandHours(input.sleepBand!);
    sleepHoursForExplanation = hours;
    factors.add(
      ReadinessFactorValue(
        id: ReadinessFactorId.sleep,
        source: ReadinessFactorSource.selfReport,
        weight: readinessWeightSleep,
        score: readinessScaleSleep(hours: hours, efficiencyPercent: null),
      ),
    );
    facts.add(
      ReadinessFact(
        kind: ReadinessFactKind.sleepDuration,
        source: ReadinessFactorSource.selfReport,
        hours: hours,
      ),
    );
  }

  final tsb = input.tsbPercent;
  if (tsb != null) {
    factors.add(
      ReadinessFactorValue(
        id: ReadinessFactorId.load,
        source: ReadinessFactorSource.trainingLoad,
        weight: readinessWeightLoad,
        score: readinessScaleLoad(tsb),
      ),
    );
  }

  final w = input.wellbeing;
  if (w != null) {
    checkWellbeing(w.level);
    final age = _day(input.today).difference(_day(w.day)).inDays;
    if (age >= 0 && age <= readinessWellbeingMaxAgeDays) {
      factors.add(
        ReadinessFactorValue(
          id: ReadinessFactorId.wellbeing,
          source: ReadinessFactorSource.runRating,
          weight: readinessWeightWellbeing,
          score: readinessScaleWellbeing(w.level),
        ),
      );
    }
  }

  bool has(ReadinessFactorId id) => factors.any((f) => f.id == id);
  final missing = [
    for (final id in ReadinessFactorId.values)
      if (!has(id)) id,
  ];
  final blockers = [
    for (final id in [ReadinessFactorId.hrv, ReadinessFactorId.sleep])
      if (!has(id)) id,
  ];
  final fresh =
      _fresh(input.hrvHealthConnect) ||
      _fresh(input.restingHrHealthConnect) ||
      cams.any(_fresh);

  ReadinessResult build(
    ReadinessState state, {
    int? value,
    bool capped = false,
  }) {
    final lv = readinessLevelOf(
      factors: factors,
      hrv: hrv,
      hrvSourceSpanDays: input.hrvSourceSpanDays,
      hrvCameraLocked: marked.any(
        (m) => m.kind == ReadinessFactKind.hrvDeviation,
      ),
    );
    final hasNumber = state == ReadinessState.number;
    return ReadinessResult(
      state: state,
      value: value,
      band: value == null ? null : readinessBandOf(value),
      capped: capped,
      factors: List.unmodifiable(factors),
      missing: List.unmodifiable(missing),
      blockers: List.unmodifiable(blockers),
      facts: List.unmodifiable(facts),
      markedFacts: List.unmodifiable(marked),
      hasFreshMeasurement: fresh,
      // Eine Zahl hat immer eine Stufe (mindestens vorläufig); ohne Zahl gilt
      // „nicht bestimmbar“ (PAR-147), auch bei der eingeschränkten Einschätzung.
      level: hasNumber ? lv.level : ReadinessLevel.notDeterminable,
      levelReasons: List.unmodifiable(lv.reasons),
      explanation: explainReadinessFactors(
        factors: factors,
        missing: missing,
        sleepHours: sleepHoursForExplanation,
        hasNumber: hasNumber,
        capped: capped,
      ),
    );
  }

  if (blockers.isEmpty) {
    var sum = 0.0, wsum = 0.0;
    for (final f in factors) {
      sum += f.weight * f.score;
      wsum += f.weight;
    }
    var v = (sum / wsum).round();
    var capped = false;
    if (!has(ReadinessFactorId.load) && v > readinessCapWithoutLoad) {
      v = readinessCapWithoutLoad;
      capped = true;
    }
    v = v.clamp(readinessMinValue, readinessMaxValue);
    return build(ReadinessState.number, value: v, capped: capped);
  }
  // PAR-171, PAR-171K: Schlaf oder frische Messung vorhanden.
  if (has(ReadinessFactorId.sleep) || fresh || marked.isNotEmpty) {
    return build(ReadinessState.limited);
  }
  return build(ReadinessState.insufficient);
}

MorningRmssdMark _markOf(CameraRelease release, DeviationResult r) {
  final s = r.cameraSeries;
  if (r.source != ReadinessSource.camera || s == null) {
    return MorningRmssdMark.none;
  }
  return release.forFactor(r.factor, s.posture).mark;
}
