/// Port: Uhr. Fachlogik fragt die Zeit nur hier ab, nie über `DateTime.now()`.
abstract interface class Clock {
  /// Aktuelle Zeit (UTC).
  DateTime now();
}
