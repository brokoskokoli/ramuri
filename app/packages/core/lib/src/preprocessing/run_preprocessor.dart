import 'altitude_processor.dart';
import 'heart_rate_processor.dart';
import 'latest_value_index.dart';
import 'measurement.dart';
import 'motion_segments.dart';
import 'movement_time_processor.dart';
import 'pace_processor.dart';
import 'position_processor.dart';
import 'preprocessing_parameters.dart';
import 'section_quality.dart';
import 'settling_processor.dart';
import 'steps_series.dart';

/// Gesamtergebnis der Vorverarbeitung; wächst mit den Kanälen.
class RunPreprocessing {
  const RunPreprocessing({
    required this.parameters,
    required this.position,
    required this.pace,
    required this.movement,
    required this.heartRate,
    required this.settling,
    required this.altitude,
    required this.steps,
  });

  /// Parametersatz, mit dem gerechnet wurde.
  final PreprocessingParameters parameters;
  int get parameterVersion => parameters.parameterVersion;
  final PositionResult position;
  final PaceResult pace;
  final MovementResult movement;
  final HeartRateResult heartRate;
  final SettlingResult settling;
  final AltitudeResult altitude;
  final StepsResult steps;
}

/// Fasst die Kanalprozessoren zusammen. Keine Uhr: Zeiten kommen von außen.
class RunPreprocessor {
  RunPreprocessor({
    required this.start,
    this.parameters = const PreprocessingParameters.v2(),
  }) : _position = PositionProcessor(parameters, sectionStart: start),
       _pace = PaceProcessor(parameters),
       _movement = MovementTimeProcessor(parameters, start: start),
       _heartRate = HeartRateProcessor(parameters, sectionStart: start),
       _settling = SettlingProcessor(parameters, start: start),
       _altitude = AltitudeProcessor(parameters),
       _steps = StepsSeries(parameterVersion: parameters.parameterVersion),
       _segments = SegmentBuilder(parameters.gapMaxDuration);

  final DateTime start;
  final PreprocessingParameters parameters;
  final PositionProcessor _position;
  final PaceProcessor _pace;
  final MovementTimeProcessor _movement;
  final HeartRateProcessor _heartRate;
  final SettlingProcessor _settling;
  final AltitudeProcessor _altitude;
  final StepsSeries _steps;
  final SegmentBuilder _segments;

  ProcessedPosition addPosition(RawPosition p) {
    final r = _position.add(p);
    if (r.accepted) {
      final segment = _segments.add(p, r.countedDistanceMeters);
      if (segment != null) {
        _pace.add(segment);
        _movement.add(segment);
        _settling.add(segment);
      }
    }
    return r;
  }

  ProcessedHeartRate addHeartRate(RawHeartRate h) => _heartRate.add(h);

  ProcessedAltitude addAltitude(RawAltitude a) => _altitude.add(a);

  ProcessedSteps addSteps(RawSteps s) => _steps.add(s);

  /// Manuelle Pause (Ereignis).
  void pause(DateTime time) {
    _position.pause(time);
    _heartRate.pause(time);
    _segments.reset();
    _movement.pause(time);
  }

  void resume(DateTime time) {
    _position.resume(time);
    _heartRate.resume(time);
    _segments.reset();
    _movement.resume(time);
  }

  /// Zuordnung über Zeitstempel (FR-0046).
  Lookup<RawPosition> positionAt(DateTime t) => _position.positionAt(t);

  /// Letzter akzeptierter Puls `<= t`, `unavailable` über der Einzellücke.
  Lookup<RawHeartRate> heartRateAt(DateTime t) => _heartRate.heartRateAt(t);

  /// Letzte akzeptierte Höhe `<= t`, nur mit Alter (keine Grenze).
  Lookup<RawAltitude> altitudeAt(DateTime t) => _altitude.altitudeAt(t);

  /// Letzter Schrittwert `<= t`, nur mit Alter (keine Grenze).
  Lookup<RawSteps> stepsAt(DateTime t) => _steps.stepsAt(t);

  RunPreprocessing result({required DateTime at}) {
    final movement = _movement.result(at: at);
    return RunPreprocessing(
      parameters: parameters,
      position: _position.result(at: at),
      pace: _pace.result(at: at),
      movement: movement,
      heartRate: _heartRate.result(at: at),
      settling: _settling.result(restarts: movement.resumedAt),
      altitude: _altitude.result(at: at),
      steps: _steps.result(),
    );
  }
}

extension RunPreprocessingQuality on RunPreprocessing {
  /// Qualität des Abschnitts `[from, to]` (FR-0048).
  SectionQuality assessSection(DateTime from, DateTime to) =>
      SectionQuality.assess(
        from: from,
        to: to,
        heartRate: heartRate,
        position: position,
        settlingIntervals: settling.intervals,
        parameters: parameters,
      );
}
