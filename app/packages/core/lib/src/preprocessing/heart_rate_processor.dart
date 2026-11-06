import '../fitness/algorithm_variant.dart';

import 'dart:collection';

import 'latest_value_index.dart';
import 'measurement.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version des Herzfrequenzverfahrens (ADR-0004 P.3).
const String heartRateMethod = 'heart-rate-filter';
const int heartRateMethodVersion = 1;

/// Kategorie des Verfahrens (NFR-0002, docs/architecture/algorithm-categories.md): B.
const AlgorithmCategory heartRateCategory = AlgorithmCategory.heuristic;

/// Bewertung einer Herzfrequenzeingabe.
class ProcessedHeartRate {
  const ProcessedHeartRate({
    required this.input,
    required this.state,
    this.reason,
  });

  final RawHeartRate input;

  /// `present`, `estimated` (vom Sensor geschätzt), `discarded` (mit
  /// [reason]) oder `unavailable` (nicht verwertet: Sensorzustand oder
  /// manuelle Pause).
  final MeasurementState state;
  final DiscardReason? reason;

  bool get accepted =>
      state == MeasurementState.present || state == MeasurementState.estimated;
}

/// Zeitraum ohne akzeptierten Puls, länger als PAR-010 (Einzellücke). Bleibt
/// ein fehlender Wert, nie eine Null (FR-0056).
class HeartRateGap {
  const HeartRateGap({
    required this.start,
    required this.end,
    required this.open,
  });

  /// Zeit des letzten akzeptierten Werts, vor dem ersten Wert der Beginn des
  /// Abschnitts.
  final DateTime start;

  /// Zeit des nächsten akzeptierten Werts bzw. der Stand der Abfrage.
  final DateTime end;

  /// Noch nicht durch einen Wert beendet.
  final bool open;

  MeasurementState get state => MeasurementState.unavailable;
}

/// Median der akzeptierten Werte im Fenster, das an [time] endet (PAR-006).
class HeartRateMedianSample {
  const HeartRateMedianSample({required this.time, required this.bpm});
  final DateTime time;
  final double bpm;
}

class HeartRateResult {
  HeartRateResult({
    required this.parameterVersion,
    required List<ProcessedHeartRate> processed,
    required List<RawHeartRate> acceptedValues,
    required List<HeartRateGap> gaps,
    required this.averageBpm,
    required this.maxBpm,
    required this.medianBpm,
    required List<HeartRateMedianSample> medianSeries,
  }) : processed = List.unmodifiable(processed),
       acceptedValues = List.unmodifiable(acceptedValues),
       gaps = List.unmodifiable(gaps),
       medianSeries = List.unmodifiable(medianSeries);

  String get method => heartRateMethod;
  int get methodVersion => heartRateMethodVersion;
  final int parameterVersion;

  /// Je Eingabe eine Bewertung, in Ankunftsreihenfolge.
  final List<ProcessedHeartRate> processed;
  final List<RawHeartRate> acceptedValues;
  final List<HeartRateGap> gaps;

  /// Arithmetisches Mittel der akzeptierten Werte; `null` ohne Werte, nie 0.
  /// Lücken gehen nicht ein (keine Interpolation, PAR-010).
  final double? averageBpm;

  /// Größter akzeptierter Wert; `null` ohne Werte.
  final int? maxBpm;

  /// PAR-006: Median der akzeptierten Werte in `[at-30 s, at]`.
  final double? medianBpm;

  /// PAR-006: Median je akzeptiertem Wert (nachlaufendes Fenster).
  final List<HeartRateMedianSample> medianSeries;
}

class _Point {
  const _Point(this.time, this.bpm);
  final DateTime time;
  final int bpm;
}

/// Herzfrequenzfilter und Lücken (PAR-006 bis PAR-010).
///
/// Schrittform: Die Gesamtrechnung ist der Fold über [add].
class HeartRateProcessor {
  /// [sectionStart] ist der Beginn des ersten Abschnitts (Bezugspunkt der
  /// Lückenprüfung).
  HeartRateProcessor(this.parameters, {DateTime? sectionStart})
    // ignore: prefer_initializing_formals
    : _sectionStart = sectionStart;

  final PreprocessingParameters parameters;

  final List<ProcessedHeartRate> _processed = [];
  final List<RawHeartRate> _accepted = [];
  final List<HeartRateMedianSample> _medians = [];
  final List<HeartRateGap> _gaps = [];
  final LatestValueIndex<RawHeartRate> _index = LatestValueIndex();

  /// Alle Werte, die PAR-007 und PAR-008 bestanden haben (auch als Ausreißer
  /// verworfene), im Fenster von PAR-009. So übernimmt der Median ein Plateau
  /// nach gut der halben Fensterlänge; je nach Sprunghöhe gibt zuerst die
  /// Änderungsrate oder zuerst der Median frei.
  final Queue<_Point> _window = Queue();
  _Point? _lastAccepted;
  DateTime? _lastTime;
  DateTime? _sectionStart;
  bool _paused = false;
  int _sum = 0;
  int? _max;

  /// Beginn einer manuellen Pause: Der Abschnitt endet. Eine bis hierhin
  /// offene Lücke wird geschlossen.
  void pause(DateTime time) {
    if (_paused) return;
    final from = _gapReference;
    if (from != null &&
        time.difference(from) > parameters.heartRateMaxSingleGap) {
      _gaps.add(HeartRateGap(start: from, end: time, open: false));
    }
    _paused = true;
    _lastAccepted = null;
    _sectionStart = null;
  }

  /// Ende der manuellen Pause. Pausenzeit ist keine Lücke.
  void resume(DateTime time) {
    if (!_paused) return;
    _paused = false;
    _sectionStart = time;
  }

  DateTime? get _gapReference => _lastAccepted?.time ?? _sectionStart;

  ProcessedHeartRate add(RawHeartRate h) {
    final r = _classify(h);
    _processed.add(r);
    return r;
  }

  ProcessedHeartRate _classify(RawHeartRate h) {
    ProcessedHeartRate drop(DiscardReason reason) => ProcessedHeartRate(
      input: h,
      state: MeasurementState.discarded,
      reason: reason,
    );

    final last = _lastTime;
    if (last != null && !h.time.isAfter(last)) {
      return drop(DiscardReason.nonMonotonicTime);
    }

    if (_paused ||
        h.state == MeasurementState.unavailable ||
        h.state == MeasurementState.discarded) {
      return ProcessedHeartRate(input: h, state: MeasurementState.unavailable);
    }
    // PAR-007, dann PAR-008, dann PAR-009.
    if (h.bpm < parameters.heartRateMin || h.bpm > parameters.heartRateMax) {
      return drop(DiscardReason.implausibleHeartRate);
    }
    if (parameters.heartRateDiscardPoorContact &&
        h.contact == SensorContact.poor) {
      return drop(DiscardReason.noContact);
    }
    if (_isOutlier(h)) return drop(DiscardReason.heartRateOutlier);

    final from = _gapReference;
    if (from != null &&
        h.time.difference(from) > parameters.heartRateMaxSingleGap) {
      _gaps.add(HeartRateGap(start: from, end: h.time, open: false));
    }
    _lastTime = h.time;
    _lastAccepted = _Point(h.time, h.bpm);
    _sectionStart = null;
    _accepted.add(h);
    _index.add(h.time, h, h.state);
    _sum += h.bpm;
    _max = _max == null || h.bpm > _max! ? h.bpm : _max;
    _medians.add(
      HeartRateMedianSample(time: h.time, bpm: _acceptedMedian(h.time)!),
    );
    return ProcessedHeartRate(
      input: h,
      state: h.state == MeasurementState.estimated
          ? MeasurementState.estimated
          : MeasurementState.present,
    );
  }

  /// PAR-009: Abweichung vom Median im Fenster (inklusive des Werts selbst)
  /// und Änderungsrate gegen den letzten akzeptierten Wert; beides strikt
  /// über der Grenze. Der Wert geht in jedem Fall ins Fenster ein.
  bool _isOutlier(RawHeartRate h) {
    final from = h.time.subtract(parameters.heartRateOutlierWindow);
    // Die Reihenfolge der Ankunft ist nicht die der Zeit (ein verworfener Wert
    // kann in der Zukunft liegen): alte Werte überall entfernen, spätere
    // Werte zählen für diesen Median nicht.
    _window.removeWhere((p) => p.time.isBefore(from));
    _window.addLast(_Point(h.time, h.bpm));
    final anchor = _lastAccepted;
    if (anchor == null) return false;
    final deviation =
        (h.bpm -
                _median([
                  for (final p in _window)
                    if (!p.time.isAfter(h.time)) p.bpm.toDouble(),
                ]))
            .abs();
    final seconds = h.time.difference(anchor.time).inMicroseconds / 1e6;
    final rate = (h.bpm - anchor.bpm).abs() / seconds;
    return deviation > parameters.heartRateOutlierDeviation &&
        rate > parameters.heartRateOutlierRate;
  }

  /// Median der akzeptierten Werte mit Zeit in `[to-30 s, to]`.
  double? _acceptedMedian(DateTime to) {
    final from = to.subtract(parameters.selectionMedianWindow);
    final values = <double>[];
    for (var i = _accepted.length - 1; i >= 0; i--) {
      final s = _accepted[i];
      if (s.time.isBefore(from)) break;
      if (!s.time.isAfter(to)) values.add(s.bpm.toDouble());
    }
    return values.isEmpty ? null : _median(values);
  }

  static double _median(List<double> values) {
    final v = [...values]..sort();
    final n = v.length;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
  }

  /// Letzter akzeptierter Wert `<= t` (FR-0046); `unavailable`, wenn er älter
  /// als PAR-010 (Einzellücke) ist.
  Lookup<RawHeartRate> heartRateAt(DateTime t) =>
      _index.valueAt(t, maxAge: parameters.heartRateMaxSingleGap);

  /// Stand zum Zeitpunkt [at]. Ändert den Zustand nicht.
  HeartRateResult result({required DateTime at}) {
    final gaps = [..._gaps];
    final from = _gapReference;
    if (!_paused &&
        from != null &&
        at.difference(from) > parameters.heartRateMaxSingleGap) {
      gaps.add(HeartRateGap(start: from, end: at, open: true));
    }
    return HeartRateResult(
      parameterVersion: parameters.parameterVersion,
      processed: _processed,
      acceptedValues: _accepted,
      gaps: gaps,
      averageBpm: _accepted.isEmpty ? null : _sum / _accepted.length,
      maxBpm: _max,
      medianBpm: _acceptedMedian(at),
      medianSeries: _medians,
    );
  }
}
