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

  test('localDayRanges: lokale Mitternacht, Länge folgt der Ortszeit', () {
    final r = localDayRanges(DateTime(2026, 3, 29, 12), 3);
    expect(r, hasLength(3));
    expect(r[0].end, r[1].start);
    expect(r[0].start, DateTime(2026, 3, 29).toUtc());
  });
}
