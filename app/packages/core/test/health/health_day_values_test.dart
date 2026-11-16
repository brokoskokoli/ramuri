import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const p = HealthProcessing();
  final day = DateTime.utc(2026, 11, 10);
  final days = [
    DayRange(day, day.add(const Duration(days: 1))),
    DayRange(
      day.add(const Duration(days: 1)),
      day.add(const Duration(days: 2)),
    ),
  ];

  HealthSample s(String o, DateTime t, double v) =>
      HealthSample(time: t, value: v, origin: o);

  test('Ruhepuls: Tage ohne gültigen Wert fehlen, Quelle nach Tagen', () {
    final samples = [
      s('a', day.add(const Duration(hours: 8)), 55),
      s('a', day.add(const Duration(days: 1, hours: 8)), 56),
      s('b', day.add(const Duration(hours: 9)), 50),
      s('b', day.add(const Duration(hours: 10)), 51),
      s('b', day.add(const Duration(hours: 11)), 52),
      s('b', day.add(const Duration(days: 1, hours: 9)), 500), // ungültig
    ];
    final list = restingHeartRateDayList(p, samples, days);
    expect(list, hasLength(2));
    expect(list[1].keys, ['a']);
    // a hat 2 Tage, b nur 1 (trotz mehr Einzelwerten).
    expect(p.selectSource(list), 'a');
  });

  test('HRV: je Tag die Hauptschlafphase; Tag ohne Schlaf fehlt', () {
    final sleep = SleepSession(
      origin: 'a',
      start: day.add(const Duration(hours: -1)),
      end: day.add(const Duration(hours: 7)),
    );
    final samples = [
      s('a', day.add(const Duration(hours: 3)), 40),
      s('a', day.add(const Duration(days: 1, hours: 3)), 45), // kein Schlaf
    ];
    final list = hrvDayList(p, samples, [sleep], days);
    expect(list, hasLength(1));
    expect(list.single['a']!.value, 40);
    expect(p.selectSource(list), 'a');
  });

  test(
    'HRV: Sitzung, die spät am Tag endet, zählt für diesen Tag (PAR-164)',
    () {
      // Ende 20:00, also mehr als 16 h nach Tagesbeginn: gilt bis Mitternacht.
      final late = SleepSession(
        origin: 'a',
        start: day.add(const Duration(hours: 12)),
        end: day.add(const Duration(hours: 20)),
      );
      final samples = [s('a', day.add(const Duration(hours: 15)), 42)];
      final v = hrvDayValues(p, samples, [late], days);
      expect(v, hasLength(2));
      expect(v[0]['a']!.value, 42);
      expect(v[0]['a']!.method.methodVersion, 2);
      // Am Folgetag zählt sie nicht.
      expect(v[1], isEmpty);
    },
  );

  test('HRV: Sommerzeit, Tag mit 23 h, Grenze ist die lokale Mitternacht', () {
    // Europa/Berlin 29.03.2026: Tag von 28.03. 23:00 bis 29.03. 22:00 UTC.
    final dst = [
      DayRange(DateTime.utc(2026, 3, 27, 23), DateTime.utc(2026, 3, 28, 23)),
      DayRange(DateTime.utc(2026, 3, 28, 23), DateTime.utc(2026, 3, 29, 22)),
    ];
    // Endet 23:30 UTC = 00:30 Ortszeit am 29.03.
    final night = SleepSession(
      origin: 'a',
      start: DateTime.utc(2026, 3, 28, 17),
      end: DateTime.utc(2026, 3, 28, 23, 30),
    );
    final samples = [s('a', DateTime.utc(2026, 3, 28, 20), 50)];
    final v = hrvDayValues(p, samples, [night], dst);
    expect(v[0], isEmpty);
    expect(v[1]['a']!.value, 50);
  });

  test(
    'localDayStart: lokale Mitternacht des Ortstags, wie localDayRanges',
    () {
      final at = DateTime(2026, 3, 29, 23, 59);
      expect(localDayStart(at), DateTime(2026, 3, 29).toUtc());
      expect(localDayStart(at), localDayRanges(at, 1).single.start);
      expect(localDayStart(at.toUtc()), DateTime(2026, 3, 29).toUtc());
      expect(localDayStart(at).toLocal().hour, 0);
    },
  );

  test('localDayRanges: lokale Mitternacht, Länge folgt der Ortszeit', () {
    final r = localDayRanges(DateTime(2026, 3, 29, 12), 3);
    expect(r, hasLength(3));
    expect(r[0].end, r[1].start);
    expect(r[0].start, DateTime(2026, 3, 29).toUtc());
  });
}
