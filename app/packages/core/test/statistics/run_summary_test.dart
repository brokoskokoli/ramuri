import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

void main() {
  group('Zusammenfassung eines Laufs', () {
    test('alle Punkte aus den Rohdaten; Einordnung mit Vorläufen', () async {
      final w = await RecalcWorld.create();
      for (var i = 0; i < 3; i++) {
        final p = await w.seedRun(
          DateTime.utc(2030, 1, 1 + i, 8),
          minutes: 5,
          speed: 2.5,
        );
        await w.calc().calculateAfterRun(p);
      }
      final id = await w.seedRun(
        DateTime.utc(2030, 1, 10, 8),
        minutes: 20,
        speed: 3.0,
      );
      await w.calc().calculateAfterRun(id);
      final s = (await RunSummaryService(
        session: w.session,
        clock: w.clock,
      ).load(id))!;
      expect(s.figures.distanceMeters, closeTo(3600, 5));
      expect(s.figures.movingTime, const Duration(minutes: 20));
      expect(s.figures.heartRateAverageBpm, 150);
      expect(s.bestPace.secondsPerKm, closeTo(1000 / 3, 1));
      expect(s.load.zoneTimes, isNotNull);
      expect(s.load.trimpPoints, isNotNull);
      expect(s.classification.comparedRuns, 3);
      expect(s.classification.relation, PaceRelation.faster);
      expect(s.vo2max, isNotNull);
      expect(s.ascentMeters, isNotNull);
    });

    test(
      'Lauf kürzer als die Bestpace-Strecke: Bestpace nicht verfügbar',
      () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(
          DateTime.utc(2030, 1, 10, 8),
          minutes: 2,
          speed: 3.0,
        ); // 360 m
        final s = (await RunSummaryService(
          session: w.session,
          clock: w.clock,
        ).load(id))!;
        expect(s.bestPace.secondsPerKm, isNull);
        expect(s.bestPace.unavailable, BestPaceUnavailable.noQualifyingSection);
        expect(
          s.classification.unavailable,
          ClassificationUnavailable.tooFewPreviousRuns,
        );
        expect(s.vo2max, isNull, reason: 'nicht berechnet: kein Wert');
      },
    );

    test('ohne Profil: Zonen und TRIMP nicht verfügbar mit Grund', () async {
      final w = await RecalcWorld.create(profile: const ProfileRecord());
      final id = await w.seedRun(DateTime.utc(2030, 1, 10, 8), minutes: 5);
      await w.calc().calculateAfterRun(id);
      final s = (await RunSummaryService(
        session: w.session,
        clock: w.clock,
      ).load(id))!;
      expect(s.load.zoneTimes, isNull);
      expect(s.load.zonesReason, UnavailableReason.missingMaxHeartRate);
      expect(s.load.trimpReason, UnavailableReason.missingMaxHeartRate);
      expect(s.figures.trimpPoints, isNull);
      expect(s.figures.heartRateAverageBpm, 150, reason: 'Puls bleibt da');
    });

    test('unbekannter oder unfertiger Lauf: null', () async {
      final w = await RecalcWorld.create();
      final r = await w.session.runs.create(startedAt: DateTime.utc(2030));
      final svc = RunSummaryService(session: w.session, clock: w.clock);
      expect(await svc.load(r.id), isNull);
      expect(await svc.load(999), isNull);
    });
  });
}
