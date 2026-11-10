import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

const heart = HeartRateBasis(maxBpm: 190, restingBpm: 60);

IntensityInputs inp({
  double? refSeconds = 1500,
  double? refMeters = 5000,
  int? refAge = 10,
  int pause = 0,
  double? vo2 = 45,
  Vo2maxGrade? grade = Vo2maxGrade.good,
  HeartRateBasis? hr = heart,
  List<double>? bounds,
}) => IntensityInputs(
  referenceSeconds: refSeconds,
  referenceMeters: refMeters,
  referenceAgeDays: refAge,
  longestPauseSinceReferenceDays: pause,
  vo2max: vo2,
  vo2maxGrade: grade,
  heartRate: hr,
  zoneBounds: bounds,
);

IntensityInputs noRef({
  double? vo2 = 45,
  Vo2maxGrade? grade = Vo2maxGrade.good,
  HeartRateBasis? hr = heart,
}) => inp(
  refSeconds: null,
  refMeters: null,
  refAge: null,
  vo2: vo2,
  grade: grade,
  hr: hr,
);

SegmentTarget t(PlanUnitKind u, PlanSegmentKind s, IntensityInputs i) =>
    segmentTarget(unitKind: u, segment: s, inputs: i)!;

void main() {
  group('Rangfolge (PAR-100 bis PAR-105, FR-0153)', () {
    for (final (u, s) in [
      (PlanUnitKind.easy, PlanSegmentKind.easy),
      (PlanUnitKind.long, PlanSegmentKind.easy),
      (PlanUnitKind.tempo, PlanSegmentKind.tempo),
      (PlanUnitKind.progressive, PlanSegmentKind.endBlock),
    ]) {
      test('${u.name}/${s.name}: Referenz, VO2max, Zonen, RPE', () {
        // Tempo und lockere Läufe: VO2max 45 reicht für beide Paces.
        expect(t(u, s, inp()).basis, IntensityBasis.reference);
        expect(t(u, s, noRef()).basis, IntensityBasis.vo2max);
        expect(t(u, s, noRef(vo2: null)).basis, IntensityBasis.heartRateZones);
        expect(
          t(u, s, noRef(vo2: null, hr: null)).basis,
          IntensityBasis.effort,
        );
      });
    }

    test('Intervalle: Pace nur aus der Referenz, sonst RPE, nie Puls', () {
      final i = PlanUnitKind.intervals;
      final s = PlanSegmentKind.interval;
      expect(t(i, s, inp()).basis, IntensityBasis.reference);
      final lower = t(i, s, noRef());
      expect(lower.basis, IntensityBasis.effort);
      expect(lower.intensity.paceFastSecondsPerKm, isNull);
      expect(lower.hrMinBpm, isNull);
    });

    test('Beispiel 5 km in 25:00 (PAR-102, PAR-190), Alter unter 3 Wochen', () {
      final i = inp();
      final iv = t(PlanUnitKind.intervals, PlanSegmentKind.interval, i);
      expect(iv.intensity.paceFastSecondsPerKm, 291); // 4:51
      expect(iv.intensity.paceSlowSecondsPerKm, 309); // 5:09 (3 %)
      final tp = t(PlanUnitKind.tempo, PlanSegmentKind.tempo, i);
      expect(tp.intensity.paceFastSecondsPerKm, 315); // 5:15
      expect(tp.intensity.paceSlowSecondsPerKm, 337); // 5:37 (3 %)
      final ez = t(PlanUnitKind.easy, PlanSegmentKind.easy, i);
      expect(ez.intensity.paceFastSecondsPerKm, 360); // nicht schneller 6:00
      expect(ez.intensity.paceSlowSecondsPerKm, isNull);
      expect(ez.paceIsLimit, isTrue);
    });

    test('Bandbreite nach Alter der Referenz (PAR-101)', () {
      double? slow(int age) => t(
        PlanUnitKind.intervals,
        PlanSegmentKind.interval,
        inp(refAge: age),
      ).intensity.paceSlowSecondsPerKm;
      expect(slow(20), 309); // 3 %
      expect(slow(21), 318); // 6 %
      expect(slow(90), 318);
      expect(slow(91), 330); // 10 %
      expect(slow(182), 330);
      expect(slow(183), isNull); // älter: keine Pace, nächste Stufe
    });

    test('fehlende oder unbrauchbare Referenz fällt auf die nächste Stufe', () {
      final tempo = [PlanUnitKind.tempo, PlanSegmentKind.tempo];
      IntensityBasis b(IntensityInputs i) =>
          t(tempo[0] as PlanUnitKind, tempo[1] as PlanSegmentKind, i).basis;
      expect(b(inp(refAge: 183)), IntensityBasis.vo2max);
      expect(b(inp(refAge: null)), IntensityBasis.vo2max);
      expect(b(inp(pause: 56)), IntensityBasis.vo2max); // PAR-202
      expect(b(inp(pause: 55)), IntensityBasis.reference);
      expect(b(inp(refMeters: 2999)), IntensityBasis.vo2max);
      expect(b(inp(refSeconds: 0)), IntensityBasis.vo2max);
      expect(b(inp(refSeconds: double.nan)), IntensityBasis.vo2max);
    });

    test(
      'VO2max: Güte, Mindestgeschwindigkeit, Bandbreite (PAR-103, PAR-082)',
      () {
        final e = PlanUnitKind.easy;
        final s = PlanSegmentKind.easy;
        final good = t(e, s, noRef());
        expect(good.intensity.paceFastSecondsPerKm, 445); // 7:25
        expect(good.intensity.paceSlowSecondsPerKm, 472); // 6 %
        final suff = t(e, s, noRef(grade: Vo2maxGrade.sufficient));
        expect(suff.intensity.paceSlowSecondsPerKm, 503); // 13 %, 8:23
        // unzureichend: keine Pace (FR-0145)
        expect(
          t(e, s, noRef(grade: null)).basis,
          IntensityBasis.heartRateZones,
        );
        // Locker erst ab VO2max 44,7, Tempo ab 37,0
        expect(t(e, s, noRef(vo2: 44.6)).basis, IntensityBasis.heartRateZones);
        expect(t(e, s, noRef(vo2: 44.8)).basis, IntensityBasis.vo2max);
        final tp = PlanUnitKind.tempo;
        final ts = PlanSegmentKind.tempo;
        expect(
          t(tp, ts, noRef(vo2: 36.9)).basis,
          IntensityBasis.heartRateZones,
        );
        expect(t(tp, ts, noRef(vo2: 37.1)).basis, IntensityBasis.vo2max);
        final tpace = t(tp, ts, noRef(grade: Vo2maxGrade.sufficient));
        expect(tpace.intensity.paceFastSecondsPerKm, 361); // 6:01
        expect(tpace.intensity.paceSlowSecondsPerKm, 408); // 6:48
      },
    );

    test('Herzfrequenz: Zonen, Ruhepuls fehlt, PAR-111', () {
      final z = t(PlanUnitKind.easy, PlanSegmentKind.easy, noRef(vo2: null));
      expect((z.hrMinBpm, z.hrMaxBpm), (125, 151));
      final tp = t(PlanUnitKind.tempo, PlanSegmentKind.tempo, noRef(vo2: null));
      expect((tp.hrMinBpm, tp.hrMaxBpm), (158, 171));
      // Ruhepuls 70: Obergrenze 80 % HFmax (152) gilt statt 154
      final hi = t(
        PlanUnitKind.easy,
        PlanSegmentKind.easy,
        noRef(vo2: null, hr: const HeartRateBasis(maxBpm: 190, restingBpm: 70)),
      );
      expect(hi.hrMaxBpm, 152);
      // Ruhepuls fehlt: keine Zone (PAR-104)
      expect(
        t(
          PlanUnitKind.easy,
          PlanSegmentKind.easy,
          noRef(vo2: null, hr: const HeartRateBasis(maxBpm: 190)),
        ).basis,
        IntensityBasis.effort,
      );
      // Obergrenze unter Untergrenze: keine Zone
      expect(
        t(
          PlanUnitKind.easy,
          PlanSegmentKind.easy,
          noRef(
            vo2: null,
            hr: const HeartRateBasis(maxBpm: 190, restingBpm: 120),
          ),
        ).basis,
        IntensityBasis.effort,
      );
      // Altersformel: gekennzeichnet
      final est = t(
        PlanUnitKind.easy,
        PlanSegmentKind.easy,
        noRef(
          vo2: null,
          hr: const HeartRateBasis(
            maxBpm: 190,
            restingBpm: 60,
            maxIsEstimated: true,
          ),
        ),
      );
      expect(est.maxHrEstimated, isTrue);
      expect(z.maxHrEstimated, isFalse);
    });

    test('angepasste Zonengrenzen: maßgeblich ist die Zonennummer', () {
      final r = t(
        PlanUnitKind.easy,
        PlanSegmentKind.easy,
        noRef(vo2: null, hr: heart),
      );
      final custom = IntensityInputs(
        heartRate: heart,
        zoneBounds: const [0.4, 0.5, 0.6, 0.75, 0.9, 1.0],
      );
      final c = t(PlanUnitKind.easy, PlanSegmentKind.easy, custom);
      expect(c.hrMinBpm, 60 + 52); // Untergrenze Zone 1 = 0,4
      expect(c.hrMaxBpm, 60 + 78); // Obergrenze Zone 2 = 0,6 (unter 152)
      expect(c.hrMinBpm, isNot(r.hrMinBpm));
      expect(
        () => IntensityInputs(zoneBounds: const [0.5, 0.5, 0.7, 0.8, 0.9, 1]),
        throwsArgumentError,
      );
      expect(
        () => IntensityInputs(zoneBounds: const [0.5]),
        throwsArgumentError,
      );
    });
  });

  group('RPE und Sonderfälle', () {
    test('RPE je Typ (PAR-109 bis PAR-115)', () {
      (int?, int?) r(PlanUnitKind u, PlanSegmentKind s) {
        final i = t(u, s, inp()).intensity;
        return (i.rpeMin, i.rpeMax);
      }

      expect(r(PlanUnitKind.easy, PlanSegmentKind.easy), (2, 4));
      expect(r(PlanUnitKind.easy, PlanSegmentKind.warmUp), (2, 4));
      expect(r(PlanUnitKind.intervals, PlanSegmentKind.coolDown), (2, 4));
      expect(r(PlanUnitKind.long, PlanSegmentKind.easy), (3, 4));
      expect(r(PlanUnitKind.intervals, PlanSegmentKind.interval), (7, 8));
      expect(r(PlanUnitKind.intervals, PlanSegmentKind.recovery), (1, 3));
      expect(r(PlanUnitKind.tempo, PlanSegmentKind.tempo), (6, 7));
      expect(r(PlanUnitKind.progressive, PlanSegmentKind.endBlock), (5, 7));
      expect(r(PlanUnitKind.walkRun, PlanSegmentKind.easy), (1, 4));
    });

    test('Trabpause und Geh-Lauf: nur RPE, keine Pace, kein Puls', () {
      for (final x in [
        t(PlanUnitKind.intervals, PlanSegmentKind.recovery, inp()),
        t(PlanUnitKind.walkRun, PlanSegmentKind.easy, inp()),
      ]) {
        expect(x.basis, IntensityBasis.effort);
        expect(x.intensity.paceFastSecondsPerKm, isNull);
        expect(x.hrMinBpm, isNull);
        expect(x.estimated, isFalse);
      }
    });

    test('progressiver Lauf: erster Teil ohne Pace (PAR-114)', () {
      final first = t(PlanUnitKind.progressive, PlanSegmentKind.easy, inp());
      expect(first.intensity.paceFastSecondsPerKm, isNull);
      expect(first.basis, IntensityBasis.heartRateZones);
    });

    test('Ruhetag: keine Zielintensität (PAR-116)', () {
      expect(
        segmentTarget(
          unitKind: PlanUnitKind.rest,
          segment: PlanSegmentKind.easy,
          inputs: inp(),
        ),
        isNull,
      );
    });

    test('Grundlage: Codes, Schlüssel, Wortlaut (PAR-106)', () {
      expect({for (final b in IntensityBasis.values) b.code}.length, 4);
      expect(IntensityBasis.fromCode('vo2max'), IntensityBasis.vo2max);
      expect(IntensityBasis.fromCode('x'), isNull);
      expect(IntensityBasis.values.map((b) => b.germanText), [
        'aus deiner Referenzzeit',
        'aus deiner VO₂max-Schätzung',
        'aus deinen Herzfrequenzzonen',
        'nach Gefühl',
      ]);
      expect(
        IntensityBasis.values.every((b) => b.textKey.startsWith('planBasis')),
        isTrue,
      );
    });

    test('Methode und Version registriert', () {
      final all = AlgorithmRegistry.standard().allVariants;
      expect(
        all.any(
          (v) =>
              v.method == targetIntensityMethod &&
              v.methodVersion == targetIntensityMethodVersion,
        ),
        isTrue,
      );
    });
  });

  group('Eigenschaften', () {
    test('über viele Eingaben: RPE nie leer, Pace nie Einzelwert', () {
      final rnd = Random(21);
      var withPace = 0;
      for (var n = 0; n < 4000; n++) {
        final i = IntensityInputs(
          referenceSeconds: rnd.nextBool()
              ? 600 + rnd.nextDouble() * 20000
              : null,
          referenceMeters: rnd.nextBool()
              ? 1000 + rnd.nextDouble() * 42000
              : 5000,
          referenceAgeDays: rnd.nextInt(6) == 0 ? null : rnd.nextInt(260),
          longestPauseSinceReferenceDays: rnd.nextInt(90),
          vo2max: rnd.nextBool() ? 20 + rnd.nextDouble() * 50 : null,
          vo2maxGrade: [null, ...Vo2maxGrade.values][rnd.nextInt(3)],
          heartRate: rnd.nextBool()
              ? HeartRateBasis(
                  maxBpm: rnd.nextInt(5) == 0 ? null : 150 + rnd.nextInt(60),
                  restingBpm: rnd.nextInt(5) == 0 ? null : 35 + rnd.nextInt(80),
                )
              : null,
        );
        for (final u in PlanUnitKind.values) {
          for (final s in PlanSegmentKind.values) {
            final x = segmentTarget(unitKind: u, segment: s, inputs: i);
            if (u == PlanUnitKind.rest) {
              expect(x, isNull);
              continue;
            }
            final v = x!.intensity;
            expect(v.rpeMin, isNotNull);
            expect(v.rpeMax, isNotNull);
            expect(v.rpeMin! >= 1 && v.rpeMax! <= 10, isTrue);
            expect(v.rpeMin! <= v.rpeMax!, isTrue);
            expect(v.basisCode, x.basis.code);
            final fast = v.paceFastSecondsPerKm;
            final slow = v.paceSlowSecondsPerKm;
            if (fast == null) {
              expect(slow, isNull);
              expect(x.paceIsLimit, isFalse);
            } else {
              withPace++;
              expect(fast.isFinite && fast > 0, isTrue);
              if (slow == null) {
                expect(x.paceIsLimit, isTrue); // nur lockere Grenze
                expect(x.basis, IntensityBasis.reference);
              } else {
                expect(slow > fast, isTrue, reason: 'Bereich $fast-$slow');
                expect(x.paceIsLimit, isFalse);
              }
              expect(
                x.basis == IntensityBasis.reference ||
                    x.basis == IntensityBasis.vo2max,
                isTrue,
              );
              expect(x.hrMinBpm, isNull);
            }
            if (x.basis == IntensityBasis.heartRateZones) {
              expect(x.hrMinBpm! < x.hrMaxBpm!, isTrue);
              expect(fast, isNull);
            } else {
              expect(x.hrMinBpm, isNull);
            }
            expect(x.estimated, x.basis != IntensityBasis.effort);
          }
        }
      }
      expect(withPace, greaterThan(1000));
    });

    test('Einzelwert nur als Grenze bei lockeren Läufen', () {
      final rnd = Random(7);
      for (var n = 0; n < 500; n++) {
        final i = inp(
          refSeconds: 900 + rnd.nextDouble() * 9000,
          refMeters: 3000 + rnd.nextDouble() * 30000,
          refAge: rnd.nextInt(183),
        );
        for (final u in [PlanUnitKind.intervals, PlanUnitKind.tempo]) {
          final seg = u == PlanUnitKind.tempo
              ? PlanSegmentKind.tempo
              : PlanSegmentKind.interval;
          final v = t(u, seg, i).intensity;
          expect(v.paceSlowSecondsPerKm, isNotNull);
          expect(v.paceSlowSecondsPerKm! > v.paceFastSecondsPerKm!, isTrue);
        }
      }
    });

    test('Determinismus', () {
      final a = t(PlanUnitKind.tempo, PlanSegmentKind.tempo, inp());
      final b = t(PlanUnitKind.tempo, PlanSegmentKind.tempo, inp());
      expect(
        a.intensity.paceFastSecondsPerKm,
        b.intensity.paceFastSecondsPerKm,
      );
      expect(
        a.intensity.paceSlowSecondsPerKm,
        b.intensity.paceSlowSecondsPerKm,
      );
      expect(a.intensity.basisCode, b.intensity.basisCode);
    });
  });

  group('Anbindung an erzeugte Einheiten', () {
    test(
      'applyTargetIntensities füllt jeden Abschnitt, ändert sonst nichts',
      () {
        final g = TrainingGoal(
          type: GoalType.time,
          distance: GoalDistance.tenKilometers,
          targetSeconds: 3000,
          runDays: const {2, 4, 6, 7},
          maxSessionSeconds: 120 * 60.0,
          weeklyCapSeconds: 300 * 60.0,
          createdAt: DateTime.utc(2026, 11, 11),
          hardSessionEnabled: true,
          canRun30: ContinuousRun30.yes,
        );
        final today = DateTime.utc(2026, 11, 11);
        final plan = generatePlan(
          g,
          PlanInputs(
            anchor: DateTime.utc(2026, 11, 9),
            startWeeklyMinutes: 240,
            today: today,
          ),
          const [],
          today,
        );
        expect(plan.units.any((u) => u.isHard), isTrue);
        final out = applyTargetIntensities(plan.units, inp());
        expect(out.length, plan.units.length);
        for (var k = 0; k < out.length; k++) {
          final a = plan.units[k];
          final b = out[k];
          expect(b.minutes, a.minutes);
          expect(b.day, a.day);
          expect(b.kind, a.kind);
          expect(b.segments.length, a.segments.length);
          for (var j = 0; j < a.segments.length; j++) {
            expect(a.segments[j].intensity, isNull); // Eingabe unverändert
            expect(b.segments[j].kind, a.segments[j].kind);
            expect(b.segments[j].minutes, a.segments[j].minutes);
            expect(b.segments[j].intensity?.rpeMin, isNotNull);
            expect(b.segments[j].intensity?.basisCode, isNotNull);
          }
        }
        expect(
          applyTargetIntensities(plan.units, inp())
              .map(
                (u) => u.segments.map((s) => s.intensity?.paceFastSecondsPerKm),
              )
              .toList(),
          out
              .map(
                (u) => u.segments.map((s) => s.intensity?.paceFastSecondsPerKm),
              )
              .toList(),
        );
      },
    );
  });
}
