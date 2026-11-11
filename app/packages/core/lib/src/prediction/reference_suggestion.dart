import '../fitness/fitness_parameters.dart';
import 'pace_stability.dart';
import 'prediction_parameters.dart';
import 'prediction_run.dart';
import 'reference_performance.dart';
import 'riegel.dart';

/// Warum ein Lauf als Referenz vorgeschlagen wird (PAR-185).
enum SuggestionBranch {
  /// RPE >= 8, mindestens 3 km, gleichmäßig.
  hardAndSteady,

  /// Schlägt per Riegel die aktive Referenz.
  beatsReference,
}

class ReferenceSuggestion {
  const ReferenceSuggestion({required this.run, required this.branches});

  final PredictionRun run;

  /// Alle zutreffenden Zweige; nie leer.
  final List<SuggestionBranch> branches;
}

/// Vorschläge für Läufe als Referenz (PAR-185, FR-0131). Nur ein Vorschlag:
/// Übernommen wird nie automatisch, der Nutzer bestätigt immer. Abgelehnte
/// Läufe ([rejectedRunIds]) kommen nicht wieder, ebenso Läufe, die schon als
/// Referenz gespeichert sind ([storedRunIds], auch ältere als die aktive).
///
/// Fail closed: ohne gemessene Distanz gibt es keinen Vorschlag; ist die
/// Tempostabilität nicht bestimmbar, löst Zweig 1 nicht aus. Zweig 2 braucht
/// Distanz, Zeit und mindestens [PredictionParameters.suggestionMinimumMeters]
/// (Annahme WP20).
List<ReferenceSuggestion> suggestReferences({
  required Iterable<PredictionRun> runs,
  required ReferencePerformance? activeReference,
  Set<String> rejectedRunIds = const {},
  Set<String> storedRunIds = const {},
  PredictionParameters parameters = const PredictionParameters(),
  SectionSelectionParameters? stability,
}) {
  final p = parameters;
  final stable = stability ?? const FitnessParameters.v4().sectionSelection;
  final out = <ReferenceSuggestion>[];
  for (final run in runs) {
    if (rejectedRunIds.contains(run.id)) continue;
    if (activeReference?.runId == run.id || storedRunIds.contains(run.id)) {
      continue;
    }
    final meters = run.distanceMeters;
    if (meters == null ||
        !meters.isFinite ||
        meters < p.suggestionMinimumMeters) {
      continue;
    }
    if (!(run.movingSeconds > 0) || !run.movingSeconds.isFinite) continue;
    // Ein Vorschlag, den die Prüfung beim Speichern ablehnt, ist keiner.
    if (!referencePaceInRange(meters, run.movingSeconds, p)) continue;
    final branches = <SuggestionBranch>[];
    final rpe = run.rpe;
    if (rpe != null &&
        rpe >= p.suggestionMinimumRpe &&
        isPaceStable(run.paceSamples, stable) == true) {
      branches.add(SuggestionBranch.hardAndSteady);
    }
    // Zweig 2 nur für Läufe ab dem Datum der aktiven Referenz: ein älterer
    // Lauf würde die geltende (jüngste) Referenz nie ablösen.
    if (activeReference != null &&
        !calendarDay(run.date).isBefore(calendarDay(activeReference.date)) &&
        activeReference.seconds > 0 &&
        activeReference.distanceMeters > 0) {
      final riegel = riegelWithParameters(
        p,
        referenceSeconds: activeReference.seconds,
        referenceMeters: activeReference.distanceMeters,
        targetMeters: meters,
      );
      if (run.movingSeconds < riegel) {
        branches.add(SuggestionBranch.beatsReference);
      }
    }
    if (branches.isNotEmpty) {
      out.add(ReferenceSuggestion(run: run, branches: branches));
    }
  }
  return out;
}
