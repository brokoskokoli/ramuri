import '../ports/clock.dart';

/// Uhr, die nur auf Anweisung läuft.
class FakeClock implements Clock {
  FakeClock(DateTime start) : _now = start.toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);

  void set(DateTime t) => _now = t.toUtc();
}
