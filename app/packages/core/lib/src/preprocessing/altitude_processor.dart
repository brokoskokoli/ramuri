import 'dart:collection';

import 'latest_value_index.dart';
import 'measurement.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version des Höhenverfahrens (ADR-0004 P.3).
const String altitudeMethod = 'altitude-filter';
const int altitudeMethodVersion = 1;

/// Bewertung einer Höheneingabe.
class ProcessedAltitude {
  const ProcessedAltitude({
    required this.input,
    required this.state,
    this.reason,
  });

  final RawAltitude input;

  /// `present`, `estimated` (vom Sensor), `discarded` (mit [reason]) oder
  /// `unavailable` (Sensorzustand).
  final MeasurementState state;
  final DiscardReason? reason;

  bool get accepted =>
      state == MeasurementState.present || state == MeasurementState.estimated;
}

/// Median der akzeptierten Höhen im Fenster, das an [time] endet (PAR-013).
class AltitudeSample {
  const AltitudeSample({required this.time, required this.meters});
  final DateTime time;
  final double meters;
}

class AltitudeResult {
  AltitudeResult({
    required this.parameterVersion,
    required List<ProcessedAltitude> processed,
    required List<RawAltitude> acceptedValues,
    required List<AltitudeSample> smoothed,
    required this.ascentMeters,
    required this.withoutVerticalAccuracy,
    required this.medianMeters,
  }) : processed = List.unmodifiable(processed),
       acceptedValues = List.unmodifiable(acceptedValues),
       smoothed = List.unmodifiable(smoothed);

  String get method => altitudeMethod;
  int get methodVersion => altitudeMethodVersion;
  final int parameterVersion;

  /// Je Eingabe eine Bewertung, in Ankunftsreihenfolge.
  final List<ProcessedAltitude> processed;
  final List<RawAltitude> acceptedValues;

  /// PAR-013: Median je akzeptiertem Wert (nachlaufendes Fenster).
  final List<AltitudeSample> smoothed;

  /// PAR-012: Aufstieg in Metern; `null` ohne Höhenwerte, nie 0 dafür.
  final double? ascentMeters;

  /// Akzeptierte Werte ohne gemeldete Vertikalgenauigkeit. Sie bleiben
  /// erhalten, die Auswertung kann den Aufstieg dann als vorläufig führen.
  final int withoutVerticalAccuracy;

  /// Median der akzeptierten Höhen in `[at-30 s, at]`; `null` ohne Werte.
  final double? medianMeters;
}

/// Höhenfilter und Aufstieg (PAR-012, PAR-013). Eigene Reihe, unabhängig von
/// den Positionsfiltern. Schrittform: Die Gesamtrechnung ist der Fold über
/// [add].
class AltitudeProcessor {
  AltitudeProcessor(this.parameters);

  final PreprocessingParameters parameters;

  final List<ProcessedAltitude> _processed = [];
  final List<RawAltitude> _accepted = [];
  final List<AltitudeSample> _smoothed = [];
  final Queue<RawAltitude> _window = Queue();
  final LatestValueIndex<RawAltitude> _index = LatestValueIndex();
  DateTime? _lastTime;
  double? _reference;
  double? _ascent;
  int _withoutAccuracy = 0;
  bool _paused = false;

  /// Manuelle Pause: Werte sind `unavailable`, kein Aufstieg über die Pause.
  /// Fenster und Referenz beginnen beim Fortsetzen neu, der bisherige
  /// Aufstieg bleibt.
  void pause() {
    _paused = true;
  }

  void resume() {
    _paused = false;
    _window.clear();
    _reference = null;
  }

  ProcessedAltitude add(RawAltitude a) {
    final last = _lastTime;
    final ProcessedAltitude r;
    if (last != null && !a.time.isAfter(last)) {
      r = _verdict(
        a,
        MeasurementState.discarded,
        DiscardReason.nonMonotonicTime,
      );
    } else {
      final accuracy = a.verticalAccuracyMeters;
      if (_paused ||
          a.state == MeasurementState.unavailable ||
          a.state == MeasurementState.discarded) {
        r = _verdict(a, MeasurementState.unavailable);
      } else if (!a.meters.isFinite) {
        r = _verdict(a, MeasurementState.discarded, DiscardReason.invalidValue);
      } else if (accuracy != null &&
          (accuracy < 0 ||
              !(accuracy <= parameters.altitudeMaxVerticalAccuracyMeters))) {
        r = _verdict(
          a,
          MeasurementState.discarded,
          DiscardReason.verticalAccuracy,
        );
      } else {
        _lastTime = a.time;
        r = _verdict(a, a.state);
        _accept(a);
      }
    }
    _processed.add(r);
    return r;
  }

  ProcessedAltitude _verdict(
    RawAltitude a,
    MeasurementState state, [
    DiscardReason? reason,
  ]) => ProcessedAltitude(input: a, state: state, reason: reason);

  void _accept(RawAltitude a) {
    _accepted.add(a);
    _index.add(a.time, a, a.state);
    if (a.verticalAccuracyMeters == null) _withoutAccuracy++;
    _window.addLast(a);
    final from = a.time.subtract(parameters.altitudeMedianWindow);
    while (_window.first.time.isBefore(from)) {
      _window.removeFirst();
    }
    final m = _median([for (final w in _window) w.meters]);
    _smoothed.add(AltitudeSample(time: a.time, meters: m));
    _ascend(m);
  }

  /// PAR-012: Referenz und Hysterese. Genau die Schwelle zählt.
  void _ascend(double m) {
    final ref = _reference;
    if (ref == null) {
      _reference = m;
      _ascent ??= 0;
    } else if (m - ref >= parameters.ascentThresholdMeters) {
      _ascent = _ascent! + (m - ref);
      _reference = m;
    } else if (ref - m >= parameters.ascentThresholdMeters) {
      _reference = m;
    }
  }

  static double _median(List<double> values) {
    final v = [...values]..sort();
    final n = v.length;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
  }

  /// Letzte akzeptierte Höhe `<= t` mit Alter (FR-0046). Es gibt keine
  /// Altersgrenze.
  Lookup<RawAltitude> altitudeAt(DateTime t) => _index.valueAt(t);

  AltitudeResult result({required DateTime at}) {
    final from = at.subtract(parameters.altitudeMedianWindow);
    final inWindow = [
      for (final a in _accepted)
        if (!a.time.isBefore(from) && !a.time.isAfter(at)) a.meters,
    ];
    return AltitudeResult(
      parameterVersion: parameters.parameterVersion,
      processed: _processed,
      acceptedValues: _accepted,
      smoothed: _smoothed,
      ascentMeters: _ascent,
      withoutVerticalAccuracy: _withoutAccuracy,
      medianMeters: inWindow.isEmpty ? null : _median(inWindow),
    );
  }
}
