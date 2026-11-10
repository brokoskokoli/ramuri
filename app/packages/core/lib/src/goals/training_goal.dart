import '../prediction/prediction_parameters.dart';
import '../prediction/reference_performance.dart' show calendarDay;

/// Zielart (FR-0135): Strecke, Zeit oder offenes Fitnessziel.
enum GoalType {
  /// Eine Strecke erstmals durchlaufen (ohne Zielzeit).
  distance,

  /// Eine Strecke in einer Zielzeit laufen.
  time,

  /// Offenes Fitnessziel („fitter werden“): ohne Strecke, Zeit und Datum
  /// (FR-0137, PAR-196).
  open,
}

/// Zielstrecken in Phase 2: bis Halbmarathon (FR-0135, OQ-0004).
enum GoalDistance {
  fiveKilometers,
  tenKilometers,
  halfMarathon;

  /// Streckenlänge in Metern, gleich der Prognose (FR-0128).
  double get meters => switch (this) {
    fiveKilometers => PredictionDistance.fiveKilometers.meters,
    tenKilometers => PredictionDistance.tenKilometers.meters,
    halfMarathon => PredictionDistance.halfMarathon.meters,
  };
}

/// Antwort auf „Kannst du 30 min am Stück laufen?“ (PAR-192).
enum ContinuousRun30 { yes, no, unknown }

/// Warum ein Ziel nicht gültig ist (FR-0135 bis FR-0137).
enum GoalProblem {
  /// Strecken- oder Zeitziel ohne Strecke.
  distanceMissing,

  /// Offenes Ziel mit Strecke.
  distanceNotAllowed,

  /// Zeitziel ohne Zielzeit.
  targetTimeMissing,

  /// Zielzeit bei einem Strecken- oder offenen Ziel.
  targetTimeNotAllowed,

  /// Zielzeit nicht endlich oder nicht positiv.
  targetTimeInvalid,

  /// Offenes Ziel mit Datum (läuft ohne Datum fort, PAR-196).
  targetDateNotAllowed,

  /// Zieldatum vor heute.
  targetDateInPast,

  /// Keine Lauftage gewählt.
  runDaysEmpty,

  /// Ein Wochentag außerhalb 1 (Montag) bis 7 (Sonntag).
  runDayInvalid,

  /// Maximale Zeit je Einheit nicht endlich oder nicht positiv.
  maxSessionInvalid,

  /// Regler (höchste Wochenzeit) nicht endlich oder nicht positiv.
  weeklyCapInvalid,

  /// Genannte aktuelle Wochenzeit nicht endlich oder nicht positiv.
  currentWeeklyInvalid,

  /// Weder Wochenzeit noch Antwort zu „30 min am Stück“ (PAR-192). Gilt nur,
  /// wenn keine Läufe vorhanden sind, die die Angabe ersetzen.
  standMissing,
}

/// Die Zahlen der Zielprüfung, jede mit ihrer Regel.
///
/// Nur die Grenzen, die eine Regel setzt. Für die maximale Zeit je Einheit
/// und den Regler setzt keine PAR eine Ober- oder Untergrenze (Lücke); sie
/// müssen nur endlich und positiv sein.
class GoalParameters {
  const GoalParameters({this.minRunDays = 1, this.maxRunDays = 7})
    : assert(minRunDays >= 1),
      assert(maxRunDays >= minRunDays && maxRunDays <= 7);

  /// PAR-197: ab 1 Lauftag je Woche.
  final int minRunDays;

  /// PAR-197: bis 7 Lauftage (6 und 7 nur, wenn der Nutzer sie festlegt).
  final int maxRunDays;
}

/// Persönliches Trainingsziel mit den Angaben für die Planung (FR-0135,
/// FR-0136). Eine feste Zielzeit ist nicht nötig (FR-0137): Nur ein Zeitziel
/// trägt eine.
class TrainingGoal {
  const TrainingGoal({
    required this.type,
    required this.runDays,
    required this.maxSessionSeconds,
    required this.weeklyCapSeconds,
    required this.createdAt,
    required this.hardSessionEnabled,
    this.currentWeeklySeconds,
    this.canRun30 = ContinuousRun30.unknown,
    this.distance,
    this.targetSeconds,
    this.targetDate,
  });

  final GoalType type;

  /// Strecke bei [GoalType.distance] und [GoalType.time], sonst `null`.
  final GoalDistance? distance;

  /// Zielzeit in Sekunden, nur bei [GoalType.time].
  final double? targetSeconds;

  /// Gewünschtes Zieldatum (lokaler Kalendertag). Optional außer beim offenen
  /// Ziel, das keines hat.
  final DateTime? targetDate;

  /// Lauftage: Wochentage 1 (Montag) bis 7 (Sonntag), wie [DateTime.weekday].
  /// Ihre Anzahl ist die Zahl der Trainingstage je Woche (PAR-197).
  final Set<int> runDays;

  /// Maximale Trainingszeit je Einheit in Sekunden (FR-0136, PAR-195).
  final double maxSessionSeconds;

  /// Regler: höchste Wochenzeit in Sekunden (PAR-196).
  final double weeklyCapSeconds;

  /// Zeitpunkt des Anlegens.
  final DateTime createdAt;

  /// Schalter „harte Einheit“ (PAR-198) als gespeicherter Wert. Der Standard
  /// ([defaultHardSession]) gilt nur beim Anlegen; Speichern ändert ihn nicht.
  final bool hardSessionEnabled;

  /// Heutiger Stand (PAR-192): genannte Wochenzeit in Sekunden oder `null`.
  final double? currentWeeklySeconds;

  /// Heutiger Stand (PAR-192): Antwort zu „30 min am Stück“.
  final ContinuousRun30 canRun30;

  /// Kopie mit anderer Wochenzeit als Stand (Sekunden oder `null`); alles
  /// andere unverändert. Für die Rechnung mit dem Stand aus vorhandenen
  /// Läufen (PAR-192), nicht zum Speichern.
  TrainingGoal withStand(double? currentWeeklySeconds) => TrainingGoal(
    type: type,
    runDays: runDays,
    maxSessionSeconds: maxSessionSeconds,
    weeklyCapSeconds: weeklyCapSeconds,
    createdAt: createdAt,
    hardSessionEnabled: hardSessionEnabled,
    currentWeeklySeconds: currentWeeklySeconds,
    canRun30: canRun30,
    distance: distance,
    targetSeconds: targetSeconds,
    targetDate: targetDate,
  );

  /// Standard des Schalters „harte Einheit“ beim Anlegen (PAR-198): an bei
  /// Zeitzielen, sonst aus.
  static bool defaultHardSession(GoalType type) => type == GoalType.time;

  /// Erstes Problem oder `null`. `today` wird übergeben; ein Datum von heute
  /// ist gültig. [standRequired]: ohne Wochenzeit und ohne Ja/Nein zu „30 min
  /// am Stück“ ist das Ziel unvollständig (PAR-192). Mit vorhandenen Läufen
  /// ersetzen diese die Angabe, dann `false`; beim Speichern des Ziels wird
  /// nicht danach gefragt.
  GoalProblem? validate(
    DateTime today, [
    GoalParameters? p,
    bool standRequired = true,
  ]) {
    final params = p ?? const GoalParameters();
    final dist = distance, secs = targetSeconds, date = targetDate;
    if (type == GoalType.open) {
      if (dist != null) return GoalProblem.distanceNotAllowed;
      if (date != null) return GoalProblem.targetDateNotAllowed;
    } else if (dist == null) {
      return GoalProblem.distanceMissing;
    }
    if (type == GoalType.time) {
      if (secs == null) return GoalProblem.targetTimeMissing;
      if (!secs.isFinite || !(secs > 0)) return GoalProblem.targetTimeInvalid;
    } else if (secs != null) {
      return GoalProblem.targetTimeNotAllowed;
    }
    if (date != null && calendarDay(date).isBefore(calendarDay(today))) {
      return GoalProblem.targetDateInPast;
    }
    if (runDays.any((d) => d < DateTime.monday || d > DateTime.sunday)) {
      return GoalProblem.runDayInvalid;
    }
    if (runDays.length < params.minRunDays) return GoalProblem.runDaysEmpty;
    if (runDays.length > params.maxRunDays) return GoalProblem.runDayInvalid;
    if (!maxSessionSeconds.isFinite || !(maxSessionSeconds > 0)) {
      return GoalProblem.maxSessionInvalid;
    }
    if (!weeklyCapSeconds.isFinite || !(weeklyCapSeconds > 0)) {
      return GoalProblem.weeklyCapInvalid;
    }
    final cur = currentWeeklySeconds;
    if (cur != null && (!cur.isFinite || !(cur > 0))) {
      return GoalProblem.currentWeeklyInvalid;
    }
    if (standRequired && cur == null && canRun30 == ContinuousRun30.unknown) {
      return GoalProblem.standMissing;
    }
    return null;
  }
}
