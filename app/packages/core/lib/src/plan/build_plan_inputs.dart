import '../fitness/heart_rate_basis.dart';
import '../../ports/storage_values.dart' show ComputedValue, ValueQuality;
import '../goals/training_goal.dart';
import '../prediction/reference_performance.dart';
import '../statistics/run_figures.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
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

/// Ob ein Lauf als „locker“ zählt (PAR-205). Drei Wege:
/// 1. [plannedEasy] gesetzt (der Lauf ist einer Plan-Einheit zugeordnet): nur
///    die Zuordnung zählt, `true` bei lockerer oder langer Einheit (wie
///    PAR-182), `false` bei harter oder Geh-Lauf-Einheit. RPE und Puls gelten
///    dann nie (ein Intervalllauf mit niedrigem Durchschnittspuls ist nicht
///    locker);
/// 2. ohne Zuordnung ([plannedEasy] `null`): [rpe] höchstens
///    [IntensityParameters.easyMaxRpe] (PAR-108, PAR-110);
/// 3. ohne Zuordnung: Durchschnittspuls (PAR-111), siehe unten.
/// Der Weg über RPE und Zuordnung funktioniert ohne Pulsgurt.
///
/// Durchschnittspuls (PAR-111): unter der
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
  bool? plannedEasy,
  int? rpe,
}) {
  if (plannedEasy != null) return plannedEasy;
  if (rpe != null && rpe <= intensity.easyMaxRpe) return true;
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
/// - [easyPlannedRunIds]: Kennungen der Läufe, die einer lockeren oder langen
///   Plan-Einheit zugeordnet sind; [otherPlannedRunIds]: Läufe, die einer
///   anderen Plan-Einheit (hart, Geh-Lauf) zugeordnet sind. Diese zählen nie
///   als locker; RPE und Puls gelten nur für Läufe ohne Zuordnung.
///   [rpeByRunId]: RPE je Lauf (Rückmeldung).
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
  Set<int> easyPlannedRunIds = const {},
  Set<int> otherPlannedRunIds = const {},
  Map<int, int> rpeByRunId = const {},
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
    if (!isEasyRun(
      r,
      heartRate,
      bounds,
      intensity: intensityParameters,
      plannedEasy: easyPlannedRunIds.contains(r.runId)
          ? true
          : (otherPlannedRunIds.contains(r.runId) ? false : null),
      rpe: rpeByRunId[r.runId],
    )) {
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

/// Läufe, die einer Plan-Einheit zugeordnet sind, getrennt nach der
/// Definition „locker“ (wp21-Festlegungen, PAR-205 wie PAR-182): [easy] sind
/// Läufe lockerer oder langer Einheiten, [other] Läufe jeder anderen Einheit
/// (harte Formen, Geh-Lauf, Ruhetag). Einheiten ohne Lauf fehlen.
({Set<int> easy, Set<int> other}) plannedRunIds(Iterable<PlanUnit> units) {
  final easy = <int>{};
  final other = <int>{};
  for (final u in units) {
    final id = u.runId;
    if (id == null) continue;
    switch (u.kind) {
      case PlanUnitKind.easy || PlanUnitKind.long:
        easy.add(id);
      default:
        other.add(id);
    }
  }
  return (easy: easy, other: other);
}

/// Eingaben einer automatischen Neuberechnung: Wochenzählung, Stand,
/// Geh-Lauf-Abfolge, letzte Woche und erreichter Anteil bleiben aus der
/// gespeicherten Fassung [stored]; „heute“, lockeres Tempo samt Zahl der
/// Läufe (PAR-205: „wird bei jeder Neuberechnung neu bestimmt“) und die
/// Grundlage der Zielintensität (Referenz, VO₂max, Puls) kommen aus
/// [measured] (Ergebnis von [buildPlanInputs] für heute).
PlanInputs refreshMeasuredInputs(PlanInputs stored, PlanInputs measured) =>
    PlanInputs(
      anchor: stored.anchor,
      startWeeklyMinutes: stored.startWeeklyMinutes,
      today: measured.today,
      walkRunWeeks: stored.walkRunWeeks,
      walkRunStart: stored.walkRunStart,
      walkRunFrom: stored.walkRunFrom,
      lastWeekMinutes: stored.lastWeekMinutes,
      achievedShare: stored.achievedShare,
      easyPaceSecondsPerKm: measured.easyPaceSecondsPerKm,
      easyRunCount: measured.easyRunCount,
      intensity: measured.intensity,
    );

/// Güte der VO₂max für Pace-Vorgaben (PAR-081): der Langzeitwert
/// [longTerm] und der letzte verwertbare Laufwert [lastRun] (vom Tag
/// [lastRunDay]) sind beide mindestens „ausreichend“, und der Lauf ist
/// höchstens [IntensityParameters.vo2maxLastRunMaxDays] Tage alt.
/// „Vorläufig“ und „nicht bestimmbar“ sind unzureichend: `null`. Die Güte
/// (für die Bandbreite, PAR-082) ist die des Langzeitwerts.
Vo2maxGrade? vo2maxGradeFor({
  required ComputedValue? longTerm,
  required ComputedValue? lastRun,
  required DateTime? lastRunDay,
  required DateTime today,
  IntensityParameters parameters = const IntensityParameters(),
}) {
  bool usable(ComputedValue? v) =>
      v != null &&
      v.value != null &&
      (v.quality == ValueQuality.sufficient || v.quality == ValueQuality.good);
  if (!usable(longTerm) || !usable(lastRun) || lastRunDay == null) {
    return null;
  }
  final age = planDay(today).difference(planDay(lastRunDay)).inDays;
  if (age < 0 || age > parameters.vo2maxLastRunMaxDays) return null;
  return longTerm!.quality == ValueQuality.good
      ? Vo2maxGrade.good
      : Vo2maxGrade.sufficient;
}
