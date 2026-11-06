/// Port: Uhr. Fachlogik fragt die Zeit nur hier ab, nie über `DateTime.now()`.
abstract interface class Clock {
  /// Aktuelle Zeit (UTC).
  DateTime now();

  /// Lokaler Versatz zu UTC (Zeitzone samt Sommerzeit) am Zeitpunkt [at], in
  /// ganzen Sekunden. Nötig für den lokalen Kalendertag eines Laufendes.
  Duration utcOffsetAt(DateTime at);
}
