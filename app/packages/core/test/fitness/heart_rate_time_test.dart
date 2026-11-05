import 'package:core/core.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 1, 1, 10);
DateTime at(int s) => t0.add(Duration(seconds: s));
TimeSpan span(int a, int b) => TimeSpan(start: at(a), end: at(b));
RawHeartRate hr(int s, int bpm) =>
    RawHeartRate(time: at(s), source: 'x', bpm: bpm);
HeartRateGap gap(int a, int b) =>
    HeartRateGap(start: at(a), end: at(b), open: false);
const sec = 1000000;

HeartRateTime run(
  List<TimeSpan> m,
  List<RawHeartRate> h, [
  List<HeartRateGap> g = const [],
]) => heartRateTimeByBpm(movingIntervals: m, acceptedValues: h, gaps: g);

void main() {
  test('Halten: letzter Wert gilt, vor dem ersten gilt der erste', () {
    final v = run([span(0, 30)], [hr(10, 100), hr(20, 120)]);
    expect(v.microsByBpm, {100: 20 * sec, 120: 10 * sec});
    expect(v.coveredMicros, 30 * sec);
    expect(v.movingMicros, 30 * sec);
  });

  test('Summe je Puls ist die abgedeckte Zeit; Ausgabe aufsteigend', () {
    final v = run([span(0, 7)], [hr(0, 150), hr(3, 90)]);
    expect(v.microsByBpm.keys.toList(), [90, 150]);
    expect(v.microsByBpm.values.fold<int>(0, (a, b) => a + b), v.coveredMicros);
  });

  test('Lücke wird abgezogen, auch über Intervallgrenzen', () {
    final v = run([span(0, 10), span(20, 40)], [hr(0, 100)], [gap(5, 25)]);
    expect(v.movingMicros, 30 * sec);
    expect(v.coveredMicros, 5 * sec + 15 * sec);
    expect(v.microsByBpm, {100: 20 * sec});
  });

  test('Lücke deckt ein ganzes Intervall und ragt über den Rand', () {
    final v = run([span(10, 20), span(30, 40)], [hr(0, 100)], [
      gap(0, 25),
      gap(35, 100),
    ]);
    expect(v.coveredMicros, 5 * sec);
    expect(v.microsByBpm, {100: 5 * sec});
  });

  test('Überschneidende Intervalle und Lücken zählen einmal', () {
    final v = run([span(0, 20), span(10, 30)], [hr(0, 100)], [
      gap(5, 15),
      gap(10, 12),
    ]);
    expect(v.movingMicros, 30 * sec);
    expect(v.coveredMicros, 20 * sec);
  });

  test('Reihenfolge der Eingaben ist egal; gleiche Zeit: später gewinnt', () {
    final a = run([span(30, 40), span(0, 10)], [hr(20, 120), hr(0, 100)]);
    expect(a.microsByBpm, {100: 10 * sec, 120: 10 * sec});
    final b = run([span(0, 10)], [hr(5, 100), hr(5, 130)]);
    expect(b.microsByBpm, {130: 10 * sec});
  });

  test('mehrere Werte im selben Intervall mit gleicher Zeit', () {
    final v = run([span(0, 10)], [hr(2, 100), hr(2, 110), hr(2, 120)]);
    expect(v.microsByBpm, {120: 10 * sec});
  });

  test('Wert beginnt erst nach der Pause: Halten über die Pause', () {
    final v = run([span(0, 10), span(50, 60)], [hr(0, 100), hr(30, 140)]);
    expect(v.microsByBpm, {100: 10 * sec, 140: 10 * sec});
  });

  test('ohne Puls nichts abgedeckt, Bewegungszeit bleibt', () {
    final v = run([span(0, 10)], []);
    expect(v.coveredMicros, 0);
    expect(v.movingMicros, 10 * sec);
    expect(v.microsByBpm, isEmpty);
  });

  test('keine Bewegungszeit, leere und negative Intervalle', () {
    final v = run([span(5, 5), span(9, 3)], [hr(0, 100)]);
    expect(v.movingMicros, 0);
    expect(v.coveredMicros, 0);
  });

  test('Mikrosekunden bleiben exakt (keine Rundung)', () {
    final v = heartRateTimeByBpm(
      movingIntervals: [
        TimeSpan(start: t0, end: t0.add(const Duration(microseconds: 3))),
      ],
      acceptedValues: [
        RawHeartRate(time: t0, source: 'x', bpm: 100),
        RawHeartRate(
          time: t0.add(const Duration(microseconds: 1)),
          source: 'x',
          bpm: 110,
        ),
      ],
      gaps: const [],
    );
    expect(v.microsByBpm, {100: 1, 110: 2});
  });
}
