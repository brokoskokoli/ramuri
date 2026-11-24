import '../fitness/heart_rate_basis.dart';
import '../statistics/run_figures.dart';
import 'build_plan_inputs.dart' show isEasyRun;
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'target_intensity.dart';
import 'weekly_time.dart' show planDay;

/// Warum eine andere Sportart (FR-0221) eine Einheit nicht ersetzen darf
/// (PAR-233). Die Reihenfolge ist die der Prüfung: Der erste zutreffende
/// Grund wird genannt.
enum SportReplacementBlock {
  /// Keine offene lockere Einheit (Art `easy`) an dem Tag.
  noEasyUnit,

  /// In der Planwoche (Montag bis Sonntag) hat schon eine andere Sportart
  /// eine Einheit ersetzt.
  alreadyReplaced,

  /// Nach dem Puls nicht locker: Durchschnittspuls nicht unter der Grenze
  /// aus PAR-111, ohne Durchschnittspuls oder Pulsbasis nicht bestimmbar,
  /// oder nach PAR-058 intensiv.
  tooIntensive,

  /// Bewegungszeit unter zwei Dritteln der geplanten Dauer.
  tooShort,
}

/// Prüft den Ersatz einer lockeren Einheit durch eine andere Sportart
/// (PAR-233, FR-0222); `null` heißt: erlaubt.
///
/// - [unit]: die offene Einheit, die abgehakt werden soll (`null`: keine).
///   Nur die Art `easy` lässt sich ersetzen, nie `long`, harte Formen,
///   Geh-Lauf oder Ruhetag.
/// - [sport]: Kennzahlen der Sporteinheit; Durchschnittspuls und
///   Bewegungszeit (PAR-232) beziehen sich auf die Bewegungszeit.
/// - [rpe], [highHrMinutes]: für PAR-058 (RPE ≥ 7 oder mindestens 10 min
///   ab 80 % HFmax heißt intensiv).
/// - [units]: alle Einheiten des Plans; [sportRunIds]: Kennungen aller
///   Sporteinheiten. Eine Einheit derselben Planwoche mit einer
///   Sporteinheit (außer [sport] selbst) zählt als schon ersetzt.
/// - [heartRate], [zoneBounds]: Profil für die Grenze aus PAR-111.
///
/// Reine Funktion ohne Speicherzugriff.
SportReplacementBlock? planSportReplacementBlock({
  required PlanUnit? unit,
  required RunFigures sport,
  required Iterable<PlanUnit> units,
  required Set<int> sportRunIds,
  int? rpe,
  double? highHrMinutes,
  HeartRateBasis? heartRate,
  List<double>? zoneBounds,
  PlanParameters parameters = const PlanParameters(),
  IntensityParameters intensityParameters = const IntensityParameters(),
}) {
  if (unit == null || unit.kind != PlanUnitKind.easy) {
    return SportReplacementBlock.noEasyUnit;
  }
  final day = planDay(unit.day);
  final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
  final sunday = monday.add(const Duration(days: 6));
  var replaced = 0;
  for (final u in units) {
    final id = u.runId;
    if (id == null || id == sport.runId || !sportRunIds.contains(id)) {
      continue;
    }
    if (unit.id != null && u.id == unit.id) continue;
    final d = planDay(u.day);
    if (d.isBefore(monday) || d.isAfter(sunday)) continue;
    replaced++;
  }
  if (replaced >= parameters.replaceMaxPerWeek) {
    return SportReplacementBlock.alreadyReplaced;
  }
  // Locker nur nach dem Puls (PAR-111): ohne Zuordnung und ohne RPE-Weg.
  final easyByHr = isEasyRun(
    sport,
    heartRate,
    IntensityInputs(zoneBounds: zoneBounds).zoneBounds,
    intensity: intensityParameters,
  );
  if (!easyByHr ||
      parameters.completedIntensive(rpe: rpe, highHrMinutes: highHrMinutes)) {
    return SportReplacementBlock.tooIntensive;
  }
  final moving = sport.movingTime ?? sport.totalTime ?? Duration.zero;
  final planned = Duration(minutes: unit.minutes);
  if (moving.inMicroseconds <
      planned.inMicroseconds * parameters.replaceMinShare) {
    return SportReplacementBlock.tooShort;
  }
  return null;
}
