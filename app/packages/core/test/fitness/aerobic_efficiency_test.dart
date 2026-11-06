import 'package:core/core.dart';
import 'package:test/test.dart';

import 'section_support.dart';

const _eff = MedianAerobicEfficiency();
const _p = FitnessParameters.v4();
final _now = DateTime.utc(2030, 6, 1, 12);

EvaluatedSection sec({
  double? speed = 150,
  double? r = 0.7,
  double gradient = 0,
  Duration length = const Duration(minutes: 10),
  List<SectionRule> rules = const [],
  List<SectionCaveat> caveats = const [],
  DateTime? from,
}) {
  final f = from ?? DateTime.utc(2030, 5, 1);
  return EvaluatedSection(
    from: f,
    to: f.add(length),
    status: rules.isEmpty ? SectionStatus.eligible : SectionStatus.rejected,
    violations: [for (final x in rules) SectionViolation(x)],
    caveats: caveats,
    weight: 1,
    speedMetersPerMinute: speed,
    meanHeartRate: 150,
    relativeLoad: r,
    gradient: gradient,
    gradientBasis: GradientBasis.measured,
    distanceMeters: (speed ?? 0) * length.inMinutes,
  );
}

EfficiencyRun runOf(
  List<EvaluatedSection> sections, {
  Duration ago = Duration.zero,
}) => EfficiencyRun(
  endedAt: _now.subtract(ago),
  selection: SectionSelection(
    parameterVersion: _p.parameterVersion,
    basis: selBasis,
    sections: sections,
    excluded: const [],
  ),
);

/// [n] gleiche Abschnitte, verteilt auf [runs] Läufe, [days] Tage zurück.
List<EfficiencyRun> window(
  int n,
  int runs, {
  int days = 1,
  double speed = 150,
  double gradient = 0,
  Duration length = const Duration(minutes: 10),
}) => [
  for (var i = 0; i < runs; i++)
    runOf([
      for (var k = 0; k < n; k++)
        if (k % runs == i)
          sec(speed: speed, gradient: gradient, length: length),
    ], ago: Duration(days: days, hours: i)),
];

AerobicEfficiencyResult compute(List<EfficiencyRun> runs) =>
    _eff.compute(runs: runs, p: _p, now: _now);

/// Aktuelles Fenster aus [cur] und Vergleichsfenster aus [ref].
AerobicEfficiencyResult both(
  List<EfficiencyRun> cur,
  List<EfficiencyRun> ref,
) => compute([...cur, ...ref]);

List<EfficiencyRun> ref(int n, int runs, {double gradient = 0}) =>
    window(n, runs, days: 40, gradient: gradient);
List<EfficiencyRun> cur(int n, int runs, {double gradient = 0}) =>
    window(n, runs, days: 5, gradient: gradient);

void main() {
  group('FR-0087 Formel und Median (FR-0085)', () {
    test('Referenz aus testing.md: 9,0 auf 9,5 km/h = 5,56 %', () {
      final r = both(
        window(3, 2, days: 5, speed: 9500 / 60),
        window(3, 2, days: 40, speed: 9000 / 60),
      );
      expect(r.change.value, closeTo(5.56, 0.005));
      expect(r.change.value!.toStringAsFixed(1), '5.6');
      expect(r.current.medianSpeed, closeTo(9500 / 60, 1e-9));
    });

    test('Median statt Mittelwert, ungewichtet (ungerade Anzahl)', () {
      final r = both([
        runOf([
          sec(speed: 150),
          sec(speed: 150, length: const Duration(minutes: 5)),
        ], ago: const Duration(days: 2)),
        runOf([sec(speed: 600)], ago: const Duration(days: 3)),
      ], ref(3, 2));
      expect(r.current.medianSpeed, 150); // Mittel wäre 300, gewichtet 400
    });

    test('gerade Anzahl: Mitte der beiden mittleren', () {
      expect(MedianAerobicEfficiency.median([100, 200, 140, 180]), 160);
      expect(MedianAerobicEfficiency.median([5]), 5);
    });

    test('Verschlechterung ergibt negativen Wert', () {
      final r = both(
        window(3, 2, days: 5, speed: 135),
        window(3, 2, days: 40, speed: 150),
      );
      expect(r.change.value, closeTo(-10, 1e-9));
    });
  });

  group('Eignung (PAR-044, PAR-045, OQ-0036)', () {
    bool ok(EvaluatedSection s) =>
        MedianAerobicEfficiency.isEligible(s, _p.aerobicEfficiency);

    test('r: 0,65 und 0,75 drin, knapp daneben draußen', () {
      expect(ok(sec(r: 0.65)), isTrue);
      expect(ok(sec(r: 0.75)), isTrue);
      expect(ok(sec(r: 0.6499)), isFalse);
      expect(ok(sec(r: 0.7501)), isFalse);
    });

    test('Steigung: Betrag höchstens 2 %', () {
      expect(ok(sec(gradient: 0.02)), isTrue);
      expect(ok(sec(gradient: -0.02)), isTrue);
      expect(ok(sec(gradient: 0.0201)), isFalse);
      expect(ok(sec(gradient: -0.0201)), isFalse);
    });

    test(
      'ersetzte Regeln der VO2max-Auswahl gelten nicht (PAR-030, 026, 028)',
      () {
        expect(
          ok(sec(rules: [SectionRule.tooSlow, SectionRule.gradient])),
          isTrue,
        );
        expect(ok(sec(rules: [SectionRule.intensityLow])), isTrue);
        expect(ok(sec(speed: 90, rules: [SectionRule.tooSlow])), isTrue);
      },
    );

    test('jede andere verletzte Regel schließt aus', () {
      for (final rule in SectionRule.values) {
        if (MedianAerobicEfficiency.replacedRules.contains(rule)) continue;
        expect(ok(sec(rules: [rule])), isFalse, reason: rule.name);
      }
      expect(
        ok(sec(rules: [SectionRule.lateRun, SectionRule.tooSlow])),
        isFalse,
      );
    });

    test('ohne Tempo oder r nie zugelassen', () {
      expect(ok(sec(r: null)), isFalse);
      expect(ok(sec(speed: null)), isFalse);
    });

    test(
      'Einschränkungen: nur die ausdrücklich ignorierten (PAR-031, 027)',
      () {
        for (final c in SectionCaveat.values) {
          expect(
            ok(sec(caveats: [c])),
            MedianAerobicEfficiency.ignoredCaveats.contains(c),
            reason: c.name,
          );
        }
        // Nicht ignorierte Einschränkungen schließen aus.
        for (final c in SectionCaveat.values) {
          expect(
            MedianAerobicEfficiency.isEligible(
              sec(caveats: [c]),
              _p.aerobicEfficiency,
              ignored: const {},
            ),
            isFalse,
            reason: c.name,
          );
        }
        // Neue Einschränkungen in Teil A erzwingen hier eine Entscheidung.
        expect(
          MedianAerobicEfficiency.ignoredCaveats,
          unorderedEquals(SectionCaveat.values),
        );
      },
    );

    test('Abschnitt mit Tempo null fließt nicht in den Median ein', () {
      final r = both([
        ...cur(3, 2),
        runOf([sec(speed: null)], ago: const Duration(days: 4)),
      ], ref(3, 2));
      expect(r.current.sections, hasLength(3));
      expect(r.current.medianSpeed, 150);
    });

    test('unzulässige Abschnitte fließen nicht in den Median ein', () {
      final r = both([
        ...cur(3, 2),
        runOf([
          sec(speed: 1000, r: 0.8),
          sec(speed: 1000, gradient: 0.03),
        ], ago: const Duration(days: 4)),
      ], ref(3, 2));
      expect(r.current.sections, hasLength(3));
      expect(r.current.medianSpeed, 150);
    });
  });

  group('Fenster (OQ-0036)', () {
    EfficiencyRun at(Duration ago) => runOf([sec(), sec(), sec()], ago: ago);

    test('now lokal: gleiches Ergebnis wie UTC, Metadaten in UTC', () {
      final runs = [...cur(3, 2), ...ref(3, 2)];
      final u = _eff.compute(runs: runs, p: _p, now: _now);
      final l = _eff.compute(runs: runs, p: _p, now: _now.toLocal());
      expect(l.change.value, u.change.value);
      expect(l.change.metadata.calculatedAt.isUtc, isTrue);
      expect(l.current.from.isUtc, isTrue);
      expect(l.current.from, u.current.from);
    });

    test('doppelt übergebener Lauf zählt doppelt (dokumentiert)', () {
      final one = runOf([sec(), sec(), sec()], ago: const Duration(days: 2));
      final r = both([one, one], ref(3, 2));
      expect(r.current.sections, hasLength(6));
      expect(r.current.runCount, 2);
    });

    test('Grenzen: 28 Tage inklusive aktuell, 56 Tage inklusive Vergleich', () {
      final r = compute([
        at(Duration.zero),
        at(const Duration(days: 28)), // aktuell
        at(const Duration(days: 28, seconds: 1)), // Vergleich
        at(const Duration(days: 56)), // Vergleich
        at(const Duration(days: 56, seconds: 1)), // zu alt
        at(const Duration(seconds: -1)), // nach „jetzt“
      ]);
      expect(r.current.runCount, 2);
      expect(r.reference.runCount, 2);
      expect(r.change.metadata.usableMeasurements, 12);
    });

    test('Vergleichsfenster sind getrennt und liegen vor dem aktuellen', () {
      final r = both(
        window(3, 2, days: 5, speed: 160),
        window(3, 2, days: 40, speed: 150),
      );
      expect(r.current.medianSpeed, 160);
      expect(r.reference.medianSpeed, 150);
      expect(r.reference.to, r.current.from);
    });
  });

  group('Mindestmenge (PAR-046)', () {
    test('genau 3 Abschnitte, 2 Läufe, 30 min reichen', () {
      final r = both(cur(3, 2), ref(3, 2));
      expect(r.change.metadata.tier, QualityTier.preliminary);
      expect(r.change.value, isNotNull);
    });

    test('2 Abschnitte: nicht bestimmbar, Grund aktuelles Fenster', () {
      final r = both(
        window(2, 2, days: 5, length: const Duration(minutes: 15)),
        ref(3, 2),
      );
      expect(r.change.metadata.tier, QualityTier.notDeterminable);
      expect(r.change.value, isNull);
      expect(r.change.reason, UnavailableReason.currentWindowTooSmall);
    });

    test('1 Lauf: nicht bestimmbar', () {
      final r = both(cur(3, 1), ref(3, 2));
      expect(r.change.reason, UnavailableReason.currentWindowTooSmall);
    });

    test('29:59 min: nicht bestimmbar, 30:00 min bestimmbar', () {
      List<EfficiencyRun> mins(Duration last) => [
        runOf([sec(), sec()], ago: const Duration(days: 3)),
        runOf([sec(length: last)], ago: const Duration(days: 4)),
      ];
      expect(
        both(
          mins(const Duration(minutes: 9, seconds: 59)),
          ref(3, 2),
        ).change.reason,
        UnavailableReason.currentWindowTooSmall,
      );
      expect(
        both(mins(const Duration(minutes: 10)), ref(3, 2)).change.value,
        isNotNull,
      );
    });

    test('Vergleichsfenster zu klein: eigener Grund, gilt je Fenster', () {
      expect(
        both(cur(3, 2), ref(2, 2)).change.reason,
        UnavailableReason.referenceWindowTooSmall,
      );
      expect(
        both(cur(3, 2), ref(3, 1)).change.reason,
        UnavailableReason.referenceWindowTooSmall,
      );
      expect(
        compute(const []).change.reason,
        UnavailableReason.currentWindowTooSmall,
      );
    });

    test('Läufe ohne zugelassenen Abschnitt zählen nicht als Lauf', () {
      final r = both([
        runOf([sec(), sec(), sec()], ago: const Duration(days: 2)),
        runOf([sec(r: 0.5)], ago: const Duration(days: 3)),
      ], ref(3, 2));
      expect(r.current.runCount, 1);
      expect(r.change.reason, UnavailableReason.currentWindowTooSmall);
    });
  });

  group('Stufe (PAR-047)', () {
    QualityTier? tier(List<EfficiencyRun> c, List<EfficiencyRun> rf) =>
        both(c, rf).change.metadata.tier;

    test('ausreichend ab 6 Abschnitten aus 3 Läufen, knapp darunter nicht', () {
      expect(tier(cur(6, 3), ref(6, 3)), QualityTier.sufficient);
      expect(tier(cur(5, 3), ref(6, 3)), QualityTier.preliminary);
      expect(tier(cur(6, 2), ref(6, 3)), QualityTier.preliminary);
    });

    test('gut ab 10 Abschnitten aus 4 Läufen, knapp darunter nicht', () {
      expect(tier(cur(10, 4), ref(10, 4)), QualityTier.good);
      expect(tier(cur(9, 4), ref(10, 4)), QualityTier.sufficient);
      expect(tier(cur(10, 3), ref(10, 4)), QualityTier.sufficient);
    });

    test('das schwächere Fenster entscheidet', () {
      expect(tier(cur(10, 4), ref(6, 3)), QualityTier.sufficient);
      expect(tier(cur(6, 3), ref(10, 4)), QualityTier.sufficient);
      expect(tier(cur(10, 4), ref(3, 2)), QualityTier.preliminary);
    });

    test(
      'Steigungsregel: > 1 Prozentpunkt Unterschied höchstens vorläufig',
      () {
        final even = both(cur(10, 4), ref(10, 4, gradient: 0.01));
        expect(even.slopeCapped, isFalse); // genau 1 Prozentpunkt
        expect(even.change.metadata.tier, QualityTier.good);

        final over = both(cur(10, 4, gradient: 0.0101), ref(10, 4));
        expect(over.slopeCapped, isTrue);
        expect(over.change.metadata.tier, QualityTier.preliminary);
        expect(over.change.value, isNotNull); // Wert bleibt

        final neg = both(cur(10, 4, gradient: -0.0101), ref(10, 4));
        expect(neg.change.metadata.tier, QualityTier.preliminary);

        final both2 = both(
          cur(6, 3, gradient: 0.02),
          ref(6, 3, gradient: 0.0099),
        );
        expect(both2.change.metadata.tier, QualityTier.preliminary);
      },
    );

    test('Steigungsregel: Gleichheit an der Grenze (binär exakte Werte)', () {
      // 1/64 ist exakt darstellbar; so trifft der Unterschied die Grenze genau.
      const exact = 0.015625;
      AerobicEfficiencyResult at(double limit) => _eff.compute(
        runs: [
          ...cur(10, 4),
          ...ref(10, 4, gradient: exact),
        ],
        p: _p.copyWith(
          aerobicEfficiency: AerobicEfficiencyParameters(
            maxGradientDifference: limit,
          ),
        ),
        now: _now,
      );
      expect(at(exact).slopeCapped, isFalse);
      expect(at(exact).change.metadata.tier, QualityTier.good);
      expect(at(exact - 1e-9).slopeCapped, isTrue);
    });

    test('Steigungsregel nutzt die mittlere Steigung des Fensters', () {
      // Mittel 0,0 und 0,02 -> 0,01 Unterschied, nicht größer
      final c = [
        runOf([
          sec(gradient: 0.02),
          sec(gradient: -0.02),
          sec(),
        ], ago: const Duration(days: 2)),
        runOf([
          sec(gradient: 0.02),
          sec(gradient: -0.02),
          sec(),
        ], ago: const Duration(days: 3)),
      ];
      final r = both(c, ref(3, 2, gradient: 0.02));
      expect(r.current.meanGradient, closeTo(0, 1e-12));
      expect(r.slopeCapped, isTrue);
    });
  });

  group('Metadaten, Variante, Parameter', () {
    test('Methode, Versionen, Kategorie, Zeitraum', () {
      final r = both(cur(3, 2), ref(3, 2));
      final m = r.change.metadata;
      expect(m.method, 'aerobic-efficiency-median');
      expect(m.methodVersion, 1);
      expect(m.parameterVersion, _p.parameterVersion);
      expect(m.calculatedAt, _now);
      expect(m.usableMeasurements, 6);
      expect(m.dataFrom, DateTime.utc(2030, 5, 1));
      expect(m.dataTo, DateTime.utc(2030, 5, 1, 0, 10));
      expect(_eff.category, AlgorithmCategory.heuristic);
      expect(
        AlgorithmRegistry.standard().active(aerobicEfficiencyFamily),
        isA<MedianAerobicEfficiency>(),
      );
    });

    test('nicht bestimmbar trägt dennoch Metadaten', () {
      final m = compute(const []).change.metadata;
      expect(m.tier, QualityTier.notDeterminable);
      expect(m.method, 'aerobic-efficiency-median');
      expect(m.usableMeasurements, 0);
    });

    test('abweichende Parameterversion wirft', () {
      final bad = EfficiencyRun(
        endedAt: _now,
        selection: SectionSelection(
          parameterVersion: 99,
          basis: selBasis,
          sections: const [],
          excluded: const [],
        ),
      );
      expect(() => compute([bad]), throwsArgumentError);
    });

    test('Grenzen kommen aus dem Parametersatz', () {
      final wide = _p.copyWith(
        aerobicEfficiency: const AerobicEfficiencyParameters(
          loadMin: 0.5,
          minSections: 1,
          minRuns: 1,
          minDuration: Duration(minutes: 1),
        ),
      );
      final r = _eff.compute(
        runs: [
          runOf([sec(r: 0.55)], ago: const Duration(days: 2)),
          runOf([sec(r: 0.55)], ago: const Duration(days: 40)),
        ],
        p: wide,
        now: _now,
      );
      expect(r.change.value, 0);
    });
  });

  group('Mit der Abschnittsauswahl aus Teil A', () {
    EfficiencyRun real(SelScenario sc, Duration ago) => EfficiencyRun(
      endedAt: _now.subtract(ago),
      selection: selectSections(sc),
    );

    test('Tempo unter 120 m/min und r zwischen 65 und 75 % zählen', () {
      // 1,6 m/s = 96 m/min: VO2max lehnt ab (PAR-031), Effizienz nicht.
      final sc = steady(900, speed: (s) => 1.6, bpm: (s) => 150);
      final sel = selectSections(sc);
      expect(sel.usable, isEmpty);
      expect(sel.sections, hasLength(2)); // 15 min -> 2 Abschnitte
      expect(
        sel.sections.every((x) => x.violates(SectionRule.tooSlow)),
        isTrue,
      );
      final r = both(
        [real(sc, const Duration(days: 2)), real(sc, const Duration(days: 3))],
        [
          real(sc, const Duration(days: 40)),
          real(sc, const Duration(days: 41)),
        ],
      );
      expect(r.current.sections, hasLength(4));
      expect(r.current.medianSpeed, closeTo(96, 1));
    });

    test('r = 0,615 (VO2max-tauglich) fällt aus der Effizienz heraus', () {
      final sc = steady(900, bpm: (s) => 140); // (140-60)/130
      expect(selectSections(sc).usable, isNotEmpty);
      final r = both([real(sc, const Duration(days: 2))], const []);
      expect(r.current.sections, isEmpty);
    });

    test('Tempo 125 m/min und r 0,7 (limitedSpeed) zählt mit (PAR-044)', () {
      // 125 m/min: über 120 (nicht abgelehnt), unter 150 -> Einschränkung.
      final sc = steady(900, speed: (s) => 125 / 60, bpm: (s) => 151);
      final sel = selectSections(sc);
      expect(sel.sections, isNotEmpty);
      expect(
        sel.sections.every(
          (x) =>
              x.isProvisional && x.caveats.contains(SectionCaveat.limitedSpeed),
        ),
        isTrue,
      );
      final r = both([
        real(sc, const Duration(days: 2)),
        real(sc, const Duration(days: 3)),
      ], const []);
      expect(r.current.sections, hasLength(2 * sel.sections.length));
      expect(r.current.medianSpeed, closeTo(125, 1));
    });

    test('Abschnitt ohne Höhe (noAltitude) zählt mit', () {
      final sc = steady(900, altitude: (s, m) => null, bpm: (s) => 151);
      final sel = selectSections(sc);
      expect(
        sel.sections.every((x) => x.caveats.contains(SectionCaveat.noAltitude)),
        isTrue,
      );
      final r = both([real(sc, const Duration(days: 2))], const []);
      expect(r.current.sections, hasLength(sel.sections.length));
      expect(r.current.sections, isNotEmpty);
    });

    test('Lauf über 60 min: Minute 30 bis 60 voll, ab Minute 60 nicht', () {
      // PAR-024: nach 30 min halbes Gewicht für VO2max, hier ungewichtet.
      final sc = steady(4000, bpm: (s) => 151); // 180 s Einschwingen + 4000 s
      final sel = selectSections(sc);
      final start = selT0;
      Duration at(EvaluatedSection x) => x.from.difference(start);
      final half = sel.sections.where((x) => x.weight == 0.5).toList();
      final late = sel.sections.where((x) => x.violates(SectionRule.lateRun));
      expect(half, isNotEmpty);
      expect(late, isNotEmpty);
      final r = both([real(sc, const Duration(days: 2))], const []);
      final used = r.current.sections.map((e) => e.section).toList();
      for (final x in used) {
        expect(at(x), lessThan(const Duration(minutes: 60)));
      }
      expect(used.where((x) => x.weight == 0.5), hasLength(half.length));
      expect(used.any((x) => x.violates(SectionRule.lateRun)), isFalse);
      expect(
        used,
        hasLength(
          sel.sections.where((x) => at(x) < const Duration(minutes: 60)).length,
        ),
      );
    });

    test('schlechtes GPS bleibt ausgeschlossen (PAR-025 gilt weiter)', () {
      final sc = steady(900, accuracy: (s) => 20);
      final r = both([real(sc, const Duration(days: 2))], const []);
      expect(r.current.sections, isEmpty);
    });
  });
}
