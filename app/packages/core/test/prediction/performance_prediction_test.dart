import 'package:core/core.dart';
import 'package:test/test.dart';

final now = DateTime(2026, 11, 9, 12);
DateTime day(int ago) => DateTime(2026, 11, 9 - ago, 8);

ReferencePerformance ref({
  ReferenceKind kind = ReferenceKind.race,
  double meters = 10000,
  double seconds = 3000,
  int age = 10,
  DateTime? createdAt,
  String? runId,
}) => ReferencePerformance(
  kind: kind,
  distanceMeters: meters,
  seconds: seconds,
  date: day(age),
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  runId: runId,
);

var _n = 0;
PredictionRun run(
  int ago, {
  double seconds = 600,
  double? meters,
  int? rpe,
  List<double>? pace,
}) => PredictionRun(
  id: 'r${_n++}',
  date: day(ago),
  movingSeconds: seconds,
  distanceMeters: meters,
  rpe: rpe,
  paceSamples: pace,
);

/// Läufe alle 3 Tage von heute bis [upTo] Tage zurück: jede 7-Tage-Woche hat
/// mindestens 2 Läufe, keine Lücke über 3 Tage.
List<PredictionRun> dense(int upTo, {double seconds = 600}) => [
  for (var o = 0; o <= (upTo < 60 ? 60 : upTo); o += 3)
    run(o, seconds: seconds),
];

/// Je 2 Läufe in den genannten rollenden Wochen (0 = jüngste).
List<PredictionRun> weeksWithRuns(Iterable<int> weeks) => [
  for (final w in weeks) ...[run(7 * w + 2), run(7 * w + 4)],
];

DistancePrediction predict10k(
  ReferencePerformance r,
  List<PredictionRun> runs,
) => predictPerformance(
  now: now,
  references: [r],
  runs: runs,
).of(PredictionDistance.tenKilometers);

void main() {
  group('Riegel (FR-0130)', () {
    test('5 km in 25 min ergibt für 10 km 52:07', () {
      final s = riegelSeconds(
        referenceSeconds: 1500,
        referenceMeters: 5000,
        targetMeters: 10000,
      );
      expect(s, closeTo(3127.2, 0.5));
      expect(s.round(), 52 * 60 + 7);
    });

    test('Exponent 1,06 und Rückrechnung', () {
      expect(
        riegelSeconds(
          referenceSeconds: 3127.2,
          referenceMeters: 10000,
          targetMeters: 5000,
        ),
        closeTo(1500, 0.5),
      );
      expect(
        riegelSeconds(
          referenceSeconds: 100,
          referenceMeters: 1000,
          targetMeters: 1000,
        ),
        100,
      );
    });

    test('ungültige Eingaben werfen', () {
      expect(
        () => riegelSeconds(
          referenceSeconds: 0,
          referenceMeters: 5000,
          targetMeters: 10000,
        ),
        throwsArgumentError,
      );
      expect(
        () => riegelSeconds(
          referenceSeconds: 1,
          referenceMeters: double.nan,
          targetMeters: 10000,
        ),
        throwsArgumentError,
      );
    });

    test('Prognose für alle vier Distanzen aus 5 km in 25 min', () {
      final p = predictPerformance(
        now: now,
        references: [ref(meters: 5000, seconds: 1500)],
        runs: dense(10),
      );
      expect(p.distances.map((d) => d.distance), PredictionDistance.values);
      expect(
        p.of(PredictionDistance.fiveKilometers).seconds,
        closeTo(1500, 1e-9),
      );
      expect(
        p.of(PredictionDistance.tenKilometers).seconds!.round(),
        52 * 60 + 7,
      );
      expect(
        p.of(PredictionDistance.halfMarathon).seconds,
        closeTo(1500 * _pow(21097.5 / 5000), 1e-6),
      );
      expect(
        p.of(PredictionDistance.marathon).seconds,
        closeTo(1500 * _pow(42195 / 5000), 1e-6),
      );
    });
  });

  group('nicht bestimmbar (PAR-143)', () {
    test('keine Referenz: keine Zeit, Grund', () {
      final p = predictPerformance(now: now, references: [], runs: dense(30));
      for (final d in p.distances) {
        expect(d.seconds, isNull);
        expect(d.level, PredictionLevel.notDeterminable);
        expect(d.reason, PredictionReason.noReference);
      }
      expect(p.reference, isNull);
    });

    test('VO2max allein ergibt keine Zeit (FR-0134)', () {
      final p = predictPerformance(
        now: now,
        references: [],
        runs: dense(30),
        hasVo2maxEstimate: true,
      );
      for (final d in p.distances) {
        expect(d.seconds, isNull);
        expect(d.level, PredictionLevel.notDeterminable);
        expect(d.reason, PredictionReason.onlyVo2max);
      }
      expect(p.metadata.sources, [PredictionSource.vo2max]);
    });

    test('VO2max neben einer Referenz ändert die Zeit nicht', () {
      final a = predictPerformance(
        now: now,
        references: [ref()],
        runs: dense(10),
      );
      final b = predictPerformance(
        now: now,
        references: [ref()],
        runs: dense(10),
        hasVo2maxEstimate: true,
      );
      for (final d in PredictionDistance.values) {
        expect(b.of(d).seconds, a.of(d).seconds);
        expect(b.of(d).level, a.of(d).level);
      }
    });

    test('Alter 182 Tage noch bestimmbar, 183 nicht', () {
      final ok = predict10k(ref(age: 182), dense(182));
      expect(ok.level, PredictionLevel.provisional);
      expect(ok.seconds, isNotNull);
      final old = predict10k(ref(age: 183), dense(183));
      expect(old.level, PredictionLevel.notDeterminable);
      expect(old.reason, PredictionReason.referenceTooOld);
      expect(old.seconds, isNull);
    });

    test('Pause: Lücke 55 Tage ja bestimmbar, 56 nicht', () {
      // Referenz vor 100 Tagen; die Lücke liegt zwischen Referenz und Lauf.
      final r = ref(age: 100);
      expect(predict10k(r, [run(45)]).level, PredictionLevel.provisional);
      final p = predict10k(r, [run(44)]);
      expect(p.level, PredictionLevel.notDeterminable);
      expect(p.reason, PredictionReason.pauseSinceReference);
    });

    test('Pause zählt auch die letzte Lücke bis heute', () {
      final r = ref(age: 100);
      expect(predict10k(r, [run(55)]).level, PredictionLevel.provisional);
      expect(predict10k(r, [run(56)]).level, PredictionLevel.notDeterminable);
    });

    test('Pause zwischen zwei Läufen nach der Referenz', () {
      final r = ref(age: 120);
      // Referenz 120, Läufe 70 und 15: Lücken 50, 55, 15.
      expect(
        predict10k(r, [run(70), run(15)]).level,
        PredictionLevel.provisional,
      );
      // Lücke 56 zwischen den Läufen 70 und 14.
      expect(
        predict10k(r, [run(70), run(14)]).level,
        PredictionLevel.notDeterminable,
      );
    });

    test(
      'Läufe vor der Referenz und in der Zukunft zählen nicht für Lücken',
      () {
        final r = ref(age: 100);
        final p = predict10k(r, [run(200), run(-3)]);
        expect(p.reason, PredictionReason.pauseSinceReference);
      },
    );

    test('ungültige Referenz', () {
      // Zu kurz oder Zeit null: unbrauchbar, wird ignoriert (wie keine
      // Referenz, Festlegung WP22); künftiges Datum: ungültig.
      for (final (bad, reason) in [
        (ref(meters: 2999), PredictionReason.noReference),
        (ref(seconds: 0), PredictionReason.noReference),
        (ref(age: -1), PredictionReason.invalidReference),
      ]) {
        final p = predict10k(bad, dense(10));
        expect(p.level, PredictionLevel.notDeterminable);
        expect(p.reason, reason);
        expect(p.seconds, isNull);
      }
      expect(ref(meters: 3000, seconds: 900).validate(now), isNull);
      expect(
        ref(meters: 2999).validate(now),
        ReferenceProblem.distanceTooShort,
      );
      expect(ref(seconds: -1).validate(now), ReferenceProblem.nonPositiveTime);
      expect(ref(age: 0).validate(now), isNull);
      expect(ref(age: -1).validate(now), ReferenceProblem.dateInFuture);
    });

    test('Tempospanne 2:30 bis 15:00 min/km, Grenzen eingeschlossen', () {
      // 5 km: 12:30 (2:30 min/km) und 75:00 (15:00 min/km) gelten.
      expect(ref(meters: 5000, seconds: 750).validate(now), isNull);
      expect(ref(meters: 5000, seconds: 4500).validate(now), isNull);
      for (final seconds in [749.0, 4501.0, 999 * 3600.0]) {
        expect(
          ref(meters: 5000, seconds: seconds).validate(now),
          ReferenceProblem.paceOutOfRange,
          reason: '$seconds s',
        );
      }
      // Benannte Parameter wirken.
      const wide = PredictionParameters(slowestReferencePaceSecondsPerKm: 1000);
      expect(ref(meters: 5000, seconds: 4600).validate(now, wide), isNull);
      // Vorrang: zu kurz und Zeit null vor dem Tempo.
      expect(
        ref(meters: 2999, seconds: 99999).validate(now),
        ReferenceProblem.distanceTooShort,
      );
      // Prognose: eine unplausible Referenz (gespeichert oder importiert)
      // wird ignoriert, als gäbe es sie nicht (Festlegung WP22, E2E API 36).
      final p = predict10k(ref(seconds: 999 * 3600), dense(10));
      expect(p.reason, PredictionReason.noReference);
      expect(p.seconds, isNull);
    });

    test('Referenz außerhalb der Tempospanne gilt nirgends: activeReference '
        'überspringt sie, die Prognose nimmt die ältere gültige', () {
      final valid = ref(age: 20);
      final slow = ref(age: 5, meters: 5000, seconds: 999 * 3600);
      final fast = ref(age: 3, meters: 5000, seconds: 749);
      expect(isUsableReference(valid), isTrue);
      expect(isUsableReference(slow), isFalse);
      expect(isUsableReference(fast), isFalse);
      // Künftiges Datum ist kein Ausschlussgrund (die Prognose meldet es).
      expect(isUsableReference(ref(age: -1)), isTrue);
      expect(activeReference([valid, slow, fast]), same(valid));
      expect(activeReference([slow, fast]), isNull);
      final p = predictPerformance(
        now: now,
        references: [valid, slow],
        runs: dense(30),
      ).of(PredictionDistance.tenKilometers);
      expect(p.seconds, isNotNull);
      expect(
        p.seconds,
        predict10k(valid, dense(30)).seconds,
        reason: 'Grundlage ist die ältere gültige Referenz',
      );
    });
  });

  group('Stufen und Grenzen', () {
    test('Alter 84 ausreichend, 85 vorläufig mit Grund Alter', () {
      final a = predict10k(ref(age: 84), dense(84));
      expect(a.level, PredictionLevel.sufficient);
      final b = predict10k(ref(age: 85), dense(85));
      expect(b.level, PredictionLevel.provisional);
      expect(b.reason, PredictionReason.referenceAge);
    });

    test('Alter 42 gut, 43 ausreichend mit Grund Alter', () {
      final a = predict10k(ref(age: 42), dense(42, seconds: 2400));
      expect(a.level, PredictionLevel.good);
      expect(a.reason, PredictionReason.none);
      final b = predict10k(ref(age: 43), dense(43, seconds: 2400));
      expect(b.level, PredictionLevel.sufficient);
      expect(b.reason, PredictionReason.referenceAge);
    });

    test('Verhältnis 3 ausreichend, über 3 vorläufig (beide Richtungen)', () {
      final runs = dense(10, seconds: 4000);
      for (final (m, level) in [
        (30000.0, PredictionLevel.sufficient),
        (30001.0, PredictionLevel.provisional),
        (10000 / 3, PredictionLevel.sufficient),
        (3300.0, PredictionLevel.provisional),
      ]) {
        // 5:00 min/km: im Tempobereich, nur das Verhältnis zählt.
        final p = predict10k(ref(meters: m, seconds: m * 0.3), runs);
        expect(p.level, level, reason: '$m');
        if (level == PredictionLevel.provisional) {
          expect(p.reason, PredictionReason.distanceRatio);
        }
      }
    });

    test('Verhältnis 2,2 gut, darüber ausreichend', () {
      final runs = dense(10, seconds: 5000);
      final at = predict10k(ref(meters: 22000, seconds: 6600), runs);
      expect(at.level, PredictionLevel.good, reason: '${at.limits}');
      expect(
        predict10k(ref(meters: 4546, seconds: 1364), runs).level,
        PredictionLevel.good,
      );
      final p = predict10k(ref(meters: 22100, seconds: 6630), runs);
      expect(p.level, PredictionLevel.sufficient);
      expect(p.reason, PredictionReason.distanceRatio);
      expect(
        predict10k(ref(meters: 4500, seconds: 1350), runs).level,
        PredictionLevel.sufficient,
      );
    });

    test('Regelmäßigkeit ausreichend: 6 Wochen ja, 5 nein', () {
      final r = ref(age: 30);
      final six = predict10k(r, weeksWithRuns([0, 1, 2, 3, 4, 5]));
      expect(six.level, PredictionLevel.sufficient);
      final five = predict10k(r, weeksWithRuns([0, 1, 2, 3, 4]));
      expect(five.level, PredictionLevel.provisional);
      expect(five.reason, PredictionReason.regularity);
    });

    test('Regelmäßigkeit gut: 7 Wochen ja, 6 nein', () {
      final r = ref(age: 30);
      final seven = predict10k(r, [
        ...weeksWithRuns([0, 1, 2, 3, 4, 5, 6]),
        run(10, seconds: 2400),
      ]);
      expect(seven.level, PredictionLevel.good);
      final six = predict10k(
        r,
        weeksWithRuns([0, 1, 2, 3, 4, 5])..add(run(10, seconds: 2400)),
      );
      expect(six.level, PredictionLevel.sufficient);
      expect(six.reason, PredictionReason.regularity);
    });

    test('eine Woche mit nur einem Lauf zählt nicht', () {
      final r = ref(age: 30);
      final runs = [
        ...weeksWithRuns([0, 1, 2, 3, 4, 5]),
        run(7 * 6 + 3, seconds: 2400),
        run(11, seconds: 2400),
      ];
      expect(predict10k(r, runs).level, PredictionLevel.sufficient);
    });

    test('Wochen außerhalb von 8 rollenden Wochen zählen nicht', () {
      final r = ref(age: 30);
      // Block 8 beginnt bei Offset 56: Läufe dort zählen nicht mit.
      final runs = [
        ...weeksWithRuns([0, 1, 2, 3, 4]),
        run(56),
        run(57),
      ];
      expect(predict10k(r, runs).level, PredictionLevel.provisional);
      // Block 7 (Offset 49 bis 55) zählt dagegen.
      final in8 = [
        ...weeksWithRuns([0, 1, 2, 3, 4]),
        run(49),
        run(55),
      ];
      expect(predict10k(r, in8).level, PredictionLevel.sufficient);
    });

    test('Wochen sind rollend ab heute, nicht Kalenderwochen', () {
      // Zwei Läufe an Offset 0 und 6 liegen im selben Block, 0 und 7 nicht.
      final r = ref(age: 30);
      final base = weeksWithRuns([1, 2, 3, 4, 5]);
      expect(
        predict10k(r, [...base, run(0), run(6)]).level,
        PredictionLevel.sufficient,
      );
      expect(
        predict10k(r, [...base, run(0), run(7)]).level,
        PredictionLevel.provisional,
      );
    });

    test(
      'längste Einheit 60 %: genau 60 % gut, knapp darunter ausreichend',
      () {
        final r = ref(age: 10, seconds: 3000);
        final other = dense(10);
        final ok = predict10k(r, [...other, run(41, seconds: 1800)]);
        expect(ok.level, PredictionLevel.good);
        final low = predict10k(r, [...other, run(41, seconds: 1799)]);
        expect(low.level, PredictionLevel.sufficient);
        expect(low.reason, PredictionReason.longestRun);
      },
    );

    test('längste Einheit: Fenster 42 Tage, Offset 42 zählt nicht', () {
      final r = ref(age: 10, seconds: 3000);
      final p = predict10k(r, [...dense(10), run(42, seconds: 5000)]);
      expect(p.level, PredictionLevel.sufficient);
      expect(p.reason, PredictionReason.longestRun);
    });

    test('die 60 % beziehen sich auf die Zeit der Ziel-Distanz', () {
      final p = predictPerformance(
        now: now,
        references: [ref(age: 10, seconds: 3000)],
        runs: [...dense(10), run(5, seconds: 1900)],
      );
      expect(
        p.of(PredictionDistance.tenKilometers).level,
        PredictionLevel.good,
      );
      expect(
        p.of(PredictionDistance.fiveKilometers).level,
        PredictionLevel.good,
      );
      final half = p.of(PredictionDistance.halfMarathon);
      expect(half.level, PredictionLevel.sufficient);
      expect(half.reason, PredictionReason.longestRun);
    });

    test(
      'Testzeit höchstens ausreichend, bestätigter Lauf höchstens vorläufig',
      () {
        final runs = dense(10, seconds: 4000);
        final t = predict10k(ref(kind: ReferenceKind.test), runs);
        expect(t.level, PredictionLevel.sufficient);
        expect(t.reason, PredictionReason.referenceIsTest);
        final c = predict10k(
          ref(kind: ReferenceKind.confirmedRun, runId: 'x'),
          runs,
        );
        expect(c.level, PredictionLevel.provisional);
        expect(c.reason, PredictionReason.referenceIsConfirmedRun);
      },
    );

    test('Alter 84 und bestätigter Lauf: Grund bleibt erkennbar in limits', () {
      final p = predict10k(
        ref(kind: ReferenceKind.confirmedRun, age: 85, runId: 'x'),
        dense(85),
      );
      expect(p.level, PredictionLevel.provisional);
      expect(
        p.limits,
        containsAll([
          PredictionReason.referenceAge,
          PredictionReason.referenceIsConfirmedRun,
        ]),
      );
    });

    test('Marathon nie über vorläufig, auch bei bester Datenlage', () {
      final runs = dense(5, seconds: 20000);
      for (final kind in ReferenceKind.values) {
        for (final m in [5000.0, 10000.0, 21097.5, 42195.0]) {
          final p = predictPerformance(
            now: now,
            references: [ref(kind: kind, meters: m, age: 0, seconds: m * 0.36)],
            runs: runs,
          );
          final marathon = p.of(PredictionDistance.marathon);
          expect(
            marathon.level.index,
            lessThanOrEqualTo(PredictionLevel.provisional.index),
            reason: '$kind $m',
          );
          expect(marathon.seconds, isNotNull);
        }
      }
      final best = predictPerformance(
        now: now,
        references: [ref(meters: 42195, seconds: 14400, age: 0)],
        runs: runs,
      );
      expect(
        best.of(PredictionDistance.halfMarathon).level,
        PredictionLevel.good,
      );
      final m = best.of(PredictionDistance.marathon);
      expect(m.level, PredictionLevel.provisional);
      expect(m.reason, PredictionReason.marathon);
    });

    test('ältere Referenz ergibt nie eine höhere Stufe (FR-0132)', () {
      for (final kind in ReferenceKind.values) {
        for (final meters in [5000.0, 10000.0, 21097.5, 42195.0]) {
          for (final target in PredictionDistance.values) {
            var previous = PredictionLevel.good.index;
            for (var age = 0; age <= 200; age++) {
              final p = predictPerformance(
                now: now,
                references: [
                  ref(
                    kind: kind,
                    meters: meters,
                    age: age,
                    seconds: meters * 0.3,
                  ),
                ],
                runs: dense(200, seconds: 9000),
              ).of(target);
              expect(
                p.level.index,
                lessThanOrEqualTo(previous),
                reason: '$kind $meters $target Alter $age',
              );
              previous = p.level.index;
            }
          }
        }
      }
    });
  });

  group('Referenz', () {
    test('jüngste nach Datum, bei gleichem Datum zuletzt angelegt', () {
      final a = ref(age: 20, createdAt: DateTime(2026, 5, 1));
      final b = ref(age: 10, createdAt: DateTime(2026, 4, 1));
      final c = ref(age: 10, createdAt: DateTime(2026, 6, 1), meters: 5000);
      expect(activeReference([a, b]), same(b));
      expect(activeReference([a, b, c]), same(c));
      expect(activeReference([c, b, a]), same(c));
      expect(activeReference([]), isNull);
    });
  });

  group('Zielprognose (FR-0133)', () {
    final good = predict10k(ref(age: 10), dense(10, seconds: 4000));
    test('knapp und eher später begrenzen auf vorläufig', () {
      expect(good.level, PredictionLevel.good);
      for (final f in [GoalFeasibility.tight, GoalFeasibility.later]) {
        final g = predictGoal(general: good, feasibility: f);
        expect(g.level, PredictionLevel.provisional);
        expect(g.reason, PredictionReason.goalFeasibility);
        expect(g.general, same(good));
      }
    });
    test('passt oder zu wenig Daten lässt die Stufe, nie höher', () {
      for (final f in [GoalFeasibility.fits, GoalFeasibility.notEnoughData]) {
        expect(predictGoal(general: good, feasibility: f).level, good.level);
      }
      final prov = predict10k(ref(age: 100), dense(100));
      expect(
        predictGoal(general: prov, feasibility: GoalFeasibility.tight).reason,
        prov.reason,
      );
    });
  });

  group('Metadaten (FR-0053)', () {
    test('alle Angaben abrufbar', () {
      final p = predictPerformance(
        now: now,
        references: [ref(age: 10)],
        runs: [run(1), run(2), run(60)],
        hasVo2maxEstimate: true,
      );
      final m = p.metadata;
      expect(m.calculatedAt, now);
      expect(m.dataFrom, DateTime.utc(2026, 10, 30));
      expect(m.dataTo, DateTime.utc(2026, 11, 9));
      expect(m.measurementCount, 3);
      expect(m.sources, [
        PredictionSource.enteredTime,
        PredictionSource.runHistory,
        PredictionSource.vo2max,
      ]);
      expect(m.method, predictionMethod);
      expect(m.methodVersion, predictionMethodVersion);
      expect(m.level, PredictionLevel.provisional);
    });

    test('ohne Referenz: keine Messungen, kein Zeitraum', () {
      final m = predictPerformance(
        now: now,
        references: [],
        runs: dense(10),
      ).metadata;
      expect(m.measurementCount, 0);
      expect(m.dataFrom, isNull);
      expect(m.level, PredictionLevel.notDeterminable);
    });

    test('Methode über die Registry', () {
      final v = AlgorithmRegistry.standard().active(
        performancePredictionFamily,
      );
      expect(v.method, predictionMethod);
      expect(v.methodVersion, predictionMethodVersion);
      expect(v.category, AlgorithmCategory.heuristic);
    });
  });

  group('Hinweis 5-km-Test (PAR-117)', () {
    PerformancePrediction none(List<PredictionRun> runs) =>
        predictPerformance(now: now, references: [], runs: runs);
    List<PredictionRun> twelve({double longest = 1800}) => [
      for (var i = 0; i < 11; i++) run(i * 2),
      run(5, seconds: longest),
    ];

    test('12 Läufe und 30 min: Hinweis', () {
      final r = twelve();
      expect(
        showFiveKilometerTestHint(prediction: none(r), now: now, runs: r),
        isTrue,
      );
    });
    test('11 Läufe: kein Hinweis', () {
      final r = twelve()..removeAt(0);
      expect(
        showFiveKilometerTestHint(prediction: none(r), now: now, runs: r),
        isFalse,
      );
    });
    test('29:59 min: kein Hinweis', () {
      final r = twelve(longest: 1799);
      expect(
        showFiveKilometerTestHint(prediction: none(r), now: now, runs: r),
        isFalse,
      );
    });
    test('Fenster 28 Tage: Offset 27 zählt, 28 nicht', () {
      final base = [for (var i = 0; i < 11; i++) run(i), run(5, seconds: 1800)];
      final in27 = [...base.sublist(0, 11), run(27, seconds: 1800)];
      expect(
        showFiveKilometerTestHint(prediction: none(in27), now: now, runs: in27),
        isTrue,
      );
      final in28 = [...base.sublist(0, 11), run(28, seconds: 1800)];
      expect(
        showFiveKilometerTestHint(prediction: none(in28), now: now, runs: in28),
        isFalse,
      );
    });
    test('nur bei nicht bestimmbar', () {
      final r = twelve();
      final p = predictPerformance(now: now, references: [ref()], runs: r);
      expect(
        showFiveKilometerTestHint(prediction: p, now: now, runs: r),
        isFalse,
      );
    });
  });

  group('Tempostabilität (PAR-022)', () {
    final p = const FitnessParameters.v4().sectionSelection;
    test('gleichmäßig, schwankend, Hälften, nicht bestimmbar', () {
      expect(isPaceStable(List.filled(10, 3.0), p), isTrue);
      expect(isPaceStable([3, 3.5, 2.5, 3.4, 2.6, 3.3], p), isFalse);
      expect(
        isPaceStable([3.0, 3.0, 3.0, 3.0, 3.2, 3.2, 3.2, 3.2], p),
        isFalse,
      );
      expect(isPaceStable([3.0], p), isNull);
      expect(isPaceStable(null, p), isNull);
      expect(isPaceStable([3.0, 0], p), isNull);
    });
  });

  group('Vorschlag (PAR-185)', () {
    final steady = List.filled(10, 3.2);
    final active = ref(meters: 5000, seconds: 1500, age: 30);
    final limit = riegelSeconds(
      referenceSeconds: 1500,
      referenceMeters: 5000,
      targetMeters: 10000,
    );
    List<ReferenceSuggestion> s(
      List<PredictionRun> runs, {
      ReferencePerformance? ref,
      Set<String> rejected = const {},
      Set<String> stored = const {},
    }) => suggestReferences(
      runs: runs,
      activeReference: ref,
      rejectedRunIds: rejected,
      storedRunIds: stored,
    );

    test('Zweig 1: RPE 8, 3 km, gleichmäßig', () {
      final r = run(1, seconds: 900, meters: 3000, rpe: 8, pace: steady);
      expect(s([r]).single.branches, [SuggestionBranch.hardAndSteady]);
    });
    test('RPE 7 kein Vorschlag, RPE 9 ja', () {
      expect(
        s([run(1, seconds: 1500, meters: 5000, rpe: 7, pace: steady)]),
        isEmpty,
      );
      expect(
        s([run(1, seconds: 1500, meters: 5000, rpe: 9, pace: steady)]),
        hasLength(1),
      );
    });
    test('Tempo außerhalb 2:30 bis 15:00 min/km: kein Vorschlag', () {
      // 5 km in 12:29 (zu schnell) und 75:01 (zu langsam); Grenzen ja.
      for (final (seconds, n) in [(749.0, 0), (750.0, 1), (4500.0, 1)]) {
        expect(
          s([run(1, seconds: seconds, meters: 5000, rpe: 9, pace: steady)]),
          hasLength(n),
          reason: '$seconds s',
        );
      }
      expect(
        s([run(1, seconds: 4501, meters: 5000, rpe: 9, pace: steady)]),
        isEmpty,
      );
    });
    test('2999 m kein Vorschlag, 3000 m ja', () {
      expect(s([run(1, meters: 2999, rpe: 8, pace: steady)]), isEmpty);
      expect(s([run(1, meters: 3000, rpe: 8, pace: steady)]), hasLength(1));
    });
    test('ungleichmäßig oder Stabilität unbekannt: kein Vorschlag', () {
      expect(
        s([
          run(
            1,
            seconds: 1500,
            meters: 5000,
            rpe: 9,
            pace: [3, 3.6, 2.4, 3.5, 2.5],
          ),
        ]),
        isEmpty,
      );
      expect(s([run(1, seconds: 1500, meters: 5000, rpe: 9)]), isEmpty);
    });
    test('RPE fehlt: Zweig 1 löst nicht aus', () {
      expect(s([run(1, seconds: 1500, meters: 5000, pace: steady)]), isEmpty);
    });
    test('Distanz nicht gemessen: kein Vorschlag, auch bei Zweig 2', () {
      expect(
        s([run(1, seconds: 100, rpe: 9, pace: steady)], ref: active),
        isEmpty,
      );
    });
    test('Zweig 2: schlägt Riegel der Referenz, knapp ja, gleich nein', () {
      final beat = run(1, seconds: limit - 1, meters: 10000);
      final same = run(2, seconds: limit, meters: 10000);
      final out = s([beat, same], ref: active);
      expect(out.map((e) => e.run.id), [beat.id]);
      expect(out.single.branches, [SuggestionBranch.beatsReference]);
    });
    test('Zweig 2 braucht eine Referenz und 3 km', () {
      expect(s([run(1, seconds: 3000, meters: 10000)]), isEmpty);
      expect(s([run(1, seconds: 800, meters: 2999)], ref: active), isEmpty);
      expect(
        s([run(1, seconds: 800, meters: 3000)], ref: active),
        hasLength(1),
      );
    });
    test('beide Zweige zugleich', () {
      final r = run(
        1,
        seconds: limit - 60,
        meters: 10000,
        rpe: 9,
        pace: steady,
      );
      expect(s([r], ref: active).single.branches, [
        SuggestionBranch.hardAndSteady,
        SuggestionBranch.beatsReference,
      ]);
    });
    test('abgelehnt und aktive Referenz kommen nicht wieder', () {
      final r = run(1, seconds: limit - 60, meters: 10000);
      expect(s([r], ref: active, rejected: {r.id}), isEmpty);
      final asRef = ref(
        kind: ReferenceKind.confirmedRun,
        meters: 5000,
        seconds: 1500,
        runId: r.id,
      );
      expect(s([r], ref: asRef), isEmpty);
    });
    test('schon gespeicherte Referenz-Läufe kommen nicht wieder (Befund 2)', () {
      // Ein bestätigter Lauf, der älter ist als die aktive Referenz, ist nicht
      // die aktive Referenz, aber gespeichert.
      final r = run(40, seconds: limit - 60, meters: 10000);
      expect(s([r], ref: active), isEmpty); // älter als die aktive (30 Tage)
      final h = run(40, seconds: 900, meters: 5000, rpe: 9, pace: steady);
      expect(s([h], ref: active), hasLength(1)); // Zweig 1 gilt weiter
      expect(s([h], ref: active, stored: {h.id}), isEmpty);
    });
    test('Zweig 2 nur ab dem Datum der aktiven Referenz', () {
      final onDay = run(30, seconds: limit - 60, meters: 10000);
      final before = run(31, seconds: limit - 60, meters: 10000);
      expect(s([onDay, before], ref: active).map((e) => e.run.id), [onDay.id]);
    });
    test('lockerer Lauf wird nie vorgeschlagen (FR-0131)', () {
      expect(
        s([
          run(1, seconds: 3600, meters: 6000, rpe: 4, pace: steady),
        ], ref: active),
        isEmpty,
      );
    });
  });
}

double _pow(double ratio) =>
    riegelSeconds(referenceSeconds: 1, referenceMeters: 1, targetMeters: ratio);
