import 'package:core/core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 11, 9);

/// Lauf vor [daysAgo] Tagen mit sRPE 100 und TRIMP = 100 · [ratio].
FactorRun run(int daysAgo, double ratio, int rpe) => FactorRun(
  time: now.subtract(Duration(days: daysAgo)),
  trimp: 100 * ratio,
  srpePoints: 100,
  rpe: rpe,
);

/// [n] Läufe, RPE abwechselnd 3 und 7 (genug niedrige und hohe).
List<FactorRun> mix(int n, {double ratio = 1}) => [
  for (var i = 0; i < n; i++) run(i + 1, ratio, i.isEven ? 3 : 7),
];

void main() {
  test('PAR-086: 9 Läufe reichen nicht, 10 reichen', () {
    final few = computePersonalLoadFactor(mix(9), now: now);
    expect(few.available, isFalse);
    expect(few.unavailable, FactorUnavailableReason.tooFewRuns);
    final ok = computePersonalLoadFactor(mix(10), now: now);
    expect(ok.available, isTrue);
    expect(ok.value, 1);
    expect(ok.runCount, 10);
  });

  test('PAR-086: nur Läufe der letzten 180 Tage zählen', () {
    final runs = [...mix(9), run(181, 1, 5)];
    expect(
      computePersonalLoadFactor(runs, now: now).unavailable,
      FactorUnavailableReason.tooFewRuns,
    );
    final edge = [...mix(9), run(180, 1, 5)];
    expect(computePersonalLoadFactor(edge, now: now).available, isTrue);
  });

  test('PAR-086: mindestens 2 mit RPE >= 6 und 2 mit RPE <= 4', () {
    final noHigh = [for (var i = 0; i < 12; i++) run(i + 1, 1, i < 11 ? 5 : 6)];
    expect(
      computePersonalLoadFactor(noHigh, now: now).unavailable,
      FactorUnavailableReason.tooFewHighRpe,
    );
    final noLow = [
      run(1, 1, 7),
      run(2, 1, 7),
      run(3, 1, 4),
      for (var i = 4; i <= 12; i++) run(i, 1, 5),
    ];
    expect(
      computePersonalLoadFactor(noLow, now: now).unavailable,
      FactorUnavailableReason.tooFewLowRpe,
    );
    final edge = [
      run(1, 1, 6),
      run(2, 1, 6),
      run(3, 1, 4),
      run(4, 1, 4),
      for (var i = 5; i <= 12; i++) run(i, 1, 5),
    ];
    expect(computePersonalLoadFactor(edge, now: now).available, isTrue);
  });

  test('PAR-087: Median (nicht Mittel) über die letzten 20 Läufe', () {
    // 20 Läufe, Verhältnisse 1..20: Median 10,5; Mittel ebenfalls 10,5, daher
    // Ausreißer: 19 mal 1, einmal 1000 -> Median 1.
    final runs = [
      for (var i = 0; i < 20; i++)
        run(i + 1, i == 7 ? 1000 : 1, i.isEven ? 3 : 7),
    ];
    final f = computePersonalLoadFactor(runs, now: now);
    expect(f.value, 1);
    // Ungerade Anzahl: mittlerer Wert; gerade: Mittel der beiden mittleren.
    final odd = [
      for (var i = 0; i < 11; i++) run(i + 1, 1.0 + i, i.isEven ? 3 : 7),
    ];
    expect(computePersonalLoadFactor(odd, now: now).value, 6);
    final even = [
      for (var i = 0; i < 12; i++) run(i + 1, 1.0 + i, i.isEven ? 3 : 7),
    ];
    expect(computePersonalLoadFactor(even, now: now).value, 6.5);
  });

  test('PAR-087: nur die neuesten 20 gehen ein', () {
    final runs = [
      ...mix(20, ratio: 2),
      for (var i = 0; i < 30; i++) run(100 + i, 0.5, i.isEven ? 3 : 7),
    ];
    final f = computePersonalLoadFactor(runs, now: now);
    expect(f.value, 2);
    expect(f.runCount, 20);
  });

  test('PAR-087: unter 20 Läufen "noch wenig gesichert", ab 20 nicht', () {
    expect(computePersonalLoadFactor(mix(19), now: now).tentative, isTrue);
    expect(computePersonalLoadFactor(mix(20), now: now).tentative, isFalse);
    expect(computePersonalLoadFactor(mix(9), now: now).tentative, isFalse);
  });

  test('Läufe ohne rechenbares Verhältnis und künftige zählen nicht', () {
    final runs = [
      ...mix(9),
      FactorRun(
        time: DateTime.utc(2026, 11, 8),
        trimp: 50,
        srpePoints: 0,
        rpe: 0,
      ),
      FactorRun(
        time: now.add(const Duration(days: 1)),
        trimp: 100,
        srpePoints: 100,
        rpe: 5,
      ),
    ];
    expect(computePersonalLoadFactor(runs, now: now).available, isFalse);
  });

  test('Umrechnung sRPE -> TRIMP-Skala', () {
    final f = computePersonalLoadFactor(mix(10, ratio: 0.8), now: now);
    expect(f.convert(250), closeTo(200, 1e-9));
    expect(computePersonalLoadFactor(mix(3), now: now).convert(250), isNull);
  });

  group('Übernahmeregel ±25 %', () {
    test('ohne gespeicherten Faktor: übernehmen', () {
      expect(
        decideFactorAdoption(stored: null, fresh: 3),
        FactorDecision.adopt,
      );
    });
    test('innerhalb und genau auf der Grenze: übernehmen', () {
      expect(decideFactorAdoption(stored: 1, fresh: 1.2), FactorDecision.adopt);
      expect(
        decideFactorAdoption(stored: 1, fresh: 1.25),
        FactorDecision.adopt,
      );
      expect(
        decideFactorAdoption(stored: 1, fresh: 0.75),
        FactorDecision.adopt,
      );
    });
    test('darüber: Neuberechnung anbieten, in beide Richtungen', () {
      expect(
        decideFactorAdoption(stored: 1, fresh: 1.26),
        FactorDecision.offerRecalculation,
      );
      expect(
        decideFactorAdoption(stored: 1, fresh: 0.74),
        FactorDecision.offerRecalculation,
      );
    });
  });
}
