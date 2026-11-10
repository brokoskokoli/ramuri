import '../fitness/heart_rate_basis.dart';
import '../goals/training_goal.dart';
import '../prediction/reference_performance.dart';
import '../statistics/run_figures.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'target_intensity.dart';
import 'weekly_time.dart' show planDay;

/// Ergebnis von [buildPlanInputs]: die Eingaben und das Ziel, mit dem zu
/// rechnen ist. Ersetzen Läufe den Stand (PAR-192), trägt [goal] die daraus
/// gerechnete Wochenzeit; das gespeicherte Ziel bleibt unverändert.
class BuiltPlanInputs {
  const BuiltPlanInputs({required this.inputs, required this.goal});
  final PlanInputs inputs;

  /// Ziel für `generatePlan`/`assessGoal` (Stand ggf. aus Läufen).
  final TrainingGoal goal;
}

/// Ob ein Lauf als „locker“ zählt (PAR-111): Durchschnittspuls unter der
/// Reservegrenze von Zone 2 (`zoneBounds[2]`, Standard 0,70) **und** unter
/// [IntensityParameters.easyMaxShareOfMaxHr] der HFmax, es gilt der niedrigere
/// Wert. Ohne Durchschnittspuls, HFmax oder Ruhepuls: nicht bestimmbar,
/// also `false` (ANNAHME: Es gibt keine Klassifikation „locker“ je Lauf; die
/// Einordnung gegenüber Vorläufen, `classifyRun`, ist keine).
bool isEasyRun(
  RunFigures run,
  HeartRateBasis? heartRate,
  List<double> zoneBounds, {
  IntensityParameters intensity = const IntensityParameters(),
}) {
  final avg = run.heartRateAverageBpm;
  final max = heartRate?.usableMaxBpm;
  final rest = heartRate?.usableRestingBpm;
  if (avg == null || max == null || rest == null || max <= rest) return false;
  if (zoneBounds.length < 3) return false;
  final reserveLimit = rest + zoneBounds[2] * (max - rest);
  final share = intensity.easyMaxShareOfMaxHr * max;
  final limit = reserveLimit < share ? reserveLimit : share;
  return avg < limit;
}

DateTime? _runDay(RunFigures r) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(r.day);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// Median; bei gerader Zahl das Mittel der beiden mittleren Werte.
double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Plan-Eingaben aus gespeicherten Daten (ADR-0010 Punkt 2, PAR-192,
/// PAR-205). Rein: kein Speicherzugriff, „heute“ wird übergeben.
///
/// - [runs]: Zusammenfassungen beendeter Läufe; mindestens die letzten
///   `easyWindowWeeks` Wochen, für die Pause seit der Referenz (PAR-101) alle
///   seit dem Datum der Referenz. Läufe nach [today] zählen nicht.
/// - [reference]: die aktive Referenzleistung (`activeReference`), falls
///   gültig; sie geht mit Datum, nicht mit Alter in die Eingaben.
/// - [heartRate], [zoneBounds]: Profil (HFmax, Ruhepuls, Schätzkennzeichen).
/// - [vo2max], [vo2maxGrade]: Langzeitwert und Güte; die Prüfung nach PAR-081
///   liegt beim Aufrufer (`vo2maxGrade == null`: unzureichend).
///
/// Lockeres Tempo (PAR-205): Median der Durchschnittspace aller lockeren
/// Läufe ([isEasyRun]) im Fenster; ab `peakMinEasyRuns` Läufen gesetzt, sonst
/// `null` (die Zahl der Läufe bleibt in `easyRunCount`).
///
/// Stand (PAR-192): „Vorhandene Läufe ersetzen die Angabe“. ANNAHME: Mittel
/// der Laufzeit (Bewegungszeit) je Kalenderwoche über die Wochen des Fensters,
/// in denen gelaufen wurde. Ohne Läufe im Fenster gilt die Angabe im Ziel.
BuiltPlanInputs buildPlanInputs({
  required TrainingGoal goal,
  required DateTime today,
  Iterable<RunFigures> runs = const [],
  ReferencePerformance? reference,
  HeartRateBasis? heartRate,
  List<double>? zoneBounds,
  double? vo2max,
  Vo2maxGrade? vo2maxGrade,
  PlanParameters parameters = const PlanParameters(),
  IntensityParameters intensityParameters = const IntensityParameters(),
}) {
  final t = planDay(today);
  final bounds = IntensityInputs(zoneBounds: zoneBounds).zoneBounds;
  final windowStart = t.subtract(
    Duration(days: 7 * parameters.easyWindowWeeks - 1),
  );

  // Läufe im Fenster [windowStart, t].
  final inWindow = <(RunFigures, DateTime)>[];
  final allDays = <DateTime>[];
  for (final r in runs) {
    final d = _runDay(r);
    if (d == null || d.isAfter(t)) continue;
    allDays.add(d);
    if (!d.isBefore(windowStart)) inWindow.add((r, d));
  }

  // Lockeres Tempo (PAR-205).
  final paces = <double>[];
  for (final (r, _) in inWindow) {
    final pace = r.averagePaceSecondsPerKm;
    if (pace == null || !pace.isFinite || pace <= 0) continue;
    if (!isEasyRun(r, heartRate, bounds, intensity: intensityParameters)) {
      continue;
    }
    paces.add(pace);
  }
  final easyPace = paces.length >= parameters.peakMinEasyRuns
      ? _median(paces)
      : null;

  // Stand aus Läufen (PAR-192).
  final seconds = <DateTime, double>{};
  for (final (r, d) in inWindow) {
    final time = r.movingTime ?? r.totalTime;
    if (time == null || time <= Duration.zero) continue;
    final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
    seconds[monday] = (seconds[monday] ?? 0) + time.inMicroseconds / 1e6;
  }
  final effective = seconds.isEmpty
      ? goal
      : goal.withStand(seconds.values.reduce((a, b) => a + b) / seconds.length);

  // Referenz mit Datum; längste Pause seit der Referenz (PAR-101, PAR-202).
  IntensityInputs? intensity;
  final refDay = reference == null ? null : planDay(reference.date);
  var pause = 0;
  if (refDay != null) {
    final days = [refDay, ...allDays.where((d) => !d.isBefore(refDay)), t]
      ..sort();
    for (var i = 1; i < days.length; i++) {
      final gap = days[i].difference(days[i - 1]).inDays;
      if (gap > pause) pause = gap;
    }
  }
  final hasHr = heartRate != null;
  if (reference != null || vo2max != null || hasHr || zoneBounds != null) {
    intensity = IntensityInputs(
      referenceSeconds: reference?.seconds,
      referenceMeters: reference?.distanceMeters,
      referenceDate: refDay,
      longestPauseSinceReferenceDays: pause,
      vo2max: vo2max,
      vo2maxGrade: vo2maxGrade,
      heartRate: heartRate,
      zoneBounds: zoneBounds,
    );
  }

  final base = PlanInputs.forNewGoal(effective, t, parameters: parameters);
  final inputs = PlanInputs(
    anchor: base.anchor,
    startWeeklyMinutes: base.startWeeklyMinutes,
    today: t,
    walkRunWeeks: base.walkRunWeeks,
    walkRunStart: base.walkRunStart,
    walkRunFrom: base.walkRunFrom,
    easyPaceSecondsPerKm: easyPace,
    easyRunCount: paces.length,
    intensity: intensity,
  );
  return BuiltPlanInputs(inputs: inputs, goal: effective);
}
