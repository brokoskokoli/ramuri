import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Anzeige importierter Health-Connect-Daten (WP32 Teil E): Vergleich fremder
/// VO₂max-Werte je Quelle (FR-0024) und Übernahme einer Einheit als Nachtrag
/// (K62 F2). Alle Daten sind synthetisch.
void main() {
  HealthRecord rec(
    HealthDataKind kind,
    String id,
    String origin,
    DateTime t,
    double v, {
    String unit = 'x',
  }) => HealthRecord(
    kind: kind,
    id: id,
    origin: origin,
    start: t,
    end: t,
    value: v,
    unit: unit,
  );

  group('Vergleich fremder VO₂max (FR-0024)', () {
    final t0 = DateTime.utc(2030, 2, 20, 8);
    test('je Quell-App eine eigene Reihe, nichts verrechnet', () {
      final out = vo2maxComparison([
        rec(HealthDataKind.vo2Max, 'a1', 'app.a', t0, 48),
        rec(
          HealthDataKind.vo2Max,
          'a2',
          'app.a',
          t0.add(const Duration(days: 2)),
          49,
        ),
        rec(
          HealthDataKind.vo2Max,
          'b1',
          'app.b',
          t0.add(const Duration(days: 5)),
          44,
        ),
      ]);
      expect([for (final s in out) s.origin], ['app.b', 'app.a']);
      final a = out.last;
      expect([for (final p in a.points) p.value], [48, 49]);
      expect(a.latest.value, 49);
      expect(out.first.points.single.value, 44);
    });

    test('andere Datenarten und Sätze ohne Zahl gehen nie ein', () {
      final out = vo2maxComparison([
        rec(HealthDataKind.vo2Max, 'a1', 'app.a', t0, 48),
        rec(HealthDataKind.restingHeartRate, 'r1', 'app.a', t0, 55),
        rec(HealthDataKind.hrvRmssd, 'h1', 'app.c', t0, 60),
        HealthRecord(
          kind: HealthDataKind.vo2Max,
          id: 'n',
          origin: 'app.d',
          start: t0,
          end: t0,
        ),
      ]);
      expect([for (final s in out) s.origin], ['app.a']);
      expect(out.single.points, hasLength(1));
    });

    test(
      'Eigene VO₂max-Berechnung bleibt von importierten Werten unberührt',
      () async {
        final w = await RecalcWorld.create();
        final before = await FitnessOverviewService(session: w.session)
            .load(const []);
        await (w.session as HealthStorage).health.upsertValues([
          rec(HealthDataKind.vo2Max, 'a1', 'app.a', t0, 70, unit: 'ml/min/kg'),
          rec(HealthDataKind.vo2Max, 'b1', 'app.b', t0, 30, unit: 'ml/min/kg'),
        ]);
        final after = await FitnessOverviewService(session: w.session)
            .load(const []);
        expect(after.longTerm?.value, before.longTerm?.value);
        expect(after.longTerm?.value, isNull);
        expect(after.day, before.day);
      },
    );
  });

  group('Übernehmen einer Einheit (K62 F2)', () {
    late RecalcWorld w;
    late TrainingLoadService load;
    late SubjectiveService subjective;

    // recalcNow = 2030-03-01 12:00 UTC, Versatz 0.
    final today = DateTime.utc(2030, 3, 1);
    final day = today.subtract(const Duration(days: 2));
    final exercise = HealthRecord(
      kind: HealthDataKind.exercise,
      id: 'ex-1',
      origin: 'app.a',
      start: day.add(const Duration(hours: 18)),
      end: day.add(const Duration(hours: 18, minutes: 44)),
      exerciseType: 56,
    );

    setUp(() async {
      w = await RecalcWorld.create();
      load = TrainingLoadService(
        session: w.session,
        clock: w.clock,
        calculation: w.calc(),
        recalculation: w.recalc(),
      );
      subjective = SubjectiveService(session: w.session, clock: w.clock);
      await (w.session as HealthStorage).health.upsertExercises([exercise]);
      await (w.session as HealthStorage).health.replaceExerciseHeartRate(
        'ex-1',
        [HealthHeartRateSample(exercise.start, 150)],
      );
    });

    /// Zahl der Einheiten des Tages in der Belastung (0 ohne Tag in der Reihe).
    Future<int> units() async {
      final r = await load.load();
      return r.series.days
          .where((x) => x.day == day)
          .fold<int>(0, (a, x) => a + x.unitCount);
    }

    ManualTraining adopt() => ManualTraining(
      day: exerciseLocalDay(exercise, Duration.zero),
      kind: manualKindOfExercise(exercise.exerciseType),
      duration: Duration(minutes: exerciseMinutes(exercise)),
      rpe: 5,
      hcId: exercise.id,
    );

    test('Vorbelegung: Tag, Art und Dauer der Einheit', () {
      final t = adopt();
      expect(t.day, day);
      expect(t.kind, ManualTrainingKind.run);
      expect(t.duration, const Duration(minutes: 44));
      expect(manualKindOfExercise(null), ManualTrainingKind.other);
    });

    test(
      'vor dem Übernehmen zählt die fremde Einheit nicht, danach genau einmal',
      () async {
        expect(await units(), 0);
        expect(await subjective.isAdopted('ex-1'), isFalse);

        await subjective.addTraining(adopt());
        expect(await units(), 1);
        expect(await subjective.isAdopted('ex-1'), isTrue);

        // Kein zweites Übernehmen: Fehler, die Last bleibt.
        await expectLater(
          subjective.addTraining(adopt()),
          throwsA(isA<SubjectiveRangeError>()),
        );
        expect(await units(), 1);
        expect((await subjective.trainings()), hasLength(1));
      },
    );

    test('der Puls geht nie in den Nachtrag ein', () async {
      final stored = await subjective.addTraining(adopt());
      expect(stored.training.hcId, 'ex-1');
      expect(
        await (w.session as HealthStorage).health.exerciseHeartRate('ex-1'),
        hasLength(1),
      );
      // Pulsverlauf gelöscht: der Nachtrag bleibt unverändert und zählt weiter.
      await (w.session as HealthStorage).health.deleteKind(
        HealthDataKind.exercise,
      );
      expect((await subjective.trainings()).single.training.hcId, 'ex-1');
      expect(await units(), 1);
    });

    test('Ändern eines übernommenen Nachtrags: hcId bleibt, kein zweites Übernehmen', () async {
      final stored = await subjective.addTraining(adopt());
      final t = stored.training;
      await subjective.updateTraining(
        stored.id,
        ManualTraining(
          day: t.day,
          kind: t.kind,
          duration: const Duration(minutes: 50),
          rpe: 6,
          hcId: t.hcId,
        ),
      );
      final back = (await subjective.trainings()).single.training;
      expect(back.hcId, 'ex-1');
      expect(back.duration, const Duration(minutes: 50));
      expect(await subjective.isAdopted('ex-1'), isTrue);
      await expectLater(
        subjective.addTraining(adopt()),
        throwsA(isA<SubjectiveRangeError>()),
      );
      expect(await units(), 1);
    });

    test('adoptedHcIds nennt nur übernommene Einheiten', () async {
      await subjective.addTraining(adopt());
      await subjective.addTraining(
        ManualTraining(
          day: day,
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 20),
          rpe: 3,
        ),
      );
      expect(adoptedHcIds(await subjective.trainings()), {'ex-1'});
    });
  });
}
