import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/system_clock.dart';

/// Zeitpunkte (UTC), an denen sich der Versatz der Zeitzone des Prozesses in
/// [year] ändert (stündlich gesucht, dann auf die Sekunde eingegrenzt).
List<DateTime> _transitions(int year) {
  final out = <DateTime>[];
  Duration off(DateTime t) => t.toLocal().timeZoneOffset;
  var t = DateTime.utc(year);
  while (t.year == year) {
    final n = t.add(const Duration(hours: 1));
    if (off(n) != off(t)) {
      var lo = t, hi = n; // off(lo) != off(hi)
      while (hi.difference(lo) > const Duration(seconds: 1)) {
        final mid = lo.add(hi.difference(lo) ~/ 2);
        if (off(mid) == off(lo)) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      out.add(hi);
    }
    t = n;
  }
  return out;
}

void main() {
  // Läuft in jeder Zeitzone; das Gate führt die Datei zusätzlich unter
  // America/Los_Angeles, Pacific/Auckland und UTC aus.
  final clock = SystemClock();
  final winter = DateTime.utc(2026, 1, 15, 12).toLocal().timeZoneOffset;
  final summer = DateTime.utc(2026, 7, 15, 12).toLocal().timeZoneOffset;
  final changes = _transitions(2026);

  test('utcOffsetAt: Versatz des fraglichen Zeitpunkts, ganze Sekunden', () {
    for (final at in [
      DateTime.utc(2026, 1, 15, 12),
      DateTime.utc(2026, 7, 15, 12),
      DateTime(2026, 1, 15, 12), // Ortszeit statt UTC
      for (final c in changes) ...[c.subtract(const Duration(seconds: 1)), c],
    ]) {
      final offset = clock.utcOffsetAt(at);
      expect(offset, at.toLocal().timeZoneOffset, reason: '$at');
      expect(offset.inMicroseconds % Duration.microsecondsPerSecond, 0);
    }
  });

  test('utcOffsetAt: Zeitumstellung der Zone (oder keine) erkannt', () {
    if (winter == summer) {
      // Zone ohne Sommerzeit (z. B. UTC): der Versatz ist überall gleich.
      expect(changes, isEmpty);
      for (var m = 1; m <= 12; m++) {
        expect(clock.utcOffsetAt(DateTime.utc(2026, m, 1)), winter);
      }
      return;
    }
    // Mit Sommerzeit: zwei Wechsel im Jahr, an jedem springt der Versatz, und
    // der aktuelle Versatz wäre für eine Seite falsch.
    expect(changes, hasLength(2));
    for (final c in changes) {
      final before = clock.utcOffsetAt(c.subtract(const Duration(seconds: 1)));
      final after = clock.utcOffsetAt(c);
      expect(before, isNot(after), reason: '$c');
      expect({before, after}, {winter, summer}, reason: '$c');
    }
  });
}
