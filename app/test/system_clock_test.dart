import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/system_clock.dart';

void main() {
  test('utcOffsetAt: Versatz des fraglichen Zeitpunkts, ganze Sekunden', () {
    final clock = SystemClock();
    final winter = DateTime.utc(2026, 1, 15, 12).toLocal().timeZoneOffset;
    final summer = DateTime.utc(2026, 7, 15, 12).toLocal().timeZoneOffset;
    if (winter == summer) {
      markTestSkipped(
        'Zeitzone ohne Sommerzeit (z. B. UTC): Der Test prüft nichts. '
        'Mit TZ=Europe/Berlin ausführen.',
      );
      return;
    }
    // Winter und Sommer: bei Zeitzonen mit Sommerzeit unterscheiden sich die
    // Versätze, der aktuelle Versatz wäre für einen der beiden falsch.
    for (final at in [
      DateTime.utc(2026, 1, 15, 12),
      DateTime.utc(2026, 7, 15, 12),
      DateTime.utc(2026, 3, 29, 0, 59, 59),
      DateTime.utc(2026, 3, 29, 1),
    ]) {
      final offset = clock.utcOffsetAt(at);
      expect(offset, at.toLocal().timeZoneOffset, reason: '$at');
      expect(offset.inMicroseconds % Duration.microsecondsPerSecond, 0);
    }
  });
}
