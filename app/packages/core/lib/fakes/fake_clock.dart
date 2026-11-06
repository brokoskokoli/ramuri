import '../ports/clock.dart';

/// Uhr, die nur auf Anweisung läuft.
class FakeClock implements Clock {
  FakeClock(DateTime start, {this.utcOffset = Duration.zero})
    : _now = start.toUtc();

  DateTime _now;
  Duration _mono = Duration.zero;

  /// Versatz, den [utcOffsetAt] liefert (jederzeit änderbar).
  Duration utcOffset;

  @override
  DateTime now() => _now;

  @override
  Duration utcOffsetAt(DateTime at) => utcOffset;

  /// Folgt nur [advance], nicht [set]: eine umgestellte Wanduhr ändert sie nicht.
  @override
  Duration monotonic() => _mono;

  void advance(Duration d) {
    _now = _now.add(d);
    _mono += d;
  }

  void set(DateTime t) => _now = t.toUtc();
}
