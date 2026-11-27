import '../../ports/storage_plan.dart';
import 'plan_adjust.dart' show applyPlanUnderloadRaise;
import 'plan_deviation.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'target_intensity.dart' show IntensityParameters;
import 'weekly_time.dart' show planDay;

/// Unterforderung (PAR-236): Lockere Läufe sind nach Puls hart, fühlen sich
/// aber leicht an. Nur bei „adaptiv“ (FR-0216). Erstes Muster: Hinweis, die
/// HFmax zu prüfen; erneutes Muster aus späteren Läufen: Frage „Plan etwas
/// steigern?“. Alles rein: kein `DateTime.now()`, kein Speicher.

/// Grund-Code der Fassung nach „Ja, steigern“ (PAR-236). Auslöser ist
/// `feedback` wie bei der Rückmeldung (PAR-200).
const String planReasonUnderload = 'underload';

/// Einstellungsschlüssel: Stufe der Unterforderung ([PlanUnderloadStage]).
/// Kein Gesundheitswert; geht mit den übrigen Einstellungen ins Archiv.
const String planUnderloadStageKey = 'plan.underload_stage';

/// Einstellungsschlüssel: Zeitpunkt (UTC, ISO 8601) der letzten Stufe der
/// Unterforderung; gezählt werden nur Läufe, die danach endeten.
const String planUnderloadSinceKey = 'plan.underload_since';

/// Ein zugeordneter Lauf für das Muster nach PAR-236.
class PlanUnderloadRun {
  const PlanUnderloadRun({
    required this.kind,
    required this.endedAt,
    this.rpe,
    this.highHrMinutes,
  });

  /// Art der Einheit, der der Lauf zugeordnet ist.
  final PlanUnitKind kind;

  /// Ende des Laufs (UTC).
  final DateTime endedAt;

  /// RPE-Angabe des Nutzers oder `null`.
  final int? rpe;

  /// Minuten bei mindestens 80 % HFmax (Laufwert `high_hr_time`, PAR-058)
  /// oder `null` ohne Puls bzw. HFmax.
  final double? highHrMinutes;
}

/// Locker geplant im Sinne von PAR-236: locker, lang oder Geh-Lauf.
bool planUnderloadEasyKind(PlanUnitKind kind) =>
    kind == PlanUnitKind.easy ||
    kind == PlanUnitKind.long ||
    kind == PlanUnitKind.walkRun;

/// Zählt [run] für das Muster? Locker geplant, mit Puls und mit RPE.
bool planUnderloadCounts(PlanUnderloadRun run) =>
    planUnderloadEasyKind(run.kind) &&
    run.rpe != null &&
    run.highHrMinutes != null;

/// „Hart nach Puls, leicht empfunden“ (PAR-236): zählt ([planUnderloadCounts]),
/// mindestens [PlanParameters.completedIntensiveMinHighHrMinutes] Minuten bei
/// mindestens 80 % HFmax (PAR-058) und RPE höchstens die Obergrenze der
/// Vorgabe der Einheit (PAR-105, [planUnitRpeUpper]).
bool planUnderloadRunMatches(
  PlanUnderloadRun run, {
  PlanParameters parameters = const PlanParameters(),
  IntensityParameters intensity = const IntensityParameters(),
}) {
  if (!planUnderloadCounts(run)) return false;
  final upper = planUnitRpeUpper(run.kind, intensity: intensity);
  return upper != null &&
      run.highHrMinutes! >= parameters.completedIntensiveMinHighHrMinutes &&
      run.rpe! <= upper;
}

/// Muster nach PAR-236: Von den letzten
/// [PlanParameters.underloadWindowRuns] zählenden Läufen ([planUnderloadCounts],
/// nach Ende geordnet) sind mindestens [PlanParameters.underloadRuns] „hart
/// nach Puls, leicht empfunden“. Läufe ohne Puls oder ohne RPE zählen nicht
/// mit.
bool planUnderloadPattern(
  Iterable<PlanUnderloadRun> runs, {
  PlanParameters parameters = const PlanParameters(),
  IntensityParameters intensity = const IntensityParameters(),
}) {
  final counted = [
    for (final r in runs)
      if (planUnderloadCounts(r)) r,
  ]..sort((a, b) => a.endedAt.compareTo(b.endedAt));
  final n = parameters.underloadWindowRuns;
  final window = counted.length > n
      ? counted.sublist(counted.length - n)
      : counted;
  final hits = window
      .where(
        (r) => planUnderloadRunMatches(
          r,
          parameters: parameters,
          intensity: intensity,
        ),
      )
      .length;
  return hits >= parameters.underloadRuns;
}

/// Stufe der Unterforderung (PAR-236), gespeichert unter
/// [planUnderloadStageKey].
enum PlanUnderloadStage {
  /// Noch kein Muster.
  none,

  /// Erstes Muster: Hinweis „HFmax prüfen“ steht offen.
  hint,

  /// Hinweis beantwortet („HFmax prüfen“ oder „Passt so“).
  hintDone,

  /// Erneutes Muster: Frage „Plan etwas steigern?“ steht offen.
  question,

  /// Frage mit „Ja, steigern“ beantwortet.
  accepted,

  /// Frage mit „Nein“ beantwortet.
  declined,
}

/// Was die App gerade zeigt (PAR-236).
enum PlanUnderloadPrompt { hint, question }

/// Gespeicherter Zustand: Stufe und Zeitpunkt der letzten Stufe, ohne
/// Gesundheitswert.
class PlanUnderloadState {
  const PlanUnderloadState({this.stage = PlanUnderloadStage.none, this.since});

  /// Aus den Einstellungen; Unbekanntes gilt als [PlanUnderloadStage.none].
  factory PlanUnderloadState.parse(String? stage, String? since) {
    final s = PlanUnderloadStage.values
        .where((v) => v.name == stage)
        .firstOrNull;
    return PlanUnderloadState(
      stage: s ?? PlanUnderloadStage.none,
      since: since == null ? null : DateTime.tryParse(since)?.toUtc(),
    );
  }

  final PlanUnderloadStage stage;

  /// Ab hier zählen Läufe (Ende danach); `null`: alle Läufe.
  final DateTime? since;

  String get stageText => stage.name;
  String? get sinceText => since?.toUtc().toIso8601String();

  /// Offene Anzeige: Hinweis oder Frage, sonst `null`.
  PlanUnderloadPrompt? get prompt => switch (stage) {
    PlanUnderloadStage.hint => PlanUnderloadPrompt.hint,
    PlanUnderloadStage.question => PlanUnderloadPrompt.question,
    _ => null,
  };
}

/// Beginn der Zählung: der späteste Zeitpunkt aus der letzten Stufe, der
/// gespeicherten letzten Änderung der HFmax ([hrMaxChangedAt]) und dem
/// Jahresbeginn, an dem sich die genäherte HFmax geändert hat
/// ([estimatedChangedAt], `estimatedMaxHeartRateChangedAt`); nach einer
/// Änderung der wirksamen HFmax beginnt die Zählung neu. `null`: alle Läufe.
DateTime? planUnderloadCountFrom(
  PlanUnderloadState state,
  DateTime? hrMaxChangedAt, {
  DateTime? estimatedChangedAt,
}) {
  DateTime? latest;
  for (final t in [state.since, hrMaxChangedAt, estimatedChangedAt]) {
    if (t != null && (latest == null || t.isAfter(latest))) latest = t;
  }
  return latest;
}

/// Nächster Zustand am Zeitpunkt [now] (PAR-236), `null`: unverändert.
///
/// - [pattern]: Muster aus den Läufen ab [planUnderloadCountFrom].
/// - [blocked]: „fix“, Warnsignal (FR-0203), Korrektur nach unten (PAR-201)
///   oder Readiness nach PAR-173; dann ändert sich nichts.
/// - [canRaise]: Die Steigerung ließe sich anwenden
///   ([applyPlanUnderloadRaise]); sonst kommt keine Frage.
///
/// Ohne Stufe führt das erste Muster zum Hinweis. Nach dem Hinweis (auch
/// offen) und nach einer Antwort auf die Frage führt ein neues Muster zur
/// Frage. Eine offene Frage bleibt.
PlanUnderloadState? planUnderloadAdvance({
  required PlanUnderloadState state,
  required bool pattern,
  required bool blocked,
  required bool canRaise,
  required DateTime now,
}) {
  if (blocked || !pattern) return null;
  final at = now.toUtc();
  switch (state.stage) {
    case PlanUnderloadStage.none:
      return PlanUnderloadState(stage: PlanUnderloadStage.hint, since: at);
    case PlanUnderloadStage.hint ||
        PlanUnderloadStage.hintDone ||
        PlanUnderloadStage.accepted ||
        PlanUnderloadStage.declined:
      if (!canRaise) return null;
      return PlanUnderloadState(stage: PlanUnderloadStage.question, since: at);
    case PlanUnderloadStage.question:
      return null;
  }
}

/// PAR-201 korrigiert gerade nach unten: Eine Fassung der Wochenprüfung mit
/// Grund `repeatWeek`, `noIncrease` oder `fatigue` (auch nach `goalChange,`
/// bzw. `ruleVersion,`) hat ihren Anker in der Woche von [today].
bool planCorrectedDownThisWeek(
  Iterable<PlanVersionRecord> history,
  DateTime today,
) {
  final t = planDay(today);
  final monday = t.subtract(Duration(days: t.weekday - DateTime.monday));
  const down = {'repeatWeek', 'noIncrease', 'fatigue'};
  for (final v in history) {
    if (!v.reason.split(',').any(down.contains)) continue;
    try {
      if (v.inputs.anchor == monday) return true;
    } on Object {
      continue;
    }
  }
  return false;
}
