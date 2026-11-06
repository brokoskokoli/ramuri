/// Kennung und Version der Statistikrechnung (NFR-0001, NFR-0005).
const String statisticsMethod = 'statistics';
const int statisticsMethodVersion = 1;

/// Festlegungen der Statistik, die keine PAR-Grenzwerte sind: Sie stammen aus
/// OQ-0037 (Bestpace, Vergleich mit den letzten Läufen) beziehungsweise sind
/// Voreinstellungen aus Maintainer-Entscheidungen. Alles steht hier und nur
/// hier.
class StatisticsParameters {
  const StatisticsParameters({
    this.bestPaceDistanceMeters = 1000,
    this.comparisonRunCount = 5,
    this.minimumComparisonRuns = 1,
    this.firstDayOfWeek = DateTime.monday,
    this.sameToleranceSecondsPerKm = 1,
  }) : assert(bestPaceDistanceMeters > 0),
       assert(comparisonRunCount >= 1),
       assert(sameToleranceSecondsPerKm >= 0),
       assert(minimumComparisonRuns >= 1),
       assert(minimumComparisonRuns <= comparisonRunCount),
       assert(firstDayOfWeek >= DateTime.monday),
       assert(firstDayOfWeek <= DateTime.sunday);

  /// Länge des zusammenhängenden Abschnitts der Bestpace (OQ-0037: Kilometer).
  final double bestPaceDistanceMeters;

  /// Anzahl der vorherigen Läufe, mit deren Referenz verglichen wird (OQ-0037).
  final int comparisonRunCount;

  /// Mindestzahl vorheriger Läufe für eine Einordnung. Voreinstellung 1:
  /// Mit weniger als [comparisonRunCount] Vorläufen wird gegen die vorhandenen
  /// verglichen und deren Zahl mitgeliefert (vom Maintainer bestätigt; die
  /// Lücke in OQ-0037 ist damit geschlossen). Die Einstellung ist die eine
  /// Stelle zum Ändern.
  final int minimumComparisonRuns;

  /// Ein Unterschied der Pace unter diesem Wert (s/km, ausschließlich) gilt
  /// als „gleich“ (Maintainer 2026-11-06). Sonst gibt es nur den Unterschied.
  final double sameToleranceSecondsPerKm;

  /// Erster Tag der Kalenderwoche (`DateTime.monday` bis `sunday`). Die Spec
  /// nennt ihn nicht (FR-0044); Voreinstellung nach ISO 8601: Montag.
  final int firstDayOfWeek;
}
