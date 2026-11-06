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
    this.parameters = const PreprocessingParameters.v3(),
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
  bool _paused = false;

  // Höhe zählt nur zu einer angenommenen Position gleicher Zeit (ein
  // verworfener Sprungpunkt liegt an einem anderen Ort). Die Regel steckt hier,
  // damit die Aufzeichnung und eine Neuberechnung aus den Rohdaten (alle
  // Rohhöhen werden gespeichert) dasselbe rechnen, in beliebiger Reihenfolge
  // von Position und Höhe gleicher Zeit.
  DateTime? _positionTime;
  bool _positionAccepted = false;
  final List<RawAltitude> _pendingAltitudes = [];

  /// Erkannte Pause (getrennt von `pause`), billig je Punkt abfragbar.
  AutoPauseState get autoPauseState => _movement.autoPauseState;

  ProcessedPosition addPosition(RawPosition p) {
    // Höhen vor diesem Zeitpunkt hatten keine Position zu ihrer Zeit.
    _releasePending((a) => a.time.isBefore(p.time));
    final r = _position.add(p);
    _positionTime = p.time;
    _positionAccepted = r.accepted;
    if (r.accepted) {
      if (r.reanchored) _altitude.restart();
      final segment = _segments.add(
        p,
        r.countedDistanceMeters,
        forceGap: r.reanchored,
      );
      if (segment != null) {
        _pace.add(segment);
        _movement.add(segment);
        _settling.add(segment);
      }
    }
    // Höhen gleicher Zeit, die vor der Position ankamen: jetzt entscheidbar.
    final same = _pendingAltitudes
        .where((a) => a.time == p.time)
        .toList(growable: false);
    _pendingAltitudes.removeWhere((a) => a.time == p.time);
    if (r.accepted) same.forEach(_altitude.add);
    return r;
  }

  ProcessedHeartRate addHeartRate(RawHeartRate h) => _heartRate.add(h);

  /// Höhe zum Zeitstempel. Liegt zu genau dieser Zeit eine verworfene Position
  /// vor, zählt sie nicht (`null`). Ist die Position dieser Zeit noch nicht
  /// bekannt (Höhe zuerst), wartet die Höhe bis zur nächsten Position oder
  /// Pause (`null`); ohne Position zu ihrer Zeit zählt sie dann normal. Ohne
  /// jede bisherige Position (reine Höhenreihe, erster Punkt ist immer
  /// angenommen) zählt sie sofort.
  ProcessedAltitude? addAltitude(RawAltitude a) {
    final t = _positionTime;
    if (t == null) return _altitude.add(a);
    if (a.time.isAfter(t)) {
      _pendingAltitudes.add(a);
      return null;
    }
    if (a.time == t && !_positionAccepted) return null;
    return _altitude.add(a);
  }

  void _releasePending(bool Function(RawAltitude) test) {
    final due = _pendingAltitudes.where(test).toList(growable: false);
    _pendingAltitudes.removeWhere(test);
    due.forEach(_altitude.add);
  }

  ProcessedSteps addSteps(RawSteps s) => _steps.add(s);

  /// Manuelle Pause (Ereignis).
  void pause(DateTime time) {
    if (_paused) return;
    _paused = true;
    _releasePending((_) => true);
    _position.pause(time);
    _heartRate.pause(time);
    _segments.reset();
    _movement.pause(time);
    _altitude.pause();
    _steps.pause();
  }

  void resume(DateTime time) {
    if (!_paused) return;
    _paused = false;
    _releasePending((_) => true);
    _position.resume(time);
    _heartRate.resume(time);
    _segments.reset();
    _movement.resume(time);
    _altitude.resume();
    _steps.resume();
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
      pace: _pace.result(
        at: at,
        inAutoPause: movement.autoPauseState == AutoPauseState.standstillPause,
      ),
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
