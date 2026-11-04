import 'latest_value_index.dart';
import 'measurement.dart';

/// Kennung und Version der Schrittreihe (ADR-0004 P.3).
const String stepsMethod = 'steps-series';
const int stepsMethodVersion = 1;

class ProcessedSteps {
  const ProcessedSteps({required this.input, required this.state, this.reason});

  final RawSteps input;
  final MeasurementState state;
  final DiscardReason? reason;

  bool get accepted =>
      state == MeasurementState.present || state == MeasurementState.estimated;
}

class StepsResult {
  StepsResult({
    required this.parameterVersion,
    required List<ProcessedSteps> processed,
  }) : processed = List.unmodifiable(processed);

  String get method => stepsMethod;
  int get methodVersion => stepsMethodVersion;
  final int parameterVersion;
  final List<ProcessedSteps> processed;

  List<RawSteps> get acceptedValues => List.unmodifiable([
    for (final p in processed)
      if (p.accepted) p.input,
  ]);
}

/// Schritte als Reihe mit Zuordnung über Zeitstempel (FR-0046). Es gibt keine
/// Schwelle; Zeit ≤ letzte Zeit wird verworfen (`nonMonotonicTime`).
class StepsSeries {
  StepsSeries({required this.parameterVersion});

  final int parameterVersion;
  final List<ProcessedSteps> _processed = [];
  final LatestValueIndex<RawSteps> _index = LatestValueIndex();
  DateTime? _lastTime;

  ProcessedSteps add(RawSteps s) {
    final last = _lastTime;
    final ProcessedSteps r;
    if (last != null && !s.time.isAfter(last)) {
      r = ProcessedSteps(
        input: s,
        state: MeasurementState.discarded,
        reason: DiscardReason.nonMonotonicTime,
      );
    } else {
      _lastTime = s.time;
      final usable =
          s.state != MeasurementState.unavailable &&
          s.state != MeasurementState.discarded;
      r = ProcessedSteps(
        input: s,
        state: usable ? s.state : MeasurementState.unavailable,
      );
      if (usable) _index.add(s.time, s);
    }
    _processed.add(r);
    return r;
  }

  /// Letzter Schrittwert `<= t` mit Alter, ohne Altersgrenze.
  Lookup<RawSteps> stepsAt(DateTime t) => _index.valueAt(t);

  StepsResult result() =>
      StepsResult(parameterVersion: parameterVersion, processed: _processed);
}
