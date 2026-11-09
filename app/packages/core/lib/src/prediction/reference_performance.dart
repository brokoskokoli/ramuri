import 'prediction_parameters.dart';

/// Art der Referenzleistung (FR-0129, OQ-0034).
enum ReferenceKind {
  /// Eingetragene Wettkampfzeit.
  race,

  /// Eingetragene Testzeit.
  test,

  /// Bestätigter schneller Lauf (FR-0131, PAR-185).
  confirmedRun,
}

/// Warum eine Referenz nicht gültig ist.
enum ReferenceProblem { distanceTooShort, nonPositiveTime, dateInFuture }

/// Referenzleistung: Distanz, Zeit, Datum (FR-0129).
///
/// Ein bestätigter Lauf trägt die Lauf-ID; mit dem Lauf verschwindet auch die
/// Referenz (Speicherung gehört zu Teil B, nicht in `core`).
class ReferencePerformance {
  const ReferencePerformance({
    required this.kind,
    required this.distanceMeters,
    required this.seconds,
    required this.date,
    required this.createdAt,
    this.runId,
  });

  final ReferenceKind kind;
  final double distanceMeters;
  final double seconds;

  /// Datum der Leistung (lokaler Kalendertag).
  final DateTime date;

  /// Zeitpunkt des Anlegens; bei gleichem Datum gewinnt der spätere.
  final DateTime createdAt;

  /// Lauf-ID bei [ReferenceKind.confirmedRun].
  final String? runId;

  /// Erstes Problem nach FR-0129 und Festlegung WP20 oder `null`.
  ReferenceProblem? validate(DateTime now, [PredictionParameters? p]) {
    final params = p ?? const PredictionParameters();
    if (!(distanceMeters >= params.minimumReferenceMeters) ||
        !distanceMeters.isFinite) {
      return ReferenceProblem.distanceTooShort;
    }
    if (!(seconds > 0) || !seconds.isFinite) {
      return ReferenceProblem.nonPositiveTime;
    }
    if (calendarDay(date).isAfter(calendarDay(now))) {
      return ReferenceProblem.dateInFuture;
    }
    return null;
  }
}

/// Die geltende Referenz: die jüngste nach Datum, bei gleichem Datum die
/// zuletzt angelegte (Annahme WP20). `null` ohne Referenzen.
ReferencePerformance? activeReference(Iterable<ReferencePerformance> all) {
  ReferencePerformance? best;
  for (final r in all) {
    if (best == null) {
      best = r;
      continue;
    }
    final c = calendarDay(r.date).compareTo(calendarDay(best.date));
    if (c > 0 || (c == 0 && r.createdAt.isAfter(best.createdAt))) best = r;
  }
  return best;
}

/// Kalendertag im lokalen Datum als UTC-Mitternacht: Tagesdifferenzen sind
/// damit frei von Sommerzeit.
DateTime calendarDay(DateTime t) {
  final l = t.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}

/// Ganze Kalendertage von [from] bis [to] (negativ, wenn [to] davor liegt).
int daysBetween(DateTime from, DateTime to) =>
    calendarDay(to).difference(calendarDay(from)).inDays;
