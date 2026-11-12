import 'dart:math' as math;

import '../preprocessing/measurement.dart';
import '../preprocessing/movement_time_processor.dart';
import '../preprocessing/run_preprocessor.dart';
import '../recording/belt_track.dart';
import 'fitness_parameters.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_reserve.dart';
import 'variation_coefficient.dart';
import 'vo2max_section_types.dart';

export 'vo2max_section_types.dart';

/// Abschnittsauswahl für die VO₂max (FR-0073, FR-0074, FR-0070; PAR-020 bis
/// PAR-031 sowie PAR-006, PAR-010, PAR-011). Kategorie B (Heuristik, Qualitätsbewertung
/// nach NFR-0002): reine Regelprüfung auf den Ergebnissen der Vorverarbeitung.
///
/// Ablauf:
/// 1. Bewegungszeit ([MovementResult.movingIntervals]) ohne Einschwingzeit
///    (PAR-011) ergibt gleichmäßige Phasen; Pausen und Einschwingzeit werden
///    als [ExcludedSpan] gemeldet.
/// 2. Jede Phase der Länge `L` wird in `⌈L / 10 min⌉` gleich lange Abschnitte
///    geteilt (PAR-021); eine Phase unter [SectionSelectionParameters
///    .minDuration] bleibt ein einzelner, abgelehnter Abschnitt (PAR-020).
/// 3. Jeder Abschnitt wird gegen alle Regeln geprüft; es werden alle
///    Verletzungen gesammelt, nichts wird still verworfen.
///
/// Reine Funktion der Eingaben; keine Uhr, kein Netzwerk.
class Vo2maxSectionSelector {
  const Vo2maxSectionSelector({
    this.parameters = const FitnessParameters.v4(),
    this.reserve = const HeartRateReserve(),
  });

  final FitnessParameters parameters;

  /// Prüft die Basiswerte für `r` (PAR-018, PAR-019).
  final HeartRateReserve reserve;

  SectionSelectionParameters get _p => parameters.sectionSelection;

  /// [runStart] und [until] begrenzen den Lauf; [until] ist der Stand, mit dem
  /// die Vorverarbeitung abgefragt wurde. Die Minuten für PAR-024 zählen ab
  /// [runStart] (Wanduhrzeit, Pausen eingeschlossen).
  ///
  /// Bei einem Bandlauf ([belt], FR-0196) kommen die Phasen aus den Stücken
  /// gleichbleibender Einstellung (jede Änderung trennt, ihr Beginn ist
  /// Einschwingzeit), Tempo, Strecke und Steigung aus den eingestellten Werten
  /// statt aus Positionen; GPS-Regeln entfallen.
  ///
  /// Wirft [ArgumentError], wenn die Parameterversion von der der
  /// Vorverarbeitung abweicht.
  SectionSelection select({
    required RunPreprocessing run,
    required HeartRateBasis basis,
    required DateTime runStart,
    required DateTime until,
    BeltTrack? belt,
  }) {
    if (run.parameterVersion != parameters.parameterVersion) {
      throw ArgumentError(
        'Parameterversionen weichen ab: Vorverarbeitung '
        '${run.parameterVersion}, Fitness ${parameters.parameterVersion}',
      );
    }
    if (!until.isAfter(runStart)) {
      throw ArgumentError.value(until, 'until', 'muss nach runStart liegen');
    }
    final settling = _clip(
      belt == null
          ? run.settling.intervals
          : _beltSettling(belt, run.parameters.settlingDuration),
      runStart,
      until,
    );
    final moving = _clip(
      belt == null
          ? run.movement.movingIntervals
          : [for (final p in belt.constantPhases) p.span],
      runStart,
      until,
    );
    final excluded = <ExcludedSpan>[
      for (final s in settling)
        ExcludedSpan(span: s, kind: ExclusionKind.settling),
      for (final s in _complement(moving, runStart, until))
        ExcludedSpan(span: s, kind: ExclusionKind.pause),
    ]..sort((a, b) => a.span.start.compareTo(b.span.start));

    final sections = <EvaluatedSection>[];
    for (final phase in _subtract(moving, settling)) {
      for (final part in _split(phase)) {
        sections.add(_evaluate(part, run, basis, runStart, belt));
      }
    }
    return SectionSelection(
      parameterVersion: parameters.parameterVersion,
      basis: basis,
      sections: sections,
      excluded: excluded,
    );
  }

  // --- Phasen und Aufteilung -------------------------------------------

  /// PAR-021: `k = ⌈L / splitLength⌉` gleich lange Teile; unter der
  /// Mindestdauer (PAR-020) bleibt die Phase ungeteilt.
  List<TimeSpan> _split(TimeSpan phase) {
    final length = phase.duration.inMicroseconds;
    if (length <= 0) return const [];
    if (phase.duration < _p.minDuration) return [phase];
    final max = _p.splitLength.inMicroseconds;
    final k = (length + max - 1) ~/ max;
    return [
      for (var i = 0; i < k; i++)
        TimeSpan(
          start: phase.start.add(Duration(microseconds: length * i ~/ k)),
          end: phase.start.add(Duration(microseconds: length * (i + 1) ~/ k)),
        ),
    ];
  }

  static List<TimeSpan> _clip(
    List<TimeSpan> spans,
    DateTime from,
    DateTime to,
  ) => [
    for (final s in spans)
      if (s.end.isAfter(from) && s.start.isBefore(to))
        TimeSpan(
          start: s.start.isBefore(from) ? from : s.start,
          end: s.end.isAfter(to) ? to : s.end,
        ),
  ];

  /// Lücken zwischen den (sortierten, disjunkten) Spannen in `[from, to]`.
  static List<TimeSpan> _complement(
    List<TimeSpan> spans,
    DateTime from,
    DateTime to,
  ) {
    final out = <TimeSpan>[];
    var cursor = from;
    for (final s in spans) {
      if (s.start.isAfter(cursor)) {
        out.add(TimeSpan(start: cursor, end: s.start));
      }
      if (s.end.isAfter(cursor)) cursor = s.end;
    }
    if (to.isAfter(cursor)) out.add(TimeSpan(start: cursor, end: to));
    return out;
  }

  /// [base] ohne die (sortierten) Spannen [cut]; leere Reste entfallen.
  static List<TimeSpan> _subtract(List<TimeSpan> base, List<TimeSpan> cut) {
    final out = <TimeSpan>[];
    for (final b in base) {
      var cursor = b.start;
      for (final c in cut) {
        if (!c.end.isAfter(cursor) || !c.start.isBefore(b.end)) continue;
        if (c.start.isAfter(cursor)) {
          out.add(TimeSpan(start: cursor, end: c.start));
        }
        if (c.end.isAfter(cursor)) cursor = c.end;
      }
      if (b.end.isAfter(cursor)) out.add(TimeSpan(start: cursor, end: b.end));
    }
    return out;
  }

  // --- Bewertung eines Abschnitts --------------------------------------

  EvaluatedSection _evaluate(
    TimeSpan span,
    RunPreprocessing run,
    HeartRateBasis basis,
    DateTime runStart,
    BeltTrack? belt,
  ) {
    final from = span.start;
    final to = span.end;
    final mid = from.add(
      Duration(microseconds: span.duration.inMicroseconds ~/ 2),
    );
    final violations = <SectionViolation>[];
    final caveats = <SectionCaveat>[];
    void add(SectionRule r, {double? value, double? limit}) =>
        violations.add(SectionViolation(r, value: value, limit: limit));

    // PAR-020
    if (span.duration < _p.minDuration) {
      add(
        SectionRule.tooShort,
        value: _minutes(span.duration),
        limit: _minutes(_p.minDuration),
      );
    }

    // PAR-024
    final elapsed = from.difference(runStart);
    if (elapsed >= _p.lateExcludeFrom) {
      add(
        SectionRule.lateRun,
        value: _minutes(elapsed),
        limit: _minutes(_p.lateExcludeFrom),
      );
    }
    final weight = violations.any((v) => v.rule == SectionRule.lateRun)
        ? 0.0
        : elapsed >= _p.lateHalfWeightFrom
        ? _p.lateWeight
        : _p.fullWeight;

    // PAR-010 (Pulslücken) und PAR-025 (GPS-Lücke) über die Abschnittsqualität.
    final quality = run.assessSection(from, to);
    if (!quality.meetsHeartRateGapRule) {
      final pp = run.parameters;
      // Beide Bedingungen von PAR-010 einzeln melden, wenn beide verletzt sind.
      if (quality.missingHeartRateShare > pp.heartRateMaxMissingShare) {
        add(
          SectionRule.heartRateGaps,
          value: quality.missingHeartRateShare,
          limit: pp.heartRateMaxMissingShare,
        );
      }
      if (quality.longestHeartRateGap > pp.heartRateMaxSingleGap) {
        add(
          SectionRule.heartRateGaps,
          value: _seconds(quality.longestHeartRateGap),
          limit: _seconds(pp.heartRateMaxSingleGap),
        );
      }
    }
    if (belt == null && quality.gpsGaps.isNotEmpty) {
      add(
        SectionRule.gpsGap,
        value: quality.gpsGaps.fold<double>(
          0,
          (a, g) => a + _seconds(g.end.difference(g.start)),
        ),
      );
    }

    // Tempo: PAR-006 (Strecke durch Zeit), PAR-030, PAR-031, PAR-022.
    final piece = belt?.pieceAt(mid);
    final distance = belt == null
        ? _distance(run, from, to)
        : piece == null
        ? null
        : piece.speedMetersPerSecond *
              span.duration.inMicroseconds /
              Duration.microsecondsPerSecond;
    final speed = belt == null
        ? _speedPerMinute(run, from, to)
        : piece?.speedMetersPerSecond == null
        ? null
        : piece!.speedMetersPerSecond * 60;
    var speedUnavailable = speed == null;
    if (speed != null) {
      if (speed < _p.limitedSpeedMetersPerMinute) {
        add(
          SectionRule.tooSlow,
          value: speed,
          limit: _p.limitedSpeedMetersPerMinute,
        );
      } else if (speed < _p.fullSpeedMetersPerMinute) {
        caveats.add(SectionCaveat.limitedSpeed);
      }
    }
    // Bandlauf: Die eingestellte Geschwindigkeit ist im Abschnitt konstant,
    // Streuung und Hälftenvergleich entfallen.
    final samples = belt != null
        ? const <double>[1]
        : [
            for (final s in run.pace.medianSeries)
              if (!s.time.isBefore(from) && !s.time.isAfter(to))
                s.metersPerSecond,
          ];
    if (samples.isEmpty) {
      speedUnavailable = true;
    } else {
      final cv = variationCoefficient(samples);
      if (cv > _p.paceMaxVariation) {
        add(SectionRule.paceVariation, value: cv, limit: _p.paceMaxVariation);
      }
    }
    final first = belt != null ? speed : _speedPerMinute(run, from, mid);
    final second = belt != null ? speed : _speedPerMinute(run, mid, to);
    if (first == null || second == null) {
      speedUnavailable = true;
    } else {
      final diff = (first - second).abs() / ((first + second) / 2);
      if (diff > _p.paceMaxHalfDifference) {
        add(
          SectionRule.paceHalves,
          value: diff,
          limit: _p.paceMaxHalfDifference,
        );
      }
    }
    if (speedUnavailable) add(SectionRule.speedUnavailable);

    // Puls: PAR-023, PAR-028, PAR-029 (FR-0068: fehlt etwas, steht der Grund da).
    final beats = run.heartRate.medianSeries;
    List<double> bpmIn(DateTime a, DateTime b, {required bool endInclusive}) =>
        [
          for (final h in beats)
            if (!h.time.isBefore(a) &&
                (endInclusive ? !h.time.isAfter(b) : h.time.isBefore(b)))
              h.bpm,
        ];
    final firstBeats = bpmIn(from, mid, endInclusive: false);
    final secondBeats = bpmIn(mid, to, endInclusive: true);
    final mean = _mean([...firstBeats, ...secondBeats]);
    if (firstBeats.isEmpty || secondBeats.isEmpty) {
      add(SectionRule.heartRateUnavailable);
    } else {
      final diff = (_mean(firstBeats)! - _mean(secondBeats)!).abs();
      if (diff > _p.heartRateMaxHalfDifferenceBpm) {
        add(
          SectionRule.heartRateHalves,
          value: diff,
          limit: _p.heartRateMaxHalfDifferenceBpm,
        );
      }
    }
    double? load;
    final basisReason = reserve.check(basis, parameters);
    if (basisReason != null) {
      violations.add(
        SectionViolation(
          SectionRule.heartRateBasisUnavailable,
          basisReason: basisReason,
        ),
      );
    } else if (mean != null) {
      // Dieselbe Rechnung wie HeartRateReserve.relativeLoad, aber mit dem
      // ungerundeten Mittel (relativeLoad nimmt ganze bpm).
      final rest = basis.usableRestingBpm!;
      load = (mean - rest) / (basis.usableMaxBpm! - rest);
      if (load < _p.intensityMin) {
        add(SectionRule.intensityLow, value: load, limit: _p.intensityMin);
      } else if (load > _p.intensityMax) {
        add(SectionRule.intensityHigh, value: load, limit: _p.intensityMax);
      }
    }

    // PAR-025: GPS-Genauigkeit.
    final gpsMedian = belt != null ? null : _gpsAccuracy(run, from, to, add);

    // PAR-026, PAR-027: Steigung.
    final (gradient, gradientBasis) = belt != null
        ? _beltGradient(piece)
        : _gradient(run, from, to, distance);
    switch (gradientBasis) {
      case GradientBasis.noAltitude:
        caveats.add(SectionCaveat.noAltitude);
      case GradientBasis.noVerticalAccuracy:
        caveats.add(SectionCaveat.noVerticalAccuracy);
      case GradientBasis.measured:
      case GradientBasis.belowThreshold:
        break;
    }
    if (gradient < _p.gradientMin) {
      add(SectionRule.gradient, value: gradient, limit: _p.gradientMin);
    } else if (gradient > _p.gradientMax) {
      add(SectionRule.gradient, value: gradient, limit: _p.gradientMax);
    }

    final status = violations.isNotEmpty
        ? SectionStatus.rejected
        : caveats.isNotEmpty
        ? SectionStatus.provisional
        : SectionStatus.eligible;
    return EvaluatedSection(
      from: from,
      to: to,
      status: status,
      violations: violations,
      caveats: caveats,
      weight: status == SectionStatus.rejected ? 0.0 : weight,
      speedMetersPerMinute: speed,
      meanHeartRate: mean,
      relativeLoad: load,
      gradient: gradient,
      gradientBasis: gradientBasis,
      distanceMeters: distance,
      gpsMedianAccuracyMeters: gpsMedian,
    );
  }

  /// PAR-025: Median ≤ Grenze und Anteil der Punkte ≤ Grenze. Punkte ohne
  /// gemeldete Genauigkeit zählen nicht zum Median und gelten beim Anteil als
  /// nicht eingehalten.
  double? _gpsAccuracy(
    RunPreprocessing run,
    DateTime from,
    DateTime to,
    void Function(SectionRule, {double? value, double? limit}) add,
  ) {
    final points = [
      for (final p in run.position.positions)
        if (p.reason != DiscardReason.nonMonotonicTime &&
            !p.input.time.isBefore(from) &&
            !p.input.time.isAfter(to))
          p.input.accuracyMeters,
    ];
    final known = [for (final a in points) ?a];
    if (known.isEmpty) {
      add(SectionRule.gpsMedianAccuracy, limit: _p.gpsMaxMedianAccuracyMeters);
      return null;
    }
    final median = _median(known);
    if (median > _p.gpsMaxMedianAccuracyMeters) {
      add(
        SectionRule.gpsMedianAccuracy,
        value: median,
        limit: _p.gpsMaxMedianAccuracyMeters,
      );
    }
    final good = known.where((a) => a <= _p.gpsShareAccuracyMeters).length;
    final share = good / points.length;
    if (share < _p.gpsMinShare) {
      add(SectionRule.gpsAccuracyShare, value: share, limit: _p.gpsMinShare);
    }
    return median;
  }

  /// Steigung des Bands: eingestellt in %, als Anteil (nicht gemessen).
  /// Ohne Angabe 0 mit dem Hinweis „keine Höhendaten“ (nie 0 statt unbekannt).
  static (double, GradientBasis) _beltGradient(BeltPiece? piece) {
    final g = piece?.inclinePercent;
    return g == null
        ? (0, GradientBasis.noAltitude)
        : (g / 100, GradientBasis.measured);
  }

  /// Einschwingzeit am Beginn jedes bewegten Stücks (Start, Fortsetzen nach
  /// Pause, jede Änderung von Geschwindigkeit oder Steigung).
  List<TimeSpan> _beltSettling(BeltTrack belt, Duration settle) => [
    for (final p in belt.constantPhases)
      TimeSpan(
        start: p.span.start,
        end: p.span.start.add(settle).isAfter(p.span.end)
            ? p.span.end
            : p.span.start.add(settle),
      ),
  ];

  /// PAR-027: `G` nur einrechnen, wenn |G| ≥ 1 % und |Δh| ≥ 2 · Vertikal-
  /// genauigkeit (größte gemeldete im Abschnitt); sonst 0. Δh ist die Differenz
  /// zwischen erstem und letztem 30-s-Höhenmedian im Abschnitt (PAR-013).
  (double, GradientBasis) _gradient(
    RunPreprocessing run,
    DateTime from,
    DateTime to,
    double? distance,
  ) {
    final heights = [
      for (final a in run.altitude.smoothed)
        if (!a.time.isBefore(from) && !a.time.isAfter(to)) a.meters,
    ];
    if (heights.length < 2 || distance == null || !(distance > 0)) {
      return (0, GradientBasis.noAltitude);
    }
    final accuracies = [
      for (final a in run.altitude.processed)
        if (a.accepted &&
            !a.input.time.isBefore(from) &&
            !a.input.time.isAfter(to) &&
            a.input.verticalAccuracyMeters != null)
          a.input.verticalAccuracyMeters!,
    ];
    if (accuracies.isEmpty) return (0, GradientBasis.noVerticalAccuracy);
    final rise = heights.last - heights.first;
    final g = rise / distance;
    final noise = accuracies.reduce(math.max) * _p.gradientAltitudeFactor;
    if (g.abs() >= _p.gradientUseFrom && rise.abs() >= noise) {
      return (g, GradientBasis.measured);
    }
    return (0, GradientBasis.belowThreshold);
  }

  // --- Kennzahlen -------------------------------------------------------

  /// Strecke zwischen erstem und letztem akzeptiertem Punkt in `[from, to]`.
  double? _distance(RunPreprocessing run, DateTime from, DateTime to) =>
      _distanceAndTime(run, from, to)?.$1;

  double? _speedPerMinute(RunPreprocessing run, DateTime from, DateTime to) {
    final dt = _distanceAndTime(run, from, to);
    if (dt == null) return null;
    return dt.$1 / (dt.$2.inMicroseconds / Duration.microsecondsPerMinute);
  }

  /// Summe der gezählten Strecken aller akzeptierten Punkte nach dem ersten,
  /// und die Zeit zwischen erstem und letztem akzeptiertem Punkt. `null`
  /// unter zwei Punkten.
  (double, Duration)? _distanceAndTime(
    RunPreprocessing run,
    DateTime from,
    DateTime to,
  ) {
    DateTime? start;
    DateTime? end;
    var meters = 0.0;
    for (final p in run.position.positions) {
      if (!p.accepted ||
          p.input.time.isBefore(from) ||
          p.input.time.isAfter(to)) {
        continue;
      }
      if (start == null) {
        start = p.input.time;
      } else {
        meters += p.countedDistanceMeters;
      }
      end = p.input.time;
    }
    if (start == null || end == null || !end.isAfter(start)) return null;
    return (meters, end.difference(start));
  }

  static double _minutes(Duration d) =>
      d.inMicroseconds / Duration.microsecondsPerMinute;
  static double _seconds(Duration d) =>
      d.inMicroseconds / Duration.microsecondsPerSecond;

  static double? _mean(List<double> xs) =>
      xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

  static double _median(List<double> xs) {
    final v = [...xs]..sort();
    final n = v.length;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
  }
}
