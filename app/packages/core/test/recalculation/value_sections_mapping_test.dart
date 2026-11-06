import 'package:core/core.dart';
import 'package:test/test.dart';

import '../fitness/section_support.dart';

const _p = FitnessParameters.v3();
const _estimator = AcsmReserveVo2maxEstimator();

Vo2maxRunEstimate _estimate(
  SectionSelection sel,
  HeartRateBasis basis,
  int seconds,
) => _estimator.estimate(
  selection: sel,
  basis: basis,
  p: _p,
  calculatedAt: selAt(0),
  runStart: selT0,
  runEnd: selAt(seconds),
);

void main() {
  // 50-min-Lauf mit echter Auswahl und echtem Schätzer: GPS-Median 8 m in den
  // ersten 700 s (Faktor PAR-033 0,75), Puls 100 zwischen 1500 und 1900 s
  // (Abschnitt 23-33 min wird abgelehnt), Abschnitte ab Minute 30 mit
  // Spätfaktor 0,5 (PAR-024). Ergibt fünf Abschnitte à 10 min.
  final scenario = steady(
    3000,
    accuracy: (s) => s < 700 ? 8 : 5,
    bpm: (s) => s > 1500 && s < 1900 ? 100 : 150,
  );
  final selection = selectSections(scenario);
  final estimate = _estimate(selection, selBasis, scenario.seconds);

  test('Ausgangslage: fünf Abschnitte, vier geschätzt, einer abgelehnt', () {
    expect(selection.sections, hasLength(5));
    expect(estimate.sections, hasLength(4));
    expect(selection.sections[2].status, SectionStatus.rejected);
  });

  test('echte Schätzerausgabe: Gewicht (PAR-033), Spätfaktor (PAR-024), '
      'GPS-Median und Gründe je Abschnitt', () {
    final v = valueSectionsOf(selection, estimate);
    expect(v, hasLength(5));
    // PAR-033: Minuten (10) * GPS-Faktor (0,75 bei Median 8 m, sonst 1) *
    // Spätfaktor (PAR-024: 1 bis Minute 30, danach 0,5; abgelehnt: 0).
    expect([for (final s in v) s.weight], [7.5, 10, 0, 5, 5]);
    expect([for (final s in v) s.lateFactor], [1, 1, 0, 0.5, 0.5]);
    expect([for (final s in v) s.gpsMedianAccuracyMeters], [8, 5, 5, 5, 5]);
    expect(
      [for (final s in v) s.status],
      [
        SectionStatus.eligible,
        SectionStatus.eligible,
        SectionStatus.rejected,
        SectionStatus.eligible,
        SectionStatus.eligible,
      ],
    );
    // Dieselbe Zahl wie die Rechnung des Schätzers.
    for (final e in estimate.sections) {
      final stored = v[selection.sections.indexOf(e.section)];
      expect(
        stored.weight,
        AcsmReserveVo2maxEstimator.sectionWeight(e.section, _p.vo2max),
      );
      expect(stored.estimate, e.vo2max);
      expect(stored.oxygenDemand, e.oxygenDemand);
      expect(stored.discard, e.discard);
    }
    // Gründe des abgelehnten Abschnitts: Namen der verletzten Regeln.
    expect(v[2].reasons, ['heartRateHalves', 'intensityLow']);
    expect(v[2].estimate, isNull);
    expect(v[2].oxygenDemand, isNull);
    expect(v[2].discard, isNull);
    expect(v[0].reasons, isEmpty);
    // Zeitraum in Reihenfolge.
    expect(v[0].start, selection.sections[0].from);
    expect(v[4].end, selection.sections[4].to);
  });

  test('ohne Schätzung (Basis fehlt): Abschnitte mit Gewicht 0 und ohne '
      'Schätzwert, Spätfaktor bleibt', () {
    const none = HeartRateBasis();
    final noBasis = selectSections(scenario, basis: none);
    final e = _estimate(noBasis, none, scenario.seconds);
    expect(e.result.reason, isNotNull);
    expect(e.sections, isEmpty);
    final v = valueSectionsOf(noBasis, e);
    expect(v, hasLength(5));
    expect(v.every((s) => s.weight == 0 && s.estimate == null), isTrue);
    expect(
      [for (final s in v) s.lateFactor],
      [for (final s in noBasis.sections) s.weight],
    );
  });

  group('nicht endliche Zahlen (fromEstimate)', () {
    SectionEstimate est({
      double? demand = 40,
      double? max = 50,
      EstimateDiscard? discard,
    }) => SectionEstimate(
      section: selection.sections[0],
      oxygenDemand: demand,
      vo2max: max,
      weight: 7.5,
      discard: discard,
    );

    test('NaN und unendlich werden null, der Grund steht in discard', () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final s = ValueSection.fromEstimate(est(max: bad));
        expect(s.estimate, isNull, reason: '$bad');
        expect(s.discard, EstimateDiscard.incomplete, reason: '$bad');
        final d = ValueSection.fromEstimate(est(demand: bad, max: null));
        expect(d.oxygenDemand, isNull, reason: '$bad');
        expect(d.discard, EstimateDiscard.incomplete, reason: '$bad');
      }
    });

    test('ein vorhandener Grund bleibt, endliche Werte bleiben', () {
      final s = ValueSection.fromEstimate(
        est(max: double.nan, discard: EstimateDiscard.implausible),
      );
      expect(s.discard, EstimateDiscard.implausible);
      final ok = ValueSection.fromEstimate(est());
      expect(ok.estimate, 50);
      expect(ok.oxygenDemand, 40);
      expect(ok.discard, isNull);
    });
  });
}
