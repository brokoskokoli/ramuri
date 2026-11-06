import 'package:core/core.dart';
import 'package:test/test.dart';

const _lt = SmoothedVo2maxLongTerm();
const _p = FitnessParameters.v3();
final _now = DateTime.utc(2030, 6, 1, 12);

/// Lauf, der zu [end] endete.
AdvancedFitnessValue<double> runAt(
  double? value,
  QualityTier tier,
  DateTime end,
) => AdvancedFitnessValue<double>(
  metadata: FitnessValueMetadata(
    calculatedAt: end,
    dataFrom: end.subtract(const Duration(hours: 1)),
    dataTo: end,
    usableMeasurements: 3,
    dataSources: const {'gps'},
    method: 'vo2max-acsm-hrr',
    methodVersion: 1,
    parameterVersion: 3,
    tier: tier,
  ),
  value: tier == QualityTier.notDeterminable ? null : value,
  reason: tier == QualityTier.notDeterminable
      ? UnavailableReason.spreadTooHigh
      : null,
);

/// Lauf, der [daysAgo] Tage (plus [extra]) vor [_now] endete.
AdvancedFitnessValue<double> run(
  double? value,
  QualityTier tier,
  num daysAgo, {
  Duration extra = Duration.zero,
}) => runAt(
  value,
  tier,
  _now.subtract(Duration(hours: (daysAgo * 24).round())).subtract(extra),
);

AdvancedFitnessValue<double> compute(
  List<AdvancedFitnessValue<double>> runs, [
  DateTime? now,
]) => _lt.compute(runs: runs, p: _p, now: now ?? _now);

const g = QualityTier.good;
const s = QualityTier.sufficient;
const v = QualityTier.preliminary;
const nd = QualityTier.notDeterminable;

void main() {
  group('α (PAR-034)', () {
    test('Grenzen von n je Stufe', () {
      final p = _p.vo2max;
      double a(QualityTier t, int n) => SmoothedVo2maxLongTerm.alpha(t, n, p);
      // gut: 1/n gilt bis n=6 (1/6 = 0,1667 > 0,15), ab n=7 0,15.
      expect(a(g, 2), 0.5);
      expect(a(g, 6), closeTo(1 / 6, 1e-12));
      expect(a(g, 7), 0.15);
      // ausreichend: 1/10 bei n=10, darüber 0,10; n=9 1/9.
      expect(a(s, 9), closeTo(1 / 9, 1e-12));
      expect(a(s, 10), 0.10);
      expect(a(s, 11), 0.10);
      // vorläufig: 1/(2n) bis n=10 (0,05 bei n=10), n=2 0,25.
      expect(a(v, 2), 0.25);
      expect(a(v, 9), closeTo(1 / 18, 1e-12));
      expect(a(v, 10), 0.05);
      expect(a(v, 11), 0.05);
      expect(a(nd, 5), 0);
      expect(() => a(g, 0), throwsArgumentError);
    });

    test('Wert nach zwei Läufen folgt der Formel', () {
      // n=2, gut: α 0,5
      final r = compute([run(40, g, 10), run(50, g, 3)]);
      expect(r.value, closeTo(45, 1e-9));
    });
  });

  group('Glättung', () {
    test('erster verwertbarer Lauf setzt den Wert', () {
      final r = compute([run(42.5, v, 3)]);
      expect(r.value, 42.5);
    });

    test('Reihenfolge der Eingabe ist egal, Zeit entscheidet', () {
      final a = compute([run(40, g, 10), run(50, g, 3), run(44, g, 1)]);
      final b = compute([run(44, g, 1), run(40, g, 10), run(50, g, 3)]);
      expect(a.value, b.value);
      // 40 -> 45 (α .5) -> 45 + (1/3)(44-45)
      expect(a.value, closeTo(45 - 1 / 3, 1e-9));
    });

    test('Ausreißerlauf ändert den Langzeitwert weniger als den Laufwert', () {
      final base = [for (var i = 0; i < 8; i++) run(45, g, 40 - i * 4)];
      final before = compute(base).value!;
      final after = compute([...base, run(60, g, 1)]).value!;
      expect(before, closeTo(45, 1e-9));
      expect((after - before).abs(), lessThan(60 - 45));
      // n=9, gut: α 0,15 -> +2,25
      expect(after - before, closeTo(0.15 * 15, 1e-9));
    });
  });

  group('Neustart (PAR-035)', () {
    // Drei Läufe (n=3, Wert 40), dann ein Lauf mit 50 nach genau [gap].
    double afterPause(Duration gap) {
      final a = run(40, g, 200);
      final b = run(40, g, 190);
      final c = run(40, g, 180);
      final next = runAt(50, g, c.metadata.dataTo.add(gap));
      return compute([a, b, c, next]).value!;
    }

    test('genau 8 Wochen: kein Neustart (n=4, α 0,25)', () {
      expect(afterPause(const Duration(days: 56)), closeTo(42.5, 1e-9));
    });

    test('8 Wochen + 1 s: Neustart (n=2, α 0,5)', () {
      expect(
        afterPause(const Duration(days: 56, seconds: 1)),
        closeTo(45, 1e-9),
      );
    });

    test('Neustart zählt ab n=2 weiter (nächster Lauf n=3)', () {
      final a = run(40, g, 300);
      final b = run(50, g, 200); // Pause > 8 Wochen, n=2 -> 45
      final c = run(60, g, 190); // n=3 -> 45 + 1/3*15 = 50
      expect(compute([a, b, c]).value, closeTo(50, 1e-6));
    });

    test('„vorläufig“ nach Neustart: α 0,25', () {
      final a = run(40, g, 300);
      final b = run(50, v, 200);
      expect(compute([a, b]).value, closeTo(42.5, 1e-9));
    });

    test('nicht bestimmbarer Lauf unterbricht die Pause nicht', () {
      final a = run(40, g, 300);
      final x = run(null, nd, 250);
      final b = run(50, g, 200);
      final c = run(60, g, 190);
      expect(compute([a, x, b, c]).value, compute([a, b, c]).value);
      expect(compute([a, x, b]).value, closeTo(45, 1e-6));
    });
  });

  group('FR-0080', () {
    test('nicht bestimmbarer Lauf lässt den Wert unverändert', () {
      final base = [run(40, g, 20), run(50, g, 10)];
      final with_ = compute([...base, run(null, nd, 2)]);
      final without = compute(base);
      expect(with_.value, without.value);
      expect(with_.metadata.usableMeasurements, 2);
      expect(with_.metadata.tier, without.metadata.tier);
    });

    test('nur nicht bestimmbare Läufe: nicht bestimmbar mit Grund', () {
      final r = compute([run(null, nd, 2)]);
      expect(r.value, isNull);
      expect(r.metadata.tier, QualityTier.notDeterminable);
      expect(r.reason, UnavailableReason.insufficientData);
      expect(compute(const []).value, isNull);
    });
  });

  group('Langzeitstufe (PAR-041 bis PAR-043)', () {
    QualityTier tier(List<AdvancedFitnessValue<double>> runs) =>
        compute(runs).metadata.tier;

    test('PAR-041: 2 Läufe in 6 Wochen -> vorläufig, auch wenn alle gut', () {
      expect(tier([run(45, g, 5), run(45, g, 10)]), v);
    });

    test('PAR-042: 3 Läufe in 6 Wochen, 2 ausreichend -> ausreichend', () {
      expect(tier([run(45, s, 5), run(45, s, 10), run(45, v, 15)]), s);
    });

    test('PAR-042: nur 1 ausreichend unter 3 -> nicht ausreichend', () {
      expect(tier([run(45, s, 5), run(45, v, 10), run(45, v, 15)]), v);
    });

    test('PAR-043: 5 Läufe in 8 Wochen, 3 gut, 3 in 6 Wochen -> gut', () {
      expect(
        tier([
          run(45, g, 5),
          run(45, g, 10),
          run(45, g, 15),
          run(45, v, 50),
          run(45, v, 55),
        ]),
        g,
      );
    });

    test('PAR-043: nur 2 gut -> ausreichend', () {
      expect(
        tier([
          run(45, g, 5),
          run(45, g, 10),
          run(45, s, 15),
          run(45, v, 50),
          run(45, v, 55),
        ]),
        s,
      );
    });

    test('PAR-043: nur 4 Läufe in 8 Wochen -> nicht gut', () {
      expect(
        tier([run(45, g, 5), run(45, g, 10), run(45, g, 15), run(45, g, 50)]),
        s,
      );
    });

    test(
      'PAR-041 geht vor: 5 Läufe in 8 Wochen, 3 gut, aber 2 in 6 Wochen',
      () {
        expect(
          tier([
            run(45, g, 5),
            run(45, g, 10),
            run(45, g, 50),
            run(45, g, 52),
            run(45, g, 55),
          ]),
          v,
        );
      },
    );

    test('Fenstergrenzen: genau 6 Wochen zählt, +1 s nicht', () {
      final inside = [run(45, s, 1), run(45, s, 2), run(45, s, 42)];
      expect(tier(inside), s);
      final outside = [
        run(45, s, 1),
        run(45, s, 2),
        run(45, s, 42, extra: const Duration(seconds: 1)),
      ];
      expect(tier(outside), v);
    });

    test('Fenstergrenzen 8 Wochen: genau zählt, +1 s nicht', () {
      List<AdvancedFitnessValue<double>> l(Duration extra) => [
        run(45, g, 1),
        run(45, g, 2),
        run(45, g, 3),
        run(45, v, 4),
        run(45, v, 56, extra: extra),
      ];
      expect(tier(l(Duration.zero)), g);
      expect(tier(l(const Duration(seconds: 1))), s);
    });

    test('nicht bestimmbare Läufe zählen nicht', () {
      expect(tier([run(45, s, 5), run(45, s, 10), run(null, nd, 12)]), v);
    });

    test(
      'veralteter Wert bleibt, ist vorläufig, Datenzeitraum der letzte Lauf',
      () {
        final r = compute([run(45, g, 100), run(45, g, 90)]);
        expect(r.value, 45);
        expect(r.metadata.tier, v);
        expect(r.metadata.usableMeasurements, 0);
      },
    );
  });

  group('Metadaten und Uhr', () {
    test('Methode, Versionen, Datenzeitraum, Berechnungszeitpunkt', () {
      final a = run(40, g, 10);
      final b = run(50, g, 3);
      final r = compute([a, b]);
      final m = r.metadata;
      expect(m.method, 'vo2max-long-term-ema');
      expect(m.methodVersion, 1);
      expect(m.parameterVersion, _p.parameterVersion);
      expect(m.calculatedAt, _now);
      expect(m.dataFrom, a.metadata.dataFrom);
      expect(m.dataTo, b.metadata.dataTo);
      expect(m.dataSources, {'gps'});
      expect(m.usableMeasurements, 2);
      expect(
        AlgorithmRegistry.standard().active(vo2maxLongTermFamily).category,
        AlgorithmCategory.heuristic,
      );
    });
  });
}
