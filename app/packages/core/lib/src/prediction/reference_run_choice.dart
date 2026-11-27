import '../calendar/calendar_day.dart';
import 'prediction_parameters.dart';
import 'prediction_run.dart';
import 'reference_performance.dart';

/// Läufe, aus denen der Nutzer eine Referenz übernehmen kann (FR-0129):
/// gemessene Distanz ab [PredictionParameters.suggestionMinimumMeters]
/// (PAR-185), Datum höchstens [PredictionParameters.runPickerWindowDays]
/// Kalendertage vor [now] und nicht danach, Bewegungszeit größer null.
/// Neueste zuerst; bei gleichem Tag bleibt die Reihenfolge von [runs]
/// (der Leser liefert neuesten Start zuerst).
///
/// Ob die Referenz gültig ist ([ReferencePerformance.validate], etwa die
/// Tempospanne), prüft erst die Übernahme; die Liste zeigt jeden Lauf.
List<PredictionRun> referenceRunChoices({
  required Iterable<PredictionRun> runs,
  required DateTime now,
  PredictionParameters parameters = const PredictionParameters(),
}) {
  final p = parameters;
  final out = <PredictionRun>[];
  for (final run in runs) {
    final meters = run.distanceMeters;
    if (meters == null || !meters.isFinite) continue;
    if (meters < p.suggestionMinimumMeters) continue;
    if (!(run.movingSeconds > 0) || !run.movingSeconds.isFinite) continue;
    final age = daysBetween(run.date, now);
    if (age < 0 || age > p.runPickerWindowDays) continue;
    out.add(run);
  }
  final order = {for (var i = 0; i < out.length; i++) out[i]: i};
  out.sort((a, b) {
    final c = calendarDay(b.date).compareTo(calendarDay(a.date));
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  return out;
}

/// Zählt der Lauf nach Angabe des Nutzers als voll gelaufen (RPE ab
/// [PredictionParameters.suggestionMinimumRpe], PAR-185)? Ohne Angabe nicht:
/// Vor der Übernahme eines solchen Laufs weist die App darauf hin (FR-0131).
bool isHardEnoughForReference(
  PredictionRun run, [
  PredictionParameters parameters = const PredictionParameters(),
]) {
  final rpe = run.rpe;
  return rpe != null && rpe >= parameters.suggestionMinimumRpe;
}

/// Die Referenz aus einem übernommenen Lauf: bestätigter Lauf mit Lauf-ID,
/// Distanz, Bewegungszeit und Datum des Laufs (FR-0129, FR-0131). `null`
/// ohne gemessene Distanz.
ReferencePerformance? referenceFromRun(PredictionRun run, DateTime now) {
  final meters = run.distanceMeters;
  if (meters == null) return null;
  return ReferencePerformance(
    kind: ReferenceKind.confirmedRun,
    distanceMeters: meters,
    seconds: run.movingSeconds,
    date: run.date,
    createdAt: now,
    runId: run.id,
  );
}
