import '../../ports/storage_warning.dart';

/// Bestätigte Pausentage (PAR-202) aus der Antwort „ja“ auf die Pausenfrage:
/// die Tage ohne Einheit nach der letzten Einheit bis einschließlich dem Tag
/// der Antwort. Der Belastungsdienst zählt sie als bekannt leer (Last 0, auch
/// ohne Zusage „alles erfasst“); erwartete Einheiten fallen dort weg.
///
/// Keine Antwort, Antwort „nein“ oder keine frühere Einheit: keine Tage (der
/// Anfang der Pause ist dann unbekannt). Eine Einheit am Tag der Antwort ist
/// kein Pausentag. Tage sind Ortstage als UTC-Mitternacht.
Set<DateTime> confirmedPauseDays({
  required PauseAnswer? answer,
  required Iterable<DateTime> unitDays,
}) {
  if (answer == null || !answer.paused) return const {};
  DateTime? last;
  for (final d in unitDays) {
    final day = warningDay(d);
    if (day.isAfter(answer.on)) continue;
    if (last == null || day.isAfter(last)) last = day;
  }
  if (last == null) return const {};
  final days = <DateTime>{};
  for (
    var d = last.add(const Duration(days: 1));
    !d.isAfter(answer.on);
    d = d.add(const Duration(days: 1))
  ) {
    days.add(d);
  }
  return days;
}
