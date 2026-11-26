import 'dart:collection';

import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/measurement.dart';
import '../preprocessing/movement_time_processor.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../preprocessing/run_preprocessor.dart';
import '../recording/belt_track.dart';
import 'fitness_parameters.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_reserve.dart';
import 'vo2max_section_gradient.dart';

/// Grenzen für „Puls passt nicht zum Tempo“ (PAR-247). Alle Werte sind
/// Startwerte (Heuristik).
class PaceMismatchParameters {
  const PaceMismatchParameters({
    this.lowerBound = 0.4,
    this.earlyTolerance = 0.25,
    this.lateTolerance = 0.15,
    this.noCheckFor = const Duration(minutes: 1),
    this.earlyUntil = const Duration(minutes: 3),
    this.minDuration = const Duration(minutes: 1),
    this.fallbackShare = 0.25,
    this.fallbackSpeedMetersPerSecond = 2.0,
    this.speedWindow = const Duration(seconds: 60),
  });

  /// Untergrenze: ab diesem Anteil der Reserve passt der Puls immer.
  final double lowerBound;

  /// Toleranz von [noCheckFor] bis [earlyUntil] seit Lauf- bzw. Pausenende.
  final double earlyTolerance;

  /// Toleranz ab [earlyUntil].
  final double lateTolerance;

  /// Keine Prüfung in dieser Zeit nach Lauf- bzw. Pausenende.
  final Duration noCheckFor;
  final Duration earlyUntil;

  /// Die Bedingung muss ununterbrochen länger als diese Zeit gelten.
  final Duration minDuration;

  /// Ersatzregel ohne VO₂max-Langzeitwert: `r` unter diesem Anteil …
  final double fallbackShare;

  /// … bei einem 60-s-Tempo ab dieser Geschwindigkeit.
  final double fallbackSpeedMetersPerSecond;

  /// Fenster des gleitenden Tempomittels.
  final Duration speedWindow;
}

/// Erwarteter Anteil der Herzfrequenzreserve (PAR-247): die ACSM-Laufformel
/// (FR-0069) rückwärts über die Reserve (FR-0071),
/// `r_erw = (VO₂ − Ruhe) / (VO₂max − Ruhe)` mit
/// `VO₂ = a · v + b · v · G + Ruhe` (v in m/min, G als Anteil, PAR-027).
double expectedReserveShare({
  required double metersPerMinute,
  required double gradient,
  required double vo2max,
  required Vo2maxParameters p,
}) {
  final demand =
      p.runCoefficient * metersPerMinute +
      p.gradeCoefficient * metersPerMinute * gradient;
  return demand / (vo2max - p.restingOxygen);
}

/// Spannen, in denen der Puls nach PAR-247 nicht zum Tempo passt (Kontakt-
/// fehler des Gurts). Geprüft wird jeder Zeitpunkt des 30-s-Pulsmedians
/// (PAR-006) in Bewegung. [longTermVo2max] ist der Langzeitwert, der vor dem
/// Start des Laufs galt (FR-0079), nie die Schätzung des Laufs selbst; ohne
/// ihn gilt die Ersatzregel. Ohne nutzbare Herzfrequenzreserve (PAR-018,
/// PAR-019) gibt es keine Spanne. Beim Bandlauf ([belt]) kommen Tempo und
/// Steigung aus den Einstellungen wie in der Abschnittsauswahl; ohne Tempo
/// keine Prüfung.
///
/// Reine Funktion der Eingaben.
List<TimeSpan> paceMismatchSpans({
  required RunPreprocessing run,
  required HeartRateBasis basis,
  required double? longTermVo2max,
  required FitnessParameters parameters,
  BeltTrack? belt,
  HeartRateReserve reserve = const HeartRateReserve(),
}) {
  if (reserve.check(basis, parameters) != null) return const [];
  final rest = basis.usableRestingBpm!;
  final hrr = basis.usableMaxBpm! - rest;
  final m = parameters.paceMismatch;
  final phases = _merge(
    belt == null
        ? run.movement.movingIntervals
        : [
            for (final p in belt.pieces)
              if (p.isMoving) p.span,
          ],
  );
  final movingFrom = run.parameters.movementFrom;

  final out = <TimeSpan>[];
  DateTime? first;
  DateTime? last;
  void close() {
    final a = first;
    final b = last;
    if (a != null && b != null && b.difference(a) > m.minDuration) {
      out.add(TimeSpan(start: a, end: b));
    }
    first = null;
    last = null;
  }

  var phase = 0;
  int? openPhase;
  for (final s in run.heartRate.medianSeries) {
    final t = s.time;
    while (phase < phases.length && !phases[phase].end.isAfter(t)) {
      phase++;
    }
    final inPhase = phase < phases.length && !phases[phase].start.isAfter(t);
    if (openPhase != null && (!inPhase || openPhase != phase)) close();
    if (!inPhase) continue;
    final since = t.difference(phases[phase].start);
    var hit = false;
    if (since >= m.noCheckFor) {
      final speed = belt == null
          ? _speed(run, from: phases[phase].start, at: t, window: m.speedWindow)
          : belt.pieceAt(t)?.speedMetersPerSecond;
      if (speed != null && speed >= movingFrom) {
        final r = (s.bpm - rest) / hrr;
        final vo2max = longTermVo2max;
        if (vo2max == null) {
          hit = speed >= m.fallbackSpeedMetersPerSecond && r < m.fallbackShare;
        } else if (r < m.lowerBound) {
          final windowStart = t.subtract(m.speedWindow);
          final from = windowStart.isBefore(phases[phase].start)
              ? phases[phase].start
              : windowStart;
          final gradient = belt == null
              ? gradientOf(
                  run,
                  from,
                  t,
                  speed * t.difference(from).inMicroseconds / 1e6,
                  parameters.sectionSelection,
                ).$1
              : beltGradientOf(belt.pieceAt(t)).$1;
          final expected = expectedReserveShare(
            metersPerMinute: speed * Duration.secondsPerMinute,
            gradient: gradient,
            vo2max: vo2max,
            p: parameters.vo2max,
          );
          final tolerance = since < m.earlyUntil
              ? m.earlyTolerance
              : m.lateTolerance;
          hit = r < expected - tolerance;
        }
      }
    }
    if (hit) {
      first ??= t;
      last = t;
      openPhase = phase;
    } else {
      close();
      openPhase = null;
    }
  }
  close();
  return out;
}

/// Gleitendes Tempomittel (Σ Strecke / Σ Zeit) der Segmente mit Ende in
/// `(at − window, at]`, nicht vor [from]; `null` ohne Segment.
double? _speed(
  RunPreprocessing run, {
  required DateTime from,
  required DateTime at,
  required Duration window,
}) {
  final start = at.subtract(window);
  var meters = 0.0;
  var seconds = 0.0;
  for (final s in run.pace.segments) {
    if (s.isGap || s.end.isAfter(at)) continue;
    if (!s.end.isAfter(start) || s.start.isBefore(from)) continue;
    meters += s.meters;
    seconds += s.seconds;
  }
  return seconds > 0 ? meters / seconds : null;
}

/// Sortierte, disjunkte Spannen; aneinandergrenzende werden verbunden.
List<TimeSpan> _merge(List<TimeSpan> spans) {
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final out = <TimeSpan>[];
  for (final s in sorted) {
    if (out.isNotEmpty && !s.start.isAfter(out.last.end)) {
      if (s.end.isAfter(out.last.end)) {
        out[out.length - 1] = TimeSpan(start: out.last.start, end: s.end);
      }
    } else {
      out.add(s);
    }
  }
  return out;
}

bool _inside(List<TimeSpan> spans, DateTime t) =>
    spans.any((s) => !t.isBefore(s.start) && !t.isAfter(s.end));

/// Puls für die Fitnesswerte (PAR-247, PAR-248): Werte in [spans] zählen als
/// fehlend (wie eine Pulslücke nach PAR-010), und PAR-009 wird mit einem
/// Median-Fenster ohne diese Werte erneut geprüft; ein Wert, den die
/// Vorverarbeitung als Ausreißer verworfen hat, gilt dann als gültig, wenn er
/// die Prüfung besteht. Lücken (PAR-010) und Medianreihe (PAR-006) entstehen
/// aus diesen Werten neu, nach denselben Regeln wie in [HeartRateProcessor].
/// Ohne Spanne ist das Ergebnis [heartRate] selbst.
///
/// [pauses]: manuelle Pausen und Unterbrechungen (Ende `null`: bis [until]),
/// wie sie die Vorverarbeitung bekam. [runStart] ist der Beginn des ersten
/// Abschnitts.
HeartRateResult fitnessHeartRateOf({
  required HeartRateResult heartRate,
  required List<TimeSpan> spans,
  required List<TimeSpan> pauses,
  required DateTime runStart,
  required DateTime until,
  required PreprocessingParameters parameters,
}) {
  if (spans.isEmpty) return heartRate;
  final p = parameters;
  final events = <(DateTime, bool)>[
    for (final s in pauses) ...[(s.start, true), (s.end, false)],
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  var e = 0;

  final processed = <ProcessedHeartRate>[];
  final accepted = <RawHeartRate>[];
  final medians = <HeartRateMedianSample>[];
  final gaps = <HeartRateGap>[];
  final window = Queue<RawHeartRate>();
  RawHeartRate? anchor;
  DateTime? sectionStart = runStart;
  var paused = false;
  DateTime? ref() => anchor?.time ?? sectionStart;

  void apply(DateTime at, bool pause) {
    if (pause) {
      if (paused) return;
      final from = ref();
      if (from != null && at.difference(from) > p.heartRateMaxSingleGap) {
        gaps.add(HeartRateGap(start: from, end: at, open: false));
      }
      paused = true;
      anchor = null;
      sectionStart = null;
    } else {
      if (!paused) return;
      paused = false;
      sectionStart = at;
    }
  }

  for (final h in heartRate.processed) {
    final t = h.input.time;
    // Dieselbe Reihenfolge wie die Wiedergabe: Fortsetzen vor einem Wert
    // gleicher Zeit, Pause danach.
    while (e < events.length &&
        (events[e].$1.isBefore(t) || (events[e].$1 == t && !events[e].$2))) {
      apply(events[e].$1, events[e].$2);
      e++;
    }
    final candidate = h.accepted || h.reason == DiscardReason.heartRateOutlier;
    if (!candidate) {
      processed.add(h);
      continue;
    }
    if (_inside(spans, t)) {
      processed.add(
        ProcessedHeartRate(input: h.input, state: MeasurementState.unavailable),
      );
      continue;
    }
    window.removeWhere(
      (v) => v.time.isBefore(t.subtract(p.heartRateOutlierWindow)),
    );
    window.addLast(h.input);
    final a = anchor;
    if (a != null) {
      final deviation =
          (h.input.bpm -
                  _median([
                    for (final v in window)
                      if (!v.time.isAfter(t)) v.bpm.toDouble(),
                  ]))
              .abs();
      final seconds = t.difference(a.time).inMicroseconds / 1e6;
      final rate = (h.input.bpm - a.bpm).abs() / seconds;
      if (deviation > p.heartRateOutlierDeviation &&
          rate > p.heartRateOutlierRate) {
        processed.add(
          ProcessedHeartRate(
            input: h.input,
            state: MeasurementState.discarded,
            reason: DiscardReason.heartRateOutlier,
          ),
        );
        continue;
      }
    }
    final from = ref();
    if (from != null && t.difference(from) > p.heartRateMaxSingleGap) {
      gaps.add(HeartRateGap(start: from, end: t, open: false));
    }
    anchor = h.input;
    sectionStart = null;
    accepted.add(h.input);
    medians.add(
      HeartRateMedianSample(
        time: t,
        bpm: _acceptedMedian(accepted, t, p.selectionMedianWindow)!,
      ),
    );
    processed.add(
      h.accepted
          ? h
          : ProcessedHeartRate(
              input: h.input,
              state: h.input.state == MeasurementState.estimated
                  ? MeasurementState.estimated
                  : MeasurementState.present,
            ),
    );
  }
  while (e < events.length && !events[e].$1.isAfter(until)) {
    apply(events[e].$1, events[e].$2);
    e++;
  }
  final from = ref();
  if (!paused &&
      from != null &&
      until.difference(from) > p.heartRateMaxSingleGap) {
    gaps.add(HeartRateGap(start: from, end: until, open: true));
  }
  var sum = 0;
  int? max;
  for (final v in accepted) {
    sum += v.bpm;
    if (max == null || v.bpm > max) max = v.bpm;
  }
  return HeartRateResult(
    parameterVersion: heartRate.parameterVersion,
    processed: processed,
    acceptedValues: accepted,
    gaps: gaps,
    averageBpm: accepted.isEmpty ? null : sum / accepted.length,
    maxBpm: max,
    medianBpm: _acceptedMedian(accepted, until, p.selectionMedianWindow),
    medianSeries: medians,
  );
}

double? _acceptedMedian(List<RawHeartRate> xs, DateTime to, Duration w) {
  final from = to.subtract(w);
  final values = <double>[];
  for (var i = xs.length - 1; i >= 0; i--) {
    final s = xs[i];
    if (s.time.isBefore(from)) break;
    if (!s.time.isAfter(to)) values.add(s.bpm.toDouble());
  }
  return values.isEmpty ? null : _median(values);
}

double _median(List<double> values) {
  final v = [...values]..sort();
  final n = v.length;
  return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
}
