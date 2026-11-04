import 'latest_value_index.dart';
import 'measurement.dart';
import 'motion_segments.dart';
import 'movement_time_processor.dart';
import 'pace_processor.dart';
import 'position_processor.dart';
import 'preprocessing_parameters.dart';

/// Gesamtergebnis der Vorverarbeitung; wächst mit den Kanälen.
class RunPreprocessing {
  const RunPreprocessing({
    required this.parameterVersion,
    required this.position,
    required this.pace,
    required this.movement,
  });

  final int parameterVersion;
  final PositionResult position;
  final PaceResult pace;
  final MovementResult movement;
}

/// Fasst die Kanalprozessoren zusammen. Keine Uhr: Zeiten kommen von außen.
class RunPreprocessor {
  RunPreprocessor({
    required this.start,
    this.parameters = const PreprocessingParameters.v2(),
  }) : _position = PositionProcessor(parameters, sectionStart: start),
       _pace = PaceProcessor(parameters),
       _movement = MovementTimeProcessor(parameters, start: start),
       _segments = SegmentBuilder(parameters.gapMaxDuration);

  final DateTime start;
  final PreprocessingParameters parameters;
  final PositionProcessor _position;
  final PaceProcessor _pace;
  final MovementTimeProcessor _movement;
  final SegmentBuilder _segments;

  ProcessedPosition addPosition(RawPosition p) {
    final r = _position.add(p);
    if (r.accepted) {
      final segment = _segments.add(p, r.countedDistanceMeters);
      if (segment != null) {
        _pace.add(segment);
        _movement.add(segment);
      }
    }
    return r;
  }

  /// Manuelle Pause (Ereignis).
  void pause(DateTime time) {
    _position.pause(time);
    _segments.reset();
    _movement.pause(time);
  }

  void resume(DateTime time) {
    _position.resume(time);
    _segments.reset();
    _movement.resume(time);
  }

  /// Zuordnung über Zeitstempel (FR-0046).
  Lookup<RawPosition> positionAt(DateTime t) => _position.positionAt(t);

  RunPreprocessing result({required DateTime at}) => RunPreprocessing(
    parameterVersion: parameters.parameterVersion,
    position: _position.result(at: at),
    pace: _pace.result(at: at),
    movement: _movement.result(at: at),
  );
}
