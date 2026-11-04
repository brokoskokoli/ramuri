import 'latest_value_index.dart';
import 'measurement.dart';
import 'position_processor.dart';
import 'preprocessing_parameters.dart';

/// Gesamtergebnis der Vorverarbeitung; wächst mit den Kanälen.
class RunPreprocessing {
  const RunPreprocessing({
    required this.parameterVersion,
    required this.position,
  });

  final int parameterVersion;
  final PositionResult position;
}

/// Fasst die Kanalprozessoren zusammen. Keine Uhr: Zeiten kommen von außen.
class RunPreprocessor {
  RunPreprocessor({
    required this.start,
    this.parameters = const PreprocessingParameters.v2(),
  }) : _position = PositionProcessor(parameters);

  final DateTime start;
  final PreprocessingParameters parameters;
  final PositionProcessor _position;

  ProcessedPosition addPosition(RawPosition p) => _position.add(p);

  /// Manuelle Pause (Ereignis).
  void pause(DateTime time) => _position.pause(time);

  void resume(DateTime time) => _position.resume(time);

  /// Zuordnung über Zeitstempel (FR-0046).
  Lookup<RawPosition> positionAt(DateTime t) => _position.positionAt(t);

  RunPreprocessing result({required DateTime at}) => RunPreprocessing(
    parameterVersion: parameters.parameterVersion,
    position: _position.result(at: at),
  );
}
