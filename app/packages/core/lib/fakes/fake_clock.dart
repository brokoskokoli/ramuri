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

  /// Lässt die Zeit bis [t] verstreichen (Wanduhr und monotone Uhr); [t] darf
  /// nicht vor der Wanduhr liegen.
  void advanceTo(DateTime t) {
    final d = t.toUtc().difference(_now);
    if (d.isNegative) {
      throw ArgumentError.value(t, 't', 'liegt in der Vergangenheit');
    }
    advance(d);
  }

  /// Stellt nur die Wanduhr (Umstellung, Netzzeit); die monotone Uhr bleibt.
  void set(DateTime t) => _now = t.toUtc();
}
