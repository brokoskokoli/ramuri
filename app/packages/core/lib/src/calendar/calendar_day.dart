/// Kalendertag eines Zeitpunkts: die eine Tagesrechnung für Prognose, Plan,
/// Ziele und Erinnerungen. Blattmodul ohne Abhängigkeit zu anderen Modulen.
library;

/// Kalendertag im lokalen Datum als UTC-Mitternacht: Tagesdifferenzen sind
/// damit frei von Sommerzeit.
DateTime calendarDay(DateTime t) {
  final l = t.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}

/// Ganze Kalendertage von [from] bis [to] (negativ, wenn [to] davor liegt).
int daysBetween(DateTime from, DateTime to) =>
    calendarDay(to).difference(calendarDay(from)).inDays;
