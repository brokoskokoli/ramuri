/// Port: Uhr. Fachlogik fragt die Zeit nur hier ab, nie über `DateTime.now()`.
abstract interface class Clock {
  /// Aktuelle Zeit (UTC).
  DateTime now();

  /// Monotone Zeit seit einem beliebigen, festen Nullpunkt. Läuft nur vorwärts
  /// und folgt keiner Umstellung der Wanduhr; nur für Abstände gedacht (z. B.
  /// Verfall einer Anzeige), nie als Zeitpunkt.
  Duration monotonic();

  /// Lokaler Versatz zu UTC (Zeitzone samt Sommerzeit) am Zeitpunkt [at], in
  /// ganzen Sekunden. Nötig für den lokalen Kalendertag eines Laufendes.
  Duration utcOffsetAt(DateTime at);
}
