import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'readiness_c2_helpers.dart';

List<(ReadinessFactorId, ReadinessDirection)> drv(ReadinessResult r) => [
  for (final d in r.explanation.drivers) (d.id, d.direction),
];

const hrv = ReadinessFactorId.hrv;
const rhr = ReadinessFactorId.restingHeartRate;
const slp = ReadinessFactorId.sleep;
const load = ReadinessFactorId.load;
const lo = ReadinessDirection.lower;
const hi = ReadinessDirection.higher;

void main() {
  group('Erklärung aus den Rechenbeispielen (Abschnitt 5, PAR-172)', () {
    void ex(
      String name,
      ReadinessInputs i,
      List<(ReadinessFactorId, ReadinessDirection)> drivers,
      ReadinessExplanationCode code,
    ) {
      test(name, () {
        final r = computeReadiness(i);
        expect(r.explanation.code, code);
        expect(drv(r), drivers);
      });
    }

    ex(
      'Alles unauffällig: kein Faktor weicht ab',
      inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: -5, wellbeing: 3),
      [],
      ReadinessExplanationCode.noDeviation,
    );
    ex(
      'Überall günstig: HRV und Ruhepuls höher, TSB nie genannt',
      inputs(hrvZ: 1, rhrZ: 1, hours: 8, eff: 90, tsb: -5, wellbeing: 4),
      [(hrv, hi), (rhr, hi)],
      ReadinessExplanationCode.drivers,
    );
    ex(
      'Nur HRV fällt',
      inputs(hrvZ: -2, rhrZ: 0, hours: 7, tsb: -5, wellbeing: 3),
      [(hrv, lo)],
      ReadinessExplanationCode.drivers,
    );
    ex(
      'Nur wenig Schlaf: Grund Schlafdauer',
      inputs(hrvZ: 0, rhrZ: 0, hours: 5, tsb: -5, wellbeing: 3),
      [(slp, lo)],
      ReadinessExplanationCode.onlySleepBelow,
    );
    ex(
      'Nur hohe Belastung: TSB als Grund für niedriger',
      inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: -30, wellbeing: 3),
      [(load, lo)],
      ReadinessExplanationCode.drivers,
    );
    ex(
      'Mehrere mäßig: Schlaf und HRV, nicht Ruhepuls und TSB',
      inputs(hrvZ: -1, rhrZ: -1, hours: 6, tsb: -20, wellbeing: 3),
      [(slp, lo), (hrv, lo)],
      ReadinessExplanationCode.drivers,
    );
    ex(
      'Mehrere stark: Schlaf und HRV',
      inputs(hrvZ: -2, rhrZ: -2, hours: 5, tsb: -35, wellbeing: 2),
      [(slp, lo), (hrv, lo)],
      ReadinessExplanationCode.drivers,
    );
    ex(
      'Nur HRV und Schlaf: nichts auffällig',
      inputs(hrvZ: 0, hours: 7),
      [],
      ReadinessExplanationCode.noDeviation,
    );

    test('Schlafgrund folgt aus der Dauer', () {
      final short = computeReadiness(
        inputs(hrvZ: 0, rhrZ: 0, hours: 5, tsb: -5),
      );
      expect(
        short.explanation.drivers.single.sleepCause,
        ReadinessSleepCause.shortDuration,
      );
      // 8 h bei Effizienz 60 %: Dauer ist günstig, nur die Effizienz drückt.
      final eff = computeReadiness(
        inputs(hrvZ: 0, rhrZ: 0, hours: 8, eff: 60, tsb: -5),
      );
      expect(eff.explanation.code, ReadinessExplanationCode.onlySleepBelow);
      expect(
        eff.explanation.drivers.single.sleepCause,
        ReadinessSleepCause.lowEfficiency,
      );
      // Selbstangabe unter 5 h: kurze Dauer.
      final band = computeReadiness(
        inputs(hrvZ: 0, rhrZ: 0, band: SleepBand.under5, tsb: -5),
      );
      expect(
        band.explanation.drivers.single.sleepCause,
        ReadinessSleepCause.shortDuration,
      );
      expect(
        band.explanation.drivers.single.source,
        ReadinessFactorSource.selfReport,
      );
    });
  });

  group('Sonderfälle PAR-172', () {
    test(
      'nur Schlaf unter Bezug: Schlaf wird auch gegen größere höhere genannt',
      () {
        // HRV 750, Ruhepuls 600 höher, Schlaf 6,9 h nur −75.
        final r = computeReadiness(
          inputs(hrvZ: 1.5, rhrZ: 1.5, hours: 6.9, tsb: -5),
        );
        expect(r.explanation.code, ReadinessExplanationCode.onlySleepBelow);
        expect(drv(r), [(hrv, hi), (slp, lo)]);
      },
    );
    test('Gleichstand: Reihenfolge der Faktoren', () {
      final r = computeReadiness(
        inputs(hrvZ: -1, rhrZ: -1.25, hours: 7, tsb: -5),
      );
      final impacts = [for (final d in r.explanation.drivers) d.impact];
      expect(impacts, [-625, -625]);
      expect(drv(r), [(hrv, lo), (rhr, lo)]);
    });
    test('Schlaf bei 7 h ist nie günstig (Bezug 70)', () {
      final r = computeReadiness(inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: -5));
      expect(r.explanation.drivers, isEmpty);
      final r8 = computeReadiness(inputs(hrvZ: 0, rhrZ: 0, hours: 8, tsb: -5));
      expect(drv(r8), [(slp, hi)]);
    });
    test('Quelle je Faktor', () {
      final r = computeReadiness(
        inputs(hrvZ: -2, rhrZ: 0, hours: 5, tsb: -30, wellbeing: 1),
      );
      final by = {for (final d in r.explanation.drivers) d.id: d.source};
      expect(by[slp], ReadinessFactorSource.healthConnect);
      expect(by[hrv], ReadinessFactorSource.healthConnect);
      final t = computeReadiness(inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: -40));
      expect(
        t.explanation.drivers.single.source,
        ReadinessFactorSource.trainingLoad,
      );
      final w = computeReadiness(
        inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: -5, wellbeing: 1),
      );
      expect(
        w.explanation.drivers.single.source,
        ReadinessFactorSource.runRating,
      );
    });
  });

  group('Fehlende Faktoren und Gewichte (PAR-170)', () {
    test('Nur HRV und Schlaf: Gewichte benannt, Kappung', () {
      final r = computeReadiness(inputs(hrvZ: 0, hours: 7));
      final e = r.explanation;
      expect(
        [for (final u in e.used) (u.id, u.weight)],
        [(hrv, 25.0), (slp, 30.0)],
      );
      expect(
        [for (final m in e.missing) (m.id, m.weight)],
        [(rhr, 20.0), (load, 15.0), (ReadinessFactorId.wellbeing, 10.0)],
      );
      expect(e.cappedWithoutLoad, isFalse);
    });
    test('Kappung auf 74 wird genannt', () {
      final r = computeReadiness(
        inputs(hrvZ: 3, rhrZ: 3, hours: 9, wellbeing: 5),
      );
      expect(r.capped, isTrue);
      expect(r.explanation.cappedWithoutLoad, isTrue);
      final full = computeReadiness(
        inputs(hrvZ: 3, rhrZ: 3, hours: 9, tsb: 0, wellbeing: 5),
      );
      expect(full.explanation.cappedWithoutLoad, isFalse);
    });
    test('Ohne Zahl: noNumber, keine Faktoren genannt', () {
      final r = computeReadiness(inputs(rhrZ: -2, hours: 4));
      expect(r.state, ReadinessState.limited);
      expect(r.explanation.code, ReadinessExplanationCode.noNumber);
      expect(r.explanation.drivers, isEmpty);
      expect(r.explanation.missing.map((m) => m.id), contains(hrv));
    });
  });

  group('Eigenschaften (Zufallsdaten)', () {
    test('Erklärung folgt aus den Faktoren, TSB nie als Grund für hoch', () {
      var loadNamed = 0, higher = 0;
      for (var seed = 0; seed < 500; seed++) {
        final rnd = Random(seed);
        final r = computeReadiness(
          inputs(
            hrvZ: rnd.nextDouble() * 8 - 4,
            rhrZ: rnd.nextBool() ? rnd.nextDouble() * 8 - 4 : null,
            hours: 3 + rnd.nextDouble() * 8,
            eff: rnd.nextBool() ? 60 + rnd.nextDouble() * 40 : null,
            tsb: rnd.nextBool() ? rnd.nextDouble() * 80 - 60 : null,
            wellbeing: rnd.nextBool() ? 1 + rnd.nextInt(5) : null,
          ),
        );
        final e = r.explanation;
        expect(e.drivers.length, lessThanOrEqualTo(2), reason: 'seed $seed');
        final byId = {for (final f in r.factors) f.id: f};
        double impactOf(ReadinessFactorValue f) =>
            f.weight * (f.score - (f.id == slp ? 70 : 60));
        for (final d in e.drivers) {
          final f = byId[d.id];
          expect(f, isNotNull, reason: 'seed $seed');
          expect(d.source, f!.source);
          expect(d.impact, impactOf(f));
          expect(d.direction, d.impact < 0 ? lo : hi);
          if (d.id == load) {
            loadNamed++;
            expect(d.direction, lo, reason: 'seed $seed');
          } else if (d.direction == hi) {
            higher++;
          }
        }
        // Größte Beträge: kein nicht genannter Faktor ist größer als der
        // kleinste genannte (außer Sonderfall nur Schlaf unter Bezug).
        if (e.code == ReadinessExplanationCode.drivers &&
            e.drivers.length == 2) {
          final named = e.drivers.map((d) => d.id).toSet();
          final minNamed = e.drivers.map((d) => d.impact.abs()).reduce(min);
          for (final f in r.factors) {
            if (named.contains(f.id)) continue;
            if (f.id == load && impactOf(f) > 0) continue;
            expect(
              impactOf(f).abs(),
              lessThanOrEqualTo(minNamed),
              reason: 'seed $seed',
            );
          }
        }
        // Belegt: genannte plus ungenannte = eingegangene; fehlend = Rest.
        expect({
          ...e.used.map((u) => u.id),
          ...e.missing.map((m) => m.id),
        }, ReadinessFactorId.values.toSet());
        expect(e.used.length + e.missing.length, 5);
        for (final u in e.used) {
          expect(u.weight, byId[u.id]!.weight);
        }
        if (e.code == ReadinessExplanationCode.onlySleepBelow) {
          expect(r.factors.where((f) => impactOf(f) < 0).map((f) => f.id), [
            slp,
          ]);
          expect(e.drivers.any((d) => d.id == slp), isTrue);
        }
      }
      expect(loadNamed, greaterThan(20));
      expect(higher, greaterThan(50));
    });
    test('TSB über 0 erscheint nie, auch nicht höher', () {
      for (final t in [-10.0, -9.9, 0.0, 30.0, 100.0]) {
        final r = computeReadiness(
          inputs(hrvZ: 0, rhrZ: 0, hours: 7, tsb: t, wellbeing: 3),
        );
        expect(r.explanation.drivers.where((d) => d.id == load), isEmpty);
      }
    });
    test('Schutz: Belastung über dem Bezug wird nie genannt', () {
      // Nicht über das Modell erreichbar (PAR-168 kappt bei 60); direkt geprüft.
      final e = explainReadinessFactors(
        factors: const [
          ReadinessFactorValue(
            id: ReadinessFactorId.load,
            source: ReadinessFactorSource.trainingLoad,
            weight: 15,
            score: 80,
          ),
          ReadinessFactorValue(
            id: ReadinessFactorId.hrv,
            source: ReadinessFactorSource.healthConnect,
            weight: 25,
            score: 61,
          ),
        ],
        missing: const [],
        sleepHours: null,
        hasNumber: true,
        capped: false,
      );
      expect(e.drivers.map((d) => d.id), [ReadinessFactorId.hrv]);
    });
    test('toString nennt keine Werte', () {
      final r = computeReadiness(inputs(hrvZ: -2, hours: 5));
      expect(r.explanation.drivers.first.toString(), isNot(contains('-')));
    });
  });
}
