import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../recalculation/run_analysis.dart' show replayJob;
import '../recalculation/value_calculation_service.dart' show dayOfRun;
import '../statistics/offload.dart';
import '../statistics/run_overview.dart';
import 'prediction_parameters.dart';
import 'prediction_run.dart';

/// Baut [PredictionRun] aus den vorhandenen Daten, ohne neue Rechnung:
/// Bewegungszeit und Distanz aus der Kurzfassung des Laufs
/// ([RunOverviewService], bei veralteter Kurzfassung neu gerechnet), die
/// 30-s-Tempowerte aus der Vorverarbeitung (`pace.medianSeries`, PAR-006). Der
/// `rpe` bleibt `null`, bis WP18 ihn liefert.
///
/// Die Tempowerte brauchen eine Wiedergabe der Rohdaten je Lauf. Sie werden
/// darum nur für Läufe gelesen, die als Vorschlag in Frage kommen
/// (Distanz >= [PredictionParameters.suggestionMinimumMeters]); für kürzere
/// bleibt `paceSamples` `null`. Mit `withPaceSamples: false` entfällt die
/// Wiedergabe ganz.
class PredictionRunReader {
  PredictionRunReader({
    required this.session,
    required this.clock,
    this.parameters = const PredictionParameters(),
    this.preprocessing = const PreprocessingParameters.v4(),
    this.offload = inlineOffload,
  });

  final StorageSession session;
  final Clock clock;
  final PredictionParameters parameters;
  final PreprocessingParameters preprocessing;
  final Offload offload;

  /// Beendete Läufe, neuester Start zuerst. Läufe ohne lesbare Kurzfassung
  /// (Rohdaten nicht lesbar) oder ohne Zeit außerhalb von Positionslücken fehlen.
  Future<List<PredictionRun>> load({bool withPaceSamples = true}) async {
    final overviews = await RunOverviewService(
      session: session,
      clock: clock,
      parameters: preprocessing,
      offload: offload,
    ).load();
    final out = <PredictionRun>[];
    for (final o in overviews) {
      // Zeit ohne Positionslücken (`paceTime`): Die Distanz enthält die
      // überbrückte Strecke nicht, die Bewegungszeit ihre Zeit schon.
      final moving = o.paceTime;
      if (o.readFailed || moving == null || moving <= Duration.zero) continue;
      final meters = o.distanceMeters;
      List<double>? pace;
      if (withPaceSamples &&
          meters != null &&
          meters >= parameters.suggestionMinimumMeters) {
        pace = await _paceSamples(o);
      }
      out.add(
        PredictionRun(
          id: '${o.run.id}',
          date: DateTime.parse(dayOfRun(o.run)),
          movingSeconds: moving.inMicroseconds / Duration.microsecondsPerSecond,
          distanceMeters: meters,
          paceSamples: pace,
        ),
      );
    }
    return out;
  }

  Future<List<double>?> _paceSamples(RunOverview o) async {
    try {
      final run = o.run;
      final pre = await offload(replayJob, (
        run: run,
        end: run.endedAt!,
        raw: await session.rawData.read(run.id),
        gaps: await session.markers.gaps(run.id),
        parameters: preprocessing,
      ));
      return [for (final s in pre.pace.medianSeries) s.metersPerSecond];
    } on Object {
      // Nicht lesbar: Stabilität nicht bestimmbar, kein Vorschlag.
      return null;
    }
  }
}
