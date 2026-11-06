import 'package:core/core.dart';
import 'package:test/test.dart';

import 'section_support.dart';

const _est = AcsmReserveVo2maxEstimator();
const _p = FitnessParameters.v3();
final _t0 = DateTime.utc(2030, 1, 1, 12);
final _end = _t0.add(const Duration(hours: 1));

/// Abschnitt, der bei 180 m/min eben genau [vo2max] ergibt (r daraus).
EvaluatedSection sec(
  double vo2max, {
  int startMin = 0,
  num durMin = 10,
  double? gps = 5,
  double weight = 1,
  List<SectionCaveat> caveats = const [],
  SectionStatus? status,
}) {
  const v = 180.0;
  final r = (_p.vo2max.runCoefficient * v) / (vo2max - _p.vo2max.restingOxygen);
  final from = _t0.add(Duration(minutes: startMin));
  return EvaluatedSection(
    from: from,
    to: from.add(Duration(microseconds: (durMin * 6e7).round())),
    status:
        status ??
        (caveats.isEmpty ? SectionStatus.eligible : SectionStatus.provisional),
    violations: const [],
    caveats: caveats,
    weight: weight,
    speedMetersPerMinute: v,
    meanHeartRate: 150,
    relativeLoad: r,
    gradient: 0,
    gradientBasis: GradientBasis.belowThreshold,
    distanceMeters: v * 10,
    gpsMedianAccuracyMeters: gps,
  );
}

SectionSelection selOf(List<EvaluatedSection> s) =>
    SectionSelection(parameterVersion: 3, sections: s, excluded: const []);

Vo2maxRunEstimate run(
  List<EvaluatedSection> s, {
  HeartRateBasis basis = selBasis,
  FitnessParameters p = _p,
  bool treadmill = false,
}) => _est.estimate(
  selection: selOf(s),
  basis: basis,
  p: p,
  calculatedAt: _end,
  runStart: _t0,
  runEnd: _end,
  treadmill: treadmill,
);

/// Drei 10-min-Abschnitte (S = 0, 30 min): „gut“ ohne Obergrenze.
List<EvaluatedSection> three([
  double a = 50,
  double b = 50,
  double c = 50,
  List<SectionCaveat> caveats = const [],
]) => [
  sec(a, startMin: 0, caveats: caveats),
  sec(b, startMin: 10),
  sec(c, startMin: 20),
];

void main() {
  group('Referenzwerte (FR-0069, FR-0071)', () {
    test('10 km/h eben ergibt 36,83 ml/kg/min', () {
      expect(
        AcsmReserveVo2maxEstimator.oxygenDemand(1e4 / 60, 0, _p.vo2max),
        closeTo(36.83, 0.005),
      );
    });

    test('10 km/h, HF 150, HFmax 190, HFRuhe 60: r 0,6923, VO2max 51,6', () {
      final r = const HeartRateReserve().relativeLoad(selBasis, 150, _p);
      final load = (r as FitnessAvailable<double>).value;
      expect(load, closeTo(0.6923, 0.00005));
      final demand = AcsmReserveVo2maxEstimator.oxygenDemand(
        1e4 / 60,
        0,
        _p.vo2max,
      );
      expect(
        AcsmReserveVo2maxEstimator.extrapolate(demand, load, _p.vo2max),
        closeTo(51.6, 0.06),
      );
    });

    test('Steigung geht mit 0,9·v·G ein (FR-0069)', () {
      // 3,5 + 0,2·180 + 0,9·180·0,02
      expect(
        AcsmReserveVo2maxEstimator.oxygenDemand(180, 0.02, _p.vo2max),
        closeTo(42.74, 1e-9),
      );
      expect(
        AcsmReserveVo2maxEstimator.oxygenDemand(180, -0.02, _p.vo2max),
        closeTo(36.26, 1e-9),
      );
    });

    test('Abschnitt trägt Bedarf, Hochrechnung und Gewicht', () {
      final e = run(three()).sections.first;
      expect(e.oxygenDemand, closeTo(39.5, 1e-9));
      expect(e.vo2max, closeTo(50, 1e-9));
      expect(e.weight, closeTo(10, 1e-9));
    });
  });

  group('FR-0066: synthetischer Lauf ergibt einen Wert', () {
    SectionSelection real(int usableSeconds) =>
        selectSections(steady(usableSeconds));

    Vo2maxRunEstimate go(SectionSelection s) => _est.estimate(
      selection: s,
      basis: selBasis,
      p: _p,
      calculatedAt: selAt(0),
      runStart: selT0,
      runEnd: selAt(4000),
      dataSources: {'gps', 'chest-strap'},
    );

    test('ein Abschnitt: Wert 55,5, vorläufig wegen eines Abschnitts', () {
      final r = go(real(600));
      // 180 m/min, r = 90/130: 3,5 + 36 / (90/130)
      expect(r.result.value, closeTo(3.5 + 36 * 130 / 90, 1e-6));
      expect(r.tier, QualityTier.preliminary);
      expect(r.caps, {TierCap.singleSection});
      expect(r.spreadPercent, isNull);
    });

    test('drei gleichmäßige Abschnitte: gut, Metadaten gefüllt', () {
      final r = go(real(1800));
      expect(r.used, hasLength(3));
      expect(r.tier, QualityTier.good);
      expect(r.spreadPercent, closeTo(0, 1e-9));
      final m = r.result.metadata;
      expect(m.method, vo2maxEstimatorMethod);
      expect(m.methodVersion, vo2maxEstimatorMethodVersion);
      expect(m.parameterVersion, currentParameterVersion);
      expect(m.usableMeasurements, 3);
      expect(m.dataSources, {'gps', 'chest-strap'});
    });

    test('zwei Abschnitte (20 min): ausreichend, nicht gut (PAR-021/040)', () {
      final r = go(real(1200));
      expect(r.used, hasLength(2));
      expect(r.tier, QualityTier.sufficient);
    });
  });

  group('FR-0068: fehlende Eingabe, kein Wert, sichtbarer Grund', () {
    for (final c in [
      (
        const HeartRateBasis(restingBpm: 60),
        UnavailableReason.missingMaxHeartRate,
      ),
      (
        const HeartRateBasis(maxBpm: 190),
        UnavailableReason.missingRestingHeartRate,
      ),
      (
        const HeartRateBasis(maxBpm: 60, restingBpm: 60),
        UnavailableReason.maxNotAboveResting,
      ),
      (
        const HeartRateBasis(maxBpm: 109, restingBpm: 60),
        UnavailableReason.reserveTooSmall,
      ),
    ]) {
      test(c.$2.name, () {
        final r = run(three(), basis: c.$1);
        expect(r.tier, QualityTier.notDeterminable);
        expect(r.result.value, isNull);
        expect(r.result.reason, c.$2);
        expect(r.result.metadata.parameterVersion, 3);
      });
    }

    test('Reserve genau 50 bpm ist noch gültig (PAR-019)', () {
      expect(
        run(
          three(),
          basis: const HeartRateBasis(maxBpm: 110, restingBpm: 60),
        ).result.value,
        isNotNull,
      );
    });

    test('kein gültiger Abschnitt: Grund noValidSection', () {
      final rejected = sec(50, status: SectionStatus.rejected);
      for (final s in [
        <EvaluatedSection>[],
        [rejected],
      ]) {
        final r = run(s);
        expect(r.tier, QualityTier.notDeterminable);
        expect(r.result.value, isNull);
        expect(r.result.reason, UnavailableReason.noValidSection);
      }
    });

    test('nur unvollständige Abschnitte: Grund noValidSection', () {
      final s = EvaluatedSection(
        from: _t0,
        to: _t0.add(const Duration(minutes: 10)),
        status: SectionStatus.eligible,
        violations: const [],
        caveats: const [],
        weight: 1,
        speedMetersPerMinute: 180,
        meanHeartRate: 150,
        relativeLoad: null,
        gradient: 0,
        gradientBasis: GradientBasis.belowThreshold,
        distanceMeters: 1800,
      );
      final r = run([s]);
      expect(r.sections.single.discard, EstimateDiscard.incomplete);
      expect(r.result.reason, UnavailableReason.noValidSection);
    });

    test('nur Abschnitte mit Gewicht 0: verworfen, Grund noValidSection', () {
      final r = run([sec(50, weight: 0), sec(52, startMin: 10, weight: 0)]);
      expect(r.sections.map((e) => e.discard), [
        EstimateDiscard.zeroWeight,
        EstimateDiscard.zeroWeight,
      ]);
      expect(r.tier, QualityTier.notDeterminable);
      expect(r.result.reason, UnavailableReason.noValidSection);
    });

    test('Gewicht 0 neben gültigen Abschnitten: verworfen, kein Fehler', () {
      final r = run([...three(), sec(70, startMin: 30, weight: 0)]);
      expect(r.sections.last.discard, EstimateDiscard.zeroWeight);
      expect(r.used, hasLength(3));
      expect(r.result.value, run(three()).result.value);
    });

    test('Parameterversion der Auswahl weicht ab: ArgumentError', () {
      expect(
        () => _est.estimate(
          selection: SectionSelection(
            parameterVersion: 2,
            sections: three(),
            excluded: const [],
          ),
          basis: selBasis,
          p: _p,
          calculatedAt: _end,
          runStart: _t0,
          runEnd: _end,
        ),
        throwsArgumentError,
      );
    });

    test('nur Abschnitte ohne Puls: Grund noHeartRate', () {
      final s = EvaluatedSection(
        from: _t0,
        to: _t0.add(const Duration(minutes: 10)),
        status: SectionStatus.rejected,
        violations: const [SectionViolation(SectionRule.heartRateUnavailable)],
        caveats: const [],
        weight: 0,
        speedMetersPerMinute: 180,
        meanHeartRate: null,
        relativeLoad: null,
        gradient: 0,
        gradientBasis: GradientBasis.belowThreshold,
        distanceMeters: 1800,
      );
      expect(run([s]).result.reason, UnavailableReason.noHeartRate);
    });

    test('echter Lauf ohne Puls ergibt keinen Wert mit Grund', () {
      final sel = selectSections(steady(1200, bpm: (s) => null));
      final r = _est.estimate(
        selection: sel,
        basis: selBasis,
        p: _p,
        calculatedAt: selAt(0),
        runStart: selT0,
        runEnd: selAt(1400),
      );
      expect(r.result.value, isNull);
      expect(r.result.reason, isNotNull);
    });
  });

  group('PAR-032: Plausibilität', () {
    test('Standardgrenzen 25 und 90', () {
      expect(_p.vo2max.plausibleMin, 25);
      expect(_p.vo2max.plausibleMax, 90);
    });

    test('knapp außerhalb wird verworfen, knapp innerhalb bleibt', () {
      expect(run(three(24.9)).used, hasLength(2));
      expect(run(three(25.1)).used, hasLength(3));
      expect(run(three(50, 50, 89.9)).used, hasLength(3));
      expect(run(three(50, 50, 90.1)).used, hasLength(2));
    });

    test('die Grenze selbst gilt (inklusiv)', () {
      final e = run(three(50)).sections.first;
      final exact = e.vo2max!;
      for (final p in [
        _p.copyWith(vo2max: Vo2maxParameters(plausibleMin: exact)),
        _p.copyWith(vo2max: Vo2maxParameters(plausibleMax: exact)),
      ]) {
        expect(run(three(), p: p).used, hasLength(3));
      }
    });

    test('alle verworfen: nicht bestimmbar mit Grund, Abschnitte bleiben', () {
      final r = run(three(10, 12, 100));
      expect(r.tier, QualityTier.notDeterminable);
      expect(r.result.reason, UnavailableReason.allEstimatesImplausible);
      expect(r.sections, hasLength(3));
      expect(r.used, isEmpty);
    });
  });

  group('FR-0076: unplausibler Abschnitt verschiebt den Wert nicht', () {
    test('ohne Filter läge der Median bei 52, mit Filter bei 51', () {
      final r = run([
        sec(50, startMin: 0),
        sec(52, startMin: 10),
        sec(150, startMin: 20),
      ]);
      expect(r.used, hasLength(2));
      expect(r.result.value, closeTo(51, 1e-9));
    });

    test('abgelehnte Abschnitte gehen nicht ein', () {
      final r = run([
        ...three(48, 50, 52),
        sec(80, startMin: 30, status: SectionStatus.rejected),
      ]);
      expect(r.sections, hasLength(3));
      expect(r.result.value, run(three(48, 50, 52)).result.value);
    });

    test('jeder Laufwert trägt eine Stufe', () {
      expect(run(three()).tier, isA<QualityTier>());
      expect(run([]).tier, QualityTier.notDeterminable);
    });
  });

  group('PAR-033: Gewichtung', () {
    final p = _p.vo2max;

    test('Dauer in Minuten bis 10', () {
      expect(
        AcsmReserveVo2maxEstimator.sectionWeight(sec(50, durMin: 6), p),
        closeTo(6, 1e-9),
      );
      expect(
        AcsmReserveVo2maxEstimator.sectionWeight(sec(50, durMin: 12), p),
        closeTo(10, 1e-9),
      );
    });

    test('GPS-Faktor: Median 5 m voll, darüber und ohne Angabe 0,75', () {
      double w(double? gps) =>
          AcsmReserveVo2maxEstimator.sectionWeight(sec(50, gps: gps), p);
      expect(w(5), closeTo(10, 1e-9));
      expect(w(5.01), closeTo(7.5, 1e-9));
      expect(w(null), closeTo(7.5, 1e-9));
    });

    test('Spätfaktor aus Teil A geht ein', () {
      expect(
        AcsmReserveVo2maxEstimator.sectionWeight(sec(50, weight: 0.5), p),
        closeTo(5, 1e-9),
      );
    });

    test('Gewicht entscheidet den Median (ungewichtet läge er bei 60)', () {
      final r = run([
        sec(40, startMin: 0), // Gewicht 10
        sec(60, startMin: 10, durMin: 5, gps: 6), // 3,75
        sec(70, startMin: 20, durMin: 5), // 5
      ]);
      expect(r.result.value, closeTo(40, 1e-9));
    });

    test('Hälfte genau getroffen trotz Gleitkomma-Rundung: Mitte', () {
      // Dezimal ist die Summe der ersten beiden Gewichte genau die Hälfte,
      // in Gleitkomma ist cum * 2 != total.
      const w = [0.1, 0.2, 0.2, 0.1];
      expect((w[0] + w[1]) * 2, isNot(w.reduce((a, b) => a + b)));
      expect(
        AcsmReserveVo2maxEstimator.weightedMedian([10, 20, 30, 40], w),
        25,
      );
    });

    test('gewichteter Median: Hälfte genau getroffen mittelt', () {
      expect(AcsmReserveVo2maxEstimator.weightedMedian([60, 40], [5, 5]), 50);
      expect(
        AcsmReserveVo2maxEstimator.weightedMedian([60, 40, 70], [1, 1, 1]),
        60,
      );
    });
  });

  group('PAR-036: Streuung S', () {
    final p = _p.vo2max;
    double? s(List<double> v, List<double> t, double c) =>
        AcsmReserveVo2maxEstimator.spread(v, t, c, p);

    test('ein Wert hat keine Streuung', () {
      expect(s([50], [0], 50), isNull);
    });

    test('zwei Werte: Spannweite durch Median, in Prozent', () {
      expect(s([48, 52], [0, 10], 50), closeTo(8, 1e-9));
    });

    test('ab 3 Abschnitten wird der Zeittrend entfernt', () {
      expect(s([45, 50, 55], [0, 10, 20], 50), closeTo(0, 1e-9));
      expect(s([40, 50, 60, 70], [0, 10, 20, 30], 55), closeTo(0, 1e-9));
    });

    test('ab 5 Abschnitten P10 bis P90 statt Spannweite', () {
      // Reste [-4,-4,16,-4,-4]: Spannweite 20, P10..P90 = 12.
      expect(
        s([50, 50, 70, 50, 50], [0, 10, 20, 30, 40], 50),
        closeTo(24, 1e-9),
      );
      // Bei 4 Abschnitten gilt noch die Spannweite der Reste.
      expect(s([50, 70, 50, 50], [0, 10, 20, 30], 50), closeTo(44, 1e-9));
      // Trend -0,2/min, Reste [-8, 14, -4, -2]: Spannweite 22.
    });
  });

  group('FR-0077: gleiches Mittel, gleicher Trend, mehr Streuung', () {
    // Werte = 50 + x + e mit x = -1, 0, 1 und e senkrecht zu 1 und x.
    List<EvaluatedSection> withResidual(double k) =>
        three(49 + 1 * k, 50 - 2 * k, 51 + 1 * k);

    test('enger Lauf ist gut, streuender Lauf ist schlechter', () {
      final tight = run(withResidual(0.1));
      final wide = run(withResidual(1.5));
      double mean(Vo2maxRunEstimate r) =>
          r.used.map((e) => e.vo2max!).reduce((a, b) => a + b) / 3;
      // Gleicher Trend: Steigung der kleinsten Quadrate über die Abschnitte
      // (Mitten im Abstand von 10 min) ist bei beiden gleich.
      double slope(Vo2maxRunEstimate r) {
        final y = r.used.map((e) => e.vo2max!).toList();
        return (y[2] - y[0]) / 20;
      }

      expect(slope(tight), closeTo(0.1, 1e-9));
      expect(slope(wide), closeTo(slope(tight), 1e-9));
      expect(mean(tight), closeTo(mean(wide), 1e-9));
      expect(tight.tier, QualityTier.good);
      expect(wide.tier, QualityTier.sufficient);
      expect(wide.spreadPercent!, greaterThan(tight.spreadPercent!));
    });

    test('reine Drift senkt die Stufe nicht (Trendabzug)', () {
      expect(run(three(45, 50, 55)).tier, QualityTier.good);
    });
  });

  group('PAR-037 bis PAR-040: Stufen an den Grenzen', () {
    QualityTier t(
      double? s, {
      int n = 3,
      Duration total = const Duration(minutes: 30),
      Set<TierCap> caps = const {},
    }) => AcsmReserveVo2maxEstimator.tierFor(
      sections: n,
      total: total,
      spreadPercent: s,
      caps: caps,
      p: _p.vo2max,
    );

    test('S über 20 % ist nicht bestimmbar, genau 20 % noch vorläufig', () {
      expect(t(20), QualityTier.preliminary);
      expect(t(20.0001), QualityTier.notDeterminable);
    });

    test('S über 10 % ist vorläufig, genau 10 % ausreichend', () {
      expect(t(10), QualityTier.sufficient);
      expect(t(10.0001), QualityTier.preliminary);
    });

    test('S über 5 % ist nicht gut, genau 5 % gut', () {
      expect(t(5), QualityTier.good);
      expect(t(5.0001), QualityTier.sufficient);
    });

    test('gut braucht 3 Abschnitte und 20 min', () {
      expect(t(1, n: 2), QualityTier.sufficient);
      expect(t(1, total: const Duration(minutes: 20)), QualityTier.good);
      expect(
        t(
          1,
          total: const Duration(minutes: 20) - const Duration(microseconds: 1),
        ),
        QualityTier.sufficient,
      );
    });

    test('ausreichend braucht 2 Abschnitte', () {
      expect(t(1, n: 2), QualityTier.sufficient);
      expect(t(null, n: 1), QualityTier.preliminary);
    });

    test('kein Abschnitt: nicht bestimmbar', () {
      expect(t(null, n: 0), QualityTier.notDeterminable);
    });

    test('Obergrenzen gelten auch bei S = 0, jede einzeln', () {
      for (final c in TierCap.values) {
        expect(t(0, caps: {c}), QualityTier.preliminary, reason: c.name);
      }
      expect(t(0), QualityTier.good);
    });

    test('Obergrenze rettet nicht vor S über 20 %', () {
      expect(t(20.5, caps: {TierCap.treadmill}), QualityTier.notDeterminable);
    });
  });

  group('PAR-038: Obergrenzen im Lauf', () {
    test('ohne Obergrenze: gut', () {
      final r = run(three());
      expect(r.tier, QualityTier.good);
      expect(r.caps, isEmpty);
    });

    test('ein Abschnitt', () {
      final r = run([sec(50)]);
      expect(r.tier, QualityTier.preliminary);
      expect(r.caps, {TierCap.singleSection});
      expect(r.result.value, isNotNull);
    });

    test('ein Abschnitt, der ausscheidet, zählt nicht mit', () {
      final r = run([sec(50), sec(50, startMin: 10), sec(150, startMin: 20)]);
      expect(r.used, hasLength(2));
      expect(r.tier, QualityTier.sufficient);
    });

    test('HFmax aus der Altersformel', () {
      final r = run(
        three(),
        basis: const HeartRateBasis(
          maxBpm: 190,
          restingBpm: 60,
          maxIsEstimated: true,
        ),
      );
      expect(r.tier, QualityTier.preliminary);
      expect(r.caps, {TierCap.estimatedMaxHeartRate});
      expect(r.maxIsEstimated, isTrue);
    });

    test('Abschnitt im Bereich PAR-031', () {
      final r = run(three(50, 50, 50, [SectionCaveat.limitedSpeed]));
      expect(r.tier, QualityTier.preliminary);
      expect(r.caps, {TierCap.limitedSpeed});
    });

    test('keine verwertbare Höhe, auch ohne Vertikalgenauigkeit (PAR-027)', () {
      for (final c in [
        SectionCaveat.noAltitude,
        SectionCaveat.noVerticalAccuracy,
      ]) {
        final r = run(three(50, 50, 50, [c]));
        expect(r.tier, QualityTier.preliminary, reason: c.name);
        expect(r.caps, {TierCap.noAltitude});
      }
    });

    test('Laufband nur als Parameter', () {
      final r = run(three(), treadmill: true);
      expect(r.tier, QualityTier.preliminary);
      expect(r.caps, {TierCap.treadmill});
    });

    test('S über 20 % bleibt nicht bestimmbar, mit Grund und ohne Wert', () {
      final r = run(three(60, 40, 60));
      expect(r.tier, QualityTier.notDeterminable);
      expect(r.result.value, isNull);
      expect(r.result.reason, UnavailableReason.spreadTooHigh);
      expect(r.spreadPercent, greaterThan(20));
      expect(r.sections, hasLength(3));
    });
  });

  group('Registry (NFR-0005)', () {
    test('Standardbestückung enthält den Schätzer als Heuristik', () {
      final v = AlgorithmRegistry.standard().active(vo2maxEstimatorFamily);
      expect(v.method, vo2maxEstimatorMethod);
      expect(v.methodVersion, 1);
      expect(v.category, AlgorithmCategory.heuristic);
    });
  });
}
