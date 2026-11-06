import 'package:core/core.dart';
import 'package:test/test.dart';

import 'section_support.dart';

/// Der einzige Abschnitt eines 10-min-Laufs (nach 3 min Einschwingzeit).
EvaluatedSection single(SectionSelection r) {
  expect(r.sections, hasLength(1), reason: '${r.sections}');
  return r.sections.single;
}

void expectOnly(SectionSelection r, SectionRule rule) {
  final s = single(r);
  expect(s.status, SectionStatus.rejected);
  expect(rulesOf(s), {rule}, reason: '${s.violations}');
  expect(s.isUsable, isFalse);
  expect(s.weight, 0);
}

void expectUsable(SectionSelection r) {
  final s = single(r);
  expect(s.violations, isEmpty, reason: '${s.violations}');
  expect(s.isUsable, isTrue);
}

/// Tempo mit Stufe: bis einschließlich Sekunde [at] gilt [a], danach [b].
double Function(int) stepSpeed(int at, double a, double b) =>
    (s) => s <= at ? a : b;

/// 50-s-Blöcke abwechselnd schnell und langsam um 3 m/s (relativer Hub [d]).
double Function(int) alternating(double d) =>
    (s) => ((s - 1) ~/ 50).isEven ? 3.0 * (1 + d) : 3.0 * (1 - d);

void main() {
  group('Grundfall und Ergebnisform (FR-0066, FR-0073)', () {
    test('gleichmäßiger Lauf ergibt einen gültigen Abschnitt mit Methode', () {
      final r = selectSections(steady(600));
      final s = single(r);
      expect(s.status, SectionStatus.eligible);
      expect(s.weight, 1);
      expect(s.speedMetersPerMinute, closeTo(180, 1e-6));
      expect(s.meanHeartRate, 150);
      expect(s.relativeLoad, closeTo(90 / 130, 1e-12));
      expect(s.gradient, 0);
      expect(r.method, 'vo2max-section-selection');
      expect(r.methodVersion, 1);
      expect(r.parameterVersion, currentParameterVersion);
      expect(r.usable, [s]);
      expect(r.rejected, isEmpty);
    });

    test(
      'Einschwingzeit wird als ausgeschlossen gemeldet, nicht verworfen',
      () {
        final r = selectSections(steady(600));
        expect(r.excluded, hasLength(1));
        expect(r.excluded.single.kind, ExclusionKind.settling);
        expect(r.excluded.single.span.start, selAt(0));
        expect(r.excluded.single.span.end, selAt(180));
      },
    );

    test('abweichende Parameterversion wird abgelehnt', () {
      expect(
        () => selectSections(
          steady(600),
          parameters: const FitnessParameters(parameterVersion: 99),
        ),
        throwsArgumentError,
      );
    });
  });

  group('PAR-020 Mindestdauer und PAR-021 Aufteilung', () {
    test('genau 5 min nach der Einschwingzeit zählen', () {
      expectUsable(selectSections(steady(300)));
    });

    test('1 s weniger: abgelehnt mit Grund tooShort, nicht verschwunden', () {
      final r = selectSections(steady(299));
      expectOnly(r, SectionRule.tooShort);
      expect(
        r.sections.single.violations.single.value,
        closeTo(299 / 60, 1e-9),
      );
      expect(r.usable, isEmpty);
    });

    test('20 min nutzbar ergeben 2 Abschnitte zu je 10 min', () {
      final r = selectSections(steady(1200));
      expect(r.sections, hasLength(2));
      expect(r.sections[0].from, selAt(180));
      expect(r.sections[0].to, selAt(780));
      expect(r.sections[1].from, selAt(780));
      expect(r.sections[1].to, selAt(1380));
      expect(r.sections.every((s) => s.status == SectionStatus.eligible), true);
    });

    test('genau 10 min bleiben ein Abschnitt, 10 min + 1 s werden zwei', () {
      expect(selectSections(steady(600)).sections, hasLength(1));
      final r = selectSections(steady(601));
      expect(r.sections, hasLength(2));
      for (final s in r.sections) {
        expect(s.duration, greaterThanOrEqualTo(const Duration(minutes: 5)));
        expect(s.duration, lessThanOrEqualTo(const Duration(minutes: 10)));
      }
      expect(r.sections[0].to, r.sections[1].from);
      expect(r.sections.every((s) => s.isUsable), isTrue);
    });

    test('20 min + 1 s ergeben 3 Abschnitte, nicht überlappend, lückenlos', () {
      final r = selectSections(steady(1201));
      expect(r.sections, hasLength(3));
      expect(r.sections.first.from, selAt(180));
      expect(r.sections.last.to, selAt(1381));
      for (var i = 1; i < r.sections.length; i++) {
        expect(r.sections[i].from, r.sections[i - 1].to);
      }
    });

    test('Pause trennt Phasen: beide werden bewertet, Pause ist gemeldet', () {
      final r = selectSections(
        SelScenario(seconds: 1480, pauses: const [(600, 700)]),
      );
      final kinds = r.excluded.map((e) => e.kind).toList();
      expect(kinds, contains(ExclusionKind.pause));
      // Phase 1: 180..600 (7 min), Phase 2: nach 3 min Einschwingzeit (880) ..
      expect(r.sections.first.from, selAt(180));
      expect(r.sections.first.to, selAt(600));
      expect(r.sections.last.from, selAt(880));
      expect(r.sections.last.to, selAt(1480));
      for (final s in r.sections) {
        expect(s.to.isAfter(selAt(600)) && s.from.isBefore(selAt(880)), false);
      }
      expect(
        r.excluded.where((e) => e.kind == ExclusionKind.settling),
        hasLength(2),
      );
    });

    test('Tempowechsel: Einschwingzeit danach zählt nicht zum Abschnitt', () {
      final r = selectSections(
        SelScenario(
          seconds: 1500,
          speed: stepSpeed(600, 2.6, 3.4),
          bpm: (s) => s <= 600 ? 145 : 155,
        ),
      );
      final settling = r.excluded
          .where((e) => e.kind == ExclusionKind.settling)
          .toList();
      expect(settling.length, greaterThanOrEqualTo(2));
      for (final s in r.sections) {
        for (final e in settling) {
          final overlaps =
              s.from.isBefore(e.span.end) && s.to.isAfter(e.span.start);
          expect(overlaps, isFalse, reason: '$s überlappt ${e.span.start}');
        }
      }
      expect(r.usable, isNotEmpty);
    });
  });

  group('PAR-022 Tempostabilität', () {
    test('Variationskoeffizient knapp innerhalb (4 %) und außerhalb (6 %)', () {
      expectUsable(selectSections(steady(600, speed: alternating(0.04))));
      expectOnly(
        selectSections(steady(600, speed: alternating(0.06))),
        SectionRule.paceVariation,
      );
    });

    test('Hälftentempo knapp innerhalb (3,0 %) und außerhalb (3,2 %)', () {
      double Function(int) halves(double d) =>
          stepSpeed(480, 3.0, 3.0 * (1 + d));
      expectUsable(selectSections(steady(600, speed: halves(0.03))));
      expectOnly(
        selectSections(steady(600, speed: halves(0.032))),
        SectionRule.paceHalves,
      );
    });
  });

  group('PAR-023 Pulsstabilität', () {
    int? Function(int) step(int d) =>
        (s) => s <= 480 ? 148 : 148 + d;
    test(
      'Unterschied der Hälften knapp innerhalb (Stufe 5) und außerhalb (6)',
      () {
        expectUsable(selectSections(steady(600, bpm: step(5))));
        expectOnly(
          selectSections(steady(600, bpm: step(6))),
          SectionRule.heartRateHalves,
        );
      },
    );
  });

  group('PAR-010 Pulslücken', () {
    Set<int> drops(Iterable<int> xs) => xs.toSet();
    int? Function(int) without(Set<int> d) =>
        (s) => d.contains(s) ? null : 150;

    test('30 s fehlende Zeit (5 %) zählen, 31 s nicht', () {
      final ok = drops([for (var k = 0; k < 30; k++) 200 + 5 * k]);
      final bad = drops([for (var k = 0; k < 31; k++) 200 + 5 * k]);
      expectUsable(selectSections(steady(600, bpm: without(ok))));
      expectOnly(
        selectSections(steady(600, bpm: without(bad))),
        SectionRule.heartRateGaps,
      );
    });

    test('Einzellücke 10 s zählt, 11 s nicht', () {
      final ok = drops([for (var s = 300; s < 309; s++) s]);
      final bad = drops([for (var s = 300; s < 310; s++) s]);
      expectUsable(selectSections(steady(600, bpm: without(ok))));
      final r = selectSections(steady(600, bpm: without(bad)));
      expectOnly(r, SectionRule.heartRateGaps);
      expect(r.sections.single.violations.single.limit, 10);
    });
  });

  group('PAR-024 später Lauf', () {
    test('Minute 30 genau: halbes Gewicht, 1 s davor volles Gewicht', () {
      // Der Abschnitt beginnt bei 180 s; runStart davor verschoben.
      final half = single(
        selectSections(
          steady(600),
          runStartOffset:
              const Duration(minutes: 30) - const Duration(seconds: 180),
        ),
      );
      expect(half.weight, 0.5);
      expect(half.status, SectionStatus.eligible);
      final full = single(
        selectSections(
          steady(600),
          runStartOffset:
              const Duration(minutes: 30) - const Duration(seconds: 181),
        ),
      );
      expect(full.weight, 1);
    });

    test('Minute 60 genau: Abschnitt entfällt, 1 s davor halbes Gewicht', () {
      final out = selectSections(
        steady(600),
        runStartOffset:
            const Duration(minutes: 60) - const Duration(seconds: 180),
      );
      expectOnly(out, SectionRule.lateRun);
      final inside = single(
        selectSections(
          steady(600),
          runStartOffset:
              const Duration(minutes: 60) - const Duration(seconds: 181),
        ),
      );
      expect(inside.weight, 0.5);
      expect(inside.isUsable, isTrue);
    });
  });

  group('PAR-025 GPS-Qualität', () {
    test('Median der Genauigkeit 10 m zählt, 10,5 m nicht', () {
      expectUsable(selectSections(steady(600, accuracy: (s) => 10)));
      expectOnly(
        selectSections(steady(600, accuracy: (s) => 10.5)),
        SectionRule.gpsMedianAccuracy,
      );
    });

    test('90 % der Punkte ≤ 15 m: 60 von 601 schlechten zählen, 61 nicht', () {
      double? Function(int) bad(int n) =>
          (s) => (s >= 200 && s < 200 + n) ? 20 : 5;
      expectUsable(selectSections(steady(600, accuracy: bad(60))));
      expectOnly(
        selectSections(steady(600, accuracy: bad(61))),
        SectionRule.gpsAccuracyShare,
      );
    });

    test('Punkt mit genau 15 m zählt zum Anteil', () {
      expectUsable(
        selectSections(steady(600, accuracy: (s) => s % 10 == 0 ? 15 : 5)),
      );
    });

    test('GPS-Lücke über 10 s im Abschnitt verletzt nur die Lückenregel', () {
      final r = selectSections(
        steady(600, dropPositions: {for (var s = 476; s <= 485; s++) s}),
      );
      expectOnly(r, SectionRule.gpsGap);
    });

    test('Lücke von genau 10 s ist keine Lücke', () {
      expectUsable(
        selectSections(
          steady(600, dropPositions: {for (var s = 476; s <= 484; s++) s}),
        ),
      );
    });
  });

  group('PAR-026 / PAR-027 Steigung', () {
    double? Function(int, double) slope(double g) =>
        (s, m) => 100 + g * m;

    test('+3 %: 2,9 % innerhalb, 3,1 % außerhalb', () {
      final ok = single(selectSections(steady(600, altitude: slope(0.029))));
      expect(ok.isUsable, isTrue);
      expect(ok.gradient, closeTo(0.029, 1e-6));
      expect(ok.gradientBasis, GradientBasis.measured);
      final bad = selectSections(steady(600, altitude: slope(0.031)));
      expectOnly(bad, SectionRule.gradient);
      expect(bad.sections.single.violations.single.limit, 0.03);
    });

    test(
      '-2 %: -1,9 % innerhalb, -2,1 % außerhalb (starkes Gefälle, FR-0070)',
      () {
        expect(
          single(selectSections(steady(600, altitude: slope(-0.019)))).isUsable,
          isTrue,
        );
        final bad = selectSections(steady(600, altitude: slope(-0.021)));
        expectOnly(bad, SectionRule.gradient);
        expect(bad.sections.single.violations.single.limit, -0.02);
      },
    );

    test('unter 1 % zählt die Steigung nicht (G = 0)', () {
      final s = single(selectSections(steady(600, altitude: slope(0.009))));
      expect(s.gradient, 0);
      expect(s.gradientBasis, GradientBasis.belowThreshold);
    });

    test('ab 1 % zählt sie', () {
      final s = single(selectSections(steady(600, altitude: slope(0.011))));
      expect(s.gradient, closeTo(0.011, 1e-6));
      expect(s.gradientBasis, GradientBasis.measured);
    });

    test(
      'Höhenänderung unter dem Doppelten der Vertikalgenauigkeit: G = 0',
      () {
        // 5 min bei 2,25 m/s = 675 m; 3,5 % = 23,6 m.
        SelScenario run(double acc) => steady(
          300,
          speed: (s) => 2.25,
          altitude: slope(0.035),
          verticalAccuracy: acc,
        );
        // 2 · 15 m = 30 m > 23,6 m: Rauschen, G = 0, Abschnitt bleibt gültig.
        final noisy = single(selectSections(run(15)));
        expect(noisy.gradient, 0);
        expect(noisy.gradientBasis, GradientBasis.belowThreshold);
        expect(noisy.isUsable, isTrue);
        // 2 · 11 m = 22 m <= 23,6 m: G zählt und überschreitet 3 %.
        expectOnly(selectSections(run(11)), SectionRule.gradient);
      },
    );

    test('ohne Höhenwerte: eben gerechnet, aber nur vorläufig', () {
      final s = single(selectSections(steady(600, altitude: (s, m) => null)));
      expect(s.status, SectionStatus.provisional);
      expect(s.caveats, [SectionCaveat.noAltitude]);
      expect(s.gradient, 0);
      expect(s.gradientBasis, GradientBasis.noAltitude);
      expect(s.isUsable, isTrue);
    });

    test('Höhe ohne gemeldete Vertikalgenauigkeit: eben, nur vorläufig', () {
      final s = single(
        selectSections(
          steady(600, altitude: slope(0.05), verticalAccuracy: null),
        ),
      );
      expect(s.status, SectionStatus.provisional);
      expect(s.caveats, [SectionCaveat.noVerticalAccuracy]);
      expect(s.gradient, 0);
    });
  });

  group('PAR-028 / PAR-029 Intensität', () {
    // HFmax 190, HFRuhe 60: r = 0,55 bei 131,5 bpm, 0,85 bei 170,5 bpm.
    test('r ≥ 0,55: 132 bpm (0,554) zählt, 131 bpm (0,546) nicht', () {
      expectUsable(selectSections(steady(600, bpm: (s) => 132)));
      expectOnly(
        selectSections(steady(600, bpm: (s) => 131)),
        SectionRule.intensityLow,
      );
    });

    test('r ≤ 0,85: 170 bpm (0,846) zählt, 171 bpm (0,854) nicht', () {
      expectUsable(selectSections(steady(600, bpm: (s) => 170)));
      expectOnly(
        selectSections(steady(600, bpm: (s) => 171)),
        SectionRule.intensityHigh,
      );
    });

    test('Basis unbrauchbar: eigener Grund, kein r (PAR-018, PAR-019)', () {
      final s = single(
        selectSections(
          steady(600),
          basis: const HeartRateBasis(maxBpm: 190, restingBpm: 150),
        ),
      );
      expect(rulesOf(s), {SectionRule.heartRateBasisUnavailable});
      expect(
        s.violations.single.basisReason,
        UnavailableReason.reserveTooSmall,
      );
      expect(s.relativeLoad, isNull);
    });

    test('fehlender Ruhepuls: Grund missingRestingHeartRate', () {
      final s = single(
        selectSections(steady(600), basis: const HeartRateBasis(maxBpm: 190)),
      );
      expect(
        s.violations.single.basisReason,
        UnavailableReason.missingRestingHeartRate,
      );
    });

    test(
      'kein Puls: Grund heartRateUnavailable, Mittel und r fehlen (nicht 0)',
      () {
        final s = single(selectSections(steady(600, bpm: (s) => null)));
        expect(s.violates(SectionRule.heartRateUnavailable), isTrue);
        expect(s.violates(SectionRule.heartRateGaps), isTrue);
        expect(s.meanHeartRate, isNull);
        expect(s.relativeLoad, isNull);
        expect(s.isUsable, isFalse);
      },
    );
  });

  group('PAR-030 / PAR-031 Mindestgeschwindigkeit (FR-0070, FR-0074)', () {
    // 134 m/min = 2,2333 m/s, 120 m/min = 2 m/s.
    test('über 134 m/min (134,5): voll bewertet', () {
      final s = single(selectSections(steady(600, speed: (s) => 134.5 / 60)));
      expect(s.status, SectionStatus.eligible);
      expect(s.speedMetersPerMinute, closeTo(134.5, 1e-6));
    });

    test('knapp unter 134 m/min (133,5): nur vorläufig', () {
      final s = single(selectSections(steady(600, speed: (s) => 133.5 / 60)));
      expect(s.status, SectionStatus.provisional);
      expect(s.caveats, [SectionCaveat.limitedSpeed]);
      expect(s.isProvisional, isTrue);
      expect(s.isUsable, isTrue);
    });

    test('knapp über 120 m/min (120,5): vorläufig', () {
      final s = single(selectSections(steady(600, speed: (s) => 120.5 / 60)));
      expect(s.status, SectionStatus.provisional);
      expect(s.caveats, [SectionCaveat.limitedSpeed]);
    });

    test('knapp unter 120 m/min (119,5): kein Abschnitt, Grund tooSlow', () {
      final r = selectSections(steady(600, speed: (s) => 119.5 / 60));
      expectOnly(r, SectionRule.tooSlow);
      expect(r.sections.single.violations.single.limit, 120);
      expect(r.usable, isEmpty);
    });

    test('reines Gehen (1,4 m/s = 84 m/min) liefert keinen Abschnitt', () {
      final r = selectSections(steady(900, speed: (s) => 1.4));
      expect(r.usable, isEmpty);
      expect(r.sections, isNotEmpty);
      expect(r.sections.every((s) => s.violates(SectionRule.tooSlow)), isTrue);
    });
  });

  group('Mehrere Verstöße und fehlende Daten', () {
    test('alle verletzten Regeln werden gemeldet, nicht nur die erste', () {
      final s = single(
        selectSections(
          steady(600, speed: (s) => 1.4, bpm: (s) => 120, accuracy: (s) => 12),
        ),
      );
      expect(
        rulesOf(s),
        containsAll([
          SectionRule.tooSlow,
          SectionRule.intensityLow,
          SectionRule.gpsMedianAccuracy,
        ]),
      );
    });

    test('ohne Positionen: Grund speedUnavailable, Kennzahlen fehlen', () {
      final r = selectSections(
        SelScenario(
          seconds: 780,
          dropPositions: {for (var s = 0; s <= 780; s++) s},
        ),
      );
      final s = single(r);
      expect(s.violates(SectionRule.speedUnavailable), isTrue);
      expect(s.speedMetersPerMinute, isNull);
      expect(s.distanceMeters, isNull);
      expect(s.isUsable, isFalse);
    });

    test(
      'Grenzen stehen im Parametersatz (FR-0075): abweichender Satz wirkt',
      () {
        const strict = FitnessParameters(
          parameterVersion: currentParameterVersion,
          sectionSelection: SectionSelectionParameters(intensityMin: 0.7),
        );
        final r = selectSections(steady(600), parameters: strict);
        expectOnly(r, SectionRule.intensityLow);
        expect(
          const FitnessParameters.v3()
              .copyWith(sectionSelection: const SectionSelectionParameters())
              .sectionSelection
              .intensityMax,
          0.85,
        );
      },
    );

    test('Startwerte nach PAR-020 bis PAR-031', () {
      const p = SectionSelectionParameters();
      expect(p.minDuration, const Duration(minutes: 5));
      expect(p.splitLength, const Duration(minutes: 10));
      expect(p.paceMaxVariation, 0.05);
      expect(p.paceMaxHalfDifference, 0.03);
      expect(p.heartRateMaxHalfDifferenceBpm, 5);
      expect(p.lateHalfWeightFrom, const Duration(minutes: 30));
      expect(p.lateExcludeFrom, const Duration(minutes: 60));
      expect(p.fullWeight, 1);
      expect(p.lateWeight, 0.5);
      expect(p.gpsMaxMedianAccuracyMeters, 10);
      expect(p.gpsShareAccuracyMeters, 15);
      expect(p.gpsMinShare, 0.9);
      expect(p.gradientMin, -0.02);
      expect(p.gradientMax, 0.03);
      expect(p.gradientUseFrom, 0.01);
      expect(p.gradientAltitudeFactor, 2);
      expect(p.intensityMin, 0.55);
      expect(p.intensityMax, 0.85);
      expect(p.fullSpeedMetersPerMinute, 134);
      expect(p.limitedSpeedMetersPerMinute, 120);
    });
  });

  group('Gleichheit an den Grenzen (Review A, Muss 1)', () {
    // Die Grenze wird genau auf den gemessenen Wert gesetzt; die Spezifikation
    // legt für jede Regel fest, ob die Grenze selbst noch gilt.
    SectionSelection run(SelScenario sc, SectionSelectionParameters p) =>
        selectSections(
          sc,
          parameters: FitnessParameters(
            parameterVersion: currentParameterVersion,
            sectionSelection: p,
          ),
        );

    /// Messwert einer Regel: eine unmögliche Grenze lässt sie verletzen, der
    /// Verstoß trägt den Wert.
    double measured(
      SelScenario sc,
      SectionRule rule,
      SectionSelectionParameters strict,
    ) {
      final v = single(run(sc, strict)).violations
          .firstWhere((v) => v.rule == rule);
      return v.value!;
    }

    double? Function(int, double) slope(double g) =>
        (s, m) => 100 + g * m;

    test('PAR-022 Variationskoeffizient gleich der Grenze: gültig', () {
      final sc = steady(600, speed: alternating(0.04));
      final cv = measured(
        sc,
        SectionRule.paceVariation,
        const SectionSelectionParameters(paceMaxVariation: 0),
      );
      expect(cv, inInclusiveRange(0.03, 0.05));
      expectUsable(run(sc, SectionSelectionParameters(paceMaxVariation: cv)));
    });

    test('PAR-022 Hälftenunterschied gleich der Grenze: gültig', () {
      final sc = steady(600, speed: stepSpeed(480, 3.0, 3.0 * 1.03));
      final d = measured(
        sc,
        SectionRule.paceHalves,
        const SectionSelectionParameters(paceMaxHalfDifference: 0),
      );
      expect(d, inInclusiveRange(0.02, 0.04));
      expectUsable(
        run(sc, SectionSelectionParameters(paceMaxHalfDifference: d)),
      );
    });

    test('PAR-023 Pulsunterschied der Hälften gleich der Grenze: gültig', () {
      final sc = steady(600, bpm: (s) => s <= 480 ? 148 : 153);
      final d = measured(
        sc,
        SectionRule.heartRateHalves,
        const SectionSelectionParameters(heartRateMaxHalfDifferenceBpm: 0),
      );
      expect(d, inInclusiveRange(4, 6));
      expectUsable(
        run(sc, SectionSelectionParameters(heartRateMaxHalfDifferenceBpm: d)),
      );
    });

    test('PAR-025 Anteil der Punkte ≤ 15 m gleich der Grenze: gültig', () {
      final sc = steady(600, accuracy: (s) => (s >= 200 && s < 260) ? 20 : 5);
      final share = measured(
        sc,
        SectionRule.gpsAccuracyShare,
        const SectionSelectionParameters(gpsMinShare: 1.1),
      );
      expect(share, inInclusiveRange(0.89, 0.91));
      expectUsable(run(sc, SectionSelectionParameters(gpsMinShare: share)));
    });

    test('PAR-026 Steigung gleich +3 % und gleich -2 %: gültig', () {
      final up = single(
        run(
          steady(600, altitude: slope(0.029)),
          const SectionSelectionParameters(),
        ),
      );
      expect(up.gradientBasis, GradientBasis.measured);
      expectUsable(
        run(
          steady(600, altitude: slope(0.029)),
          SectionSelectionParameters(gradientMax: up.gradient),
        ),
      );
      final down = single(
        run(
          steady(600, altitude: slope(-0.019)),
          const SectionSelectionParameters(),
        ),
      );
      expect(down.gradientBasis, GradientBasis.measured);
      expectUsable(
        run(
          steady(600, altitude: slope(-0.019)),
          SectionSelectionParameters(gradientMin: down.gradient),
        ),
      );
    });

    test('PAR-027 |G| gleich 1 %: G zählt', () {
      final sc = steady(600, altitude: slope(0.011));
      final g = single(run(sc, const SectionSelectionParameters())).gradient;
      expect(g, closeTo(0.011, 1e-6));
      final s = single(run(sc, SectionSelectionParameters(gradientUseFrom: g)));
      expect(s.gradientBasis, GradientBasis.measured);
      expect(s.gradient, g);
    });

    test('PAR-027 Δh gleich 2 · Vertikalgenauigkeit: G zählt', () {
      final sc = steady(600, altitude: slope(0.02), verticalAccuracy: 2);
      final heights = [
        for (final a in buildRun(sc).altitude.smoothed)
          if (!a.time.isBefore(selAt(180)) && !a.time.isAfter(selAt(780)))
            a.meters,
      ];
      final rise = (heights.last - heights.first).abs();
      expect(rise, greaterThan(30));
      // Vertikalgenauigkeit 2 m: Faktor rise / 2 ist genau (Zweierpotenz).
      final s = single(
        run(sc, SectionSelectionParameters(gradientAltitudeFactor: rise / 2)),
      );
      expect(s.gradientBasis, GradientBasis.measured);
      expect(s.gradient, closeTo(0.02, 1e-3));
      // Gegenprobe: knapp größerer Faktor, dann gilt es als Rauschen.
      final noisy = single(
        run(
          sc,
          SectionSelectionParameters(gradientAltitudeFactor: rise / 2 * 1.001),
        ),
      );
      expect(noisy.gradientBasis, GradientBasis.belowThreshold);
    });

    test('PAR-028 r gleich 0,55 und PAR-029 r gleich 0,85: gültig', () {
      final low = single(
        run(steady(600, bpm: (s) => 132), const SectionSelectionParameters()),
      );
      expectUsable(
        run(
          steady(600, bpm: (s) => 132),
          SectionSelectionParameters(intensityMin: low.relativeLoad!),
        ),
      );
      final high = single(
        run(steady(600, bpm: (s) => 170), const SectionSelectionParameters()),
      );
      expectUsable(
        run(
          steady(600, bpm: (s) => 170),
          SectionSelectionParameters(intensityMax: high.relativeLoad!),
        ),
      );
    });

    test('PAR-030 Tempo gleich 134 m/min: voll bewertet', () {
      final sc = steady(600, speed: (s) => 2.2);
      final v = single(run(sc, const SectionSelectionParameters()))
          .speedMetersPerMinute!;
      final s = single(
        run(sc, SectionSelectionParameters(fullSpeedMetersPerMinute: v)),
      );
      expect(s.status, SectionStatus.eligible);
      expect(s.caveats, isEmpty);
    });

    test('PAR-031 Tempo gleich 120 m/min: vorläufig, nicht abgelehnt', () {
      final sc = steady(600, speed: (s) => 2.1);
      final v = single(run(sc, const SectionSelectionParameters()))
          .speedMetersPerMinute!;
      final s = single(
        run(sc, SectionSelectionParameters(limitedSpeedMetersPerMinute: v)),
      );
      expect(s.status, SectionStatus.provisional);
      expect(s.caveats, [SectionCaveat.limitedSpeed]);
    });
  });

  group('Messausreißer und Randfälle (Review A)', () {
    // Zwei Serien zu je 8 s (unter der Einzellücke von 10 s): Ungefiltert läge
    // der 30-s-Median in der Zeit mit 16 von 30 Werten bei 250 bpm.
    test(
      'FR-0073 Regel 6: unplausibler Puls (250 bpm, PAR-007) zählt nicht',
      () {
        final clean = single(selectSections(steady(600)));
        final noisy = single(
          selectSections(
            steady(
              600,
              bpm: (s) =>
                  (s >= 400 && s < 408) || (s >= 412 && s < 420) ? 250 : 150,
            ),
          ),
        );
        expect(noisy.violations, isEmpty, reason: '${noisy.violations}');
        expect(noisy.status, SectionStatus.eligible);
        expect(noisy.meanHeartRate, clean.meanHeartRate);
        expect(noisy.relativeLoad, clean.relativeLoad);
      },
    );

    // Der 30-s-Median hält einzelne Sprünge ohnehin heraus; dieser Test belegt
    // das Ergebnis, nicht die Wirkung von PAR-009 (dort greift er nicht).
    test(
      'FR-0073 Regel 6: kurzer Pulssprung (90 bpm, PAR-009) ändert nichts',
      () {
        final clean = single(selectSections(steady(600)));
        final noisy = single(
          selectSections(
            steady(600, bpm: (s) => s >= 400 && s < 403 ? 90 : 150),
          ),
        );
        expect(noisy.violations, isEmpty, reason: '${noisy.violations}');
        expect(noisy.meanHeartRate, clean.meanHeartRate);
      },
    );

    test('FR-0073 Regel 6: GPS-Sprung (PAR-003) verschiebt Tempo und Strecke nicht', () {
      final clean = single(selectSections(steady(600)));
      // 50 m in 1 s, danach zurück; ein zweiter Sprung nach hinten.
      final noisy = single(
        selectSections(steady(600, jumps: {450: 50, 600: -60})),
      );
      expect(noisy.violations, isEmpty, reason: '${noisy.violations}');
      expect(
        noisy.speedMetersPerMinute,
        closeTo(clean.speedMetersPerMinute!, 1e-6),
      );
      expect(noisy.distanceMeters, closeTo(clean.distanceMeters!, 1e-6));
    });

    test('PAR-027 größte Vertikalgenauigkeit: ein schlechter Punkt genügt', () {
      // 300 s bei 2,25 m/s = 675 m; 3,5 % = 23,6 m; 2 · 15 m = 30 m.
      final s = single(
        selectSections(
          steady(
            300,
            speed: (s) => 2.25,
            altitude: (s, m) => 100 + 0.035 * m,
            verticalAccuracyAt: (s) => s == 300 ? 15 : 3,
          ),
        ),
      );
      expect(s.gradient, 0);
      expect(s.gradientBasis, GradientBasis.belowThreshold);
      expect(s.isUsable, isTrue);
    });

    test('PAR-025 Punkte ohne Genauigkeit zählen beim Anteil nicht', () {
      // 20 % ohne Angabe, die übrigen alle ≤ 5 m: Anteil 80 % < 90 %.
      final r = selectSections(
        steady(600, accuracy: (s) => s % 5 == 0 ? null : 5),
      );
      expectOnly(r, SectionRule.gpsAccuracyShare);
      expect(r.sections.single.violations.single.value, closeTo(0.8, 0.01));
    });

    test('PAR-010 beide verletzten Bedingungen werden gemeldet', () {
      // 12 s Einzellücke plus 30 verstreute Sekunden: Anteil über 5 %.
      final gone = {
        for (var s = 300; s < 312; s++) s,
        for (var k = 0; k < 30; k++) 400 + 5 * k,
      };
      final r = selectSections(
        steady(600, bpm: (s) => gone.contains(s) ? null : 150),
      );
      final v = single(r).violations
          .where((v) => v.rule == SectionRule.heartRateGaps);
      expect(v.map((v) => v.limit).toSet(), {0.05, 10});
      expect(v, hasLength(2));
    });
  });
}
