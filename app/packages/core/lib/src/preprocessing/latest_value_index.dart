import 'measurement.dart';

/// Ergebnis einer Zuordnung über Zeitstempel (FR-0046).
class Lookup<T> {
  const Lookup.present(T this.value, Duration this.age)
    : state = MeasurementState.present;
  const Lookup.unavailable({this.age})
    : state = MeasurementState.unavailable,
      value = null;

  final MeasurementState state;
  final T? value;

  /// Alter des Werts zum Abfragezeitpunkt; `null`, wenn es keinen Wert gibt.
  /// Bei zu altem Wert bleibt das Alter gesetzt.
  final Duration? age;
}

/// Zeitgeordnete Werte eines Kanals; liefert den letzten Wert `<= t`.
class LatestValueIndex<T> {
  final List<DateTime> _times = [];
  final List<T> _values = [];

  int get length => _times.length;

  /// Zeiten müssen streng aufsteigend sein (das sichern die Filter zu).
  void add(DateTime time, T value) {
    if (_times.isNotEmpty && !time.isAfter(_times.last)) {
      throw ArgumentError.value(time, 'time', 'nicht aufsteigend');
    }
    _times.add(time);
    _values.add(value);
  }

  /// Letzter Wert mit Zeit `<= t`. Ist er älter als [maxAge] (strikt), gilt
  /// er als nicht verfügbar. Ohne [maxAge] gibt es keine Grenze.
  Lookup<T> valueAt(DateTime t, {Duration? maxAge}) {
    var lo = 0;
    var hi = _times.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_times[mid].isAfter(t)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    if (lo == 0) return const Lookup.unavailable();
    final age = t.difference(_times[lo - 1]);
    if (maxAge != null && age > maxAge) return Lookup.unavailable(age: age);
    return Lookup.present(_values[lo - 1], age);
  }
}
