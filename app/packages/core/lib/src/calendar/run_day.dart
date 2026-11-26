/// Tag eines Laufs (PAR-237): die eine Rechnung für Tageswerte, Statistik,
/// Belastung, Plan, Verlauf, Kalender und Export. Eigenes Modul ohne
/// Abhängigkeit zu anderen Modulen, damit Plan, Vorverarbeitung und Statistik
/// es nutzen können, ohne einen Zyklus über die Neuberechnung zu bilden.
library;

import '../../ports/storage_runs.dart';

/// ISO-Datum (UTC) `JJJJ-MM-TT` eines Zeitpunkts.
String isoDay(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
}

/// Version der Tageszuordnung eines Laufs ([dayOfRun], PAR-237): Stufe
/// `day` der Kettenversion (`preprocessingChainVersion`). 1: Tag des
/// Laufendes; 2: Tag des Laufbeginns. Eine Erhöhung macht jeden Laufwert mit
/// älterer Kette veraltet, die Neuberechnung legt die Tageswerte dann an den
/// neuen Tag (ADR-0004, NFR-0005).
const int runDayMethodVersion = 2;

/// Ortstag des Laufbeginns als UTC-Mitternacht (PAR-237): Beginn plus der am
/// Lauf gespeicherte UTC-Versatz (Zeitzone des Laufs, nicht die des Geräts
/// jetzt; es gibt nur den Versatz zum Ende, er gilt auch für den Start). Fehlt
/// der Versatz (alter Lauf), gilt UTC, nie der Versatz des Geräts. Ein Lauf
/// über Mitternacht zählt für den Starttag. Die EINE Rechnung für [dayOfRun]
/// und die Zuordnung zu Plan-Einheiten (`planRunStartDay`, PAR-231).
DateTime runStartLocalDay(StoredRun run) {
  final local = runStartLocal(run);
  return DateTime.utc(local.year, local.month, local.day);
}

/// Beginn des Laufs in seiner Ortszeit (als UTC-Zeitpunkt mit den Ziffern der
/// Ortszeit), wie [runStartLocalDay]: Beginn plus der am Lauf gespeicherte
/// UTC-Versatz, ohne Versatz UTC.
DateTime runStartLocal(StoredRun run) =>
    run.startedAt.toUtc().add(run.endedUtcOffset ?? Duration.zero);

/// Tag eines Laufs (PAR-237), `JJJJ-MM-TT`: der Ortstag seines Beginns
/// ([runStartLocalDay]); fehlt der Versatz (alter Lauf, unbekannt), gilt der
/// UTC-Tag. Die EINE Stelle für Tageswerte, Statistik, Belastung, Readiness,
/// Prognose, Hinweise, Verlauf, Kalender und Export, für Speichern,
/// Neuberechnung und Löschen.
String dayOfRun(StoredRun run) => isoDay(runStartLocalDay(run));

/// Zeitraum für `finishedBetween` (Abfrage nach dem Laufende), der alle Läufe
/// findet, deren Tag ([dayOfRun]) in `firstDay <= Tag <= lastDay` liegt (Tage
/// als UTC-Mitternacht): vorn der größte UTC-Versatz ([maxRunEndUtcOffset]),
/// hinten zusätzlich der Folgetag, damit ein Lauf, der am letzten Tag startet
/// und am Folgetag endet, dabei ist (PAR-237). Läufe aus dem Puffer gehören
/// nicht dazu: der Aufrufer filtert danach mit [dayOfRun], so fällt auch ein
/// Lauf weg, der vor dem Zeitraum startet und darin endet.
({DateTime from, DateTime to}) runDayQueryBounds(
  DateTime firstDay,
  DateTime lastDay,
) => (
  from: firstDay.subtract(maxRunEndUtcOffset),
  to: lastDay.add(const Duration(days: 2) + maxRunEndUtcOffset),
);
