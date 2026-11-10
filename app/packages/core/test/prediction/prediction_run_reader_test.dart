import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

void main() {
  group('PredictionRunReader (Läufe aus vorhandenen Daten)', () {
    late RecalcWorld w;
    late PredictionRunReader reader;

    setUp(() async {
      w = await RecalcWorld.create();
      reader = PredictionRunReader(session: w.session, clock: w.clock);
    });

    test(
      'Bewegungszeit, Distanz und 30-s-Tempowerte; rpe bleibt null',
      () async {
        final long = await w.seedRun(DateTime.utc(2030, 1, 5, 8), minutes: 20);
        final short = await w.seedRun(DateTime.utc(2030, 1, 6, 8), minutes: 5);
        final runs = await reader.load();
        // Neuester Start zuerst; nur beendete Läufe.
        expect(runs.map((r) => r.id), ['$short', '$long']);
        final l = runs.last;
        expect(l.movingSeconds, closeTo(1200, 5));
        expect(l.distanceMeters, closeTo(3600, 40));
        expect(l.rpe, isNull);
        expect(l.paceSamples, isNotEmpty);
        for (final v in l.paceSamples!) {
          expect(v, closeTo(3.0, 0.1));
        }
        expect(
          isPaceStable(
            l.paceSamples,
            const FitnessParameters.v4().sectionSelection,
          ),
          isTrue,
        );
        // Unter der Mindeststrecke für Vorschläge: keine Wiedergabe.
        expect(runs.first.distanceMeters, lessThan(3000));
        expect(runs.first.paceSamples, isNull);
        expect(runs.first.rpe, isNull);
      },
    );

    test('ohne Tempowerte bleibt paceSamples null', () async {
      await w.seedRun(DateTime.utc(2030, 1, 5, 8), minutes: 20);
      final runs = await reader.load(withPaceSamples: false);
      expect(runs.single.paceSamples, isNull);
      expect(runs.single.movingSeconds, closeTo(1200, 5));
    });

    test(
      'paceSince: ältere Läufe bekommen keine Tempowerte, Läufe bleiben',
      () async {
        await w.seedRun(DateTime.utc(2030, 1, 5, 8), minutes: 20);
        await w.seedRun(DateTime.utc(2030, 1, 20, 8), minutes: 20);
        final runs = await reader.load(paceSince: DateTime.utc(2030, 1, 10));
        expect(runs, hasLength(2));
        expect(runs.first.paceSamples, isNotEmpty); // 20. Januar
        expect(runs.last.paceSamples, isNull); // 5. Januar
        // Der Stichtag selbst zählt noch.
        final onDay = await reader.load(paceSince: DateTime.utc(2030, 1, 5));
        expect(onDay.last.paceSamples, isNotEmpty);
      },
    );

    test('Datum ist der lokale Kalendertag des Laufendes', () async {
      // Ende 23:20 UTC + 2 h = nächster Tag lokal.
      await w.seedRun(
        DateTime.utc(2030, 1, 5, 23),
        minutes: 20,
        utcOffset: const Duration(hours: 2),
      );
      final r = (await reader.load()).single;
      expect(calendarDay(r.date), DateTime.utc(2030, 1, 6));
    });

    test(
      'Positionslücke: Zeit ohne die Lückenzeit, passend zur Distanz',
      () async {
        // 20 Minuten bei 3 m/s, aber 120 s ohne Positionen (Tunnel).
        final start = DateTime.utc(2030, 1, 5, 8);
        final run = await w.session.runs.create(startedAt: start);
        final positions = <RawPosition>[
          for (var s = 0; s <= 1200; s++)
            if (s < 500 || s > 620)
              RawPosition(
                time: start.add(Duration(seconds: s)),
                source: 'gps',
                latitude: 10 + s * 3.0 / 111195,
                longitude: 20,
                accuracyMeters: 5,
              ),
        ];
        await w.session.rawData.append(run.id, RawBatch(positions: positions));
        await w.session.runs.setState(
          run.id,
          RunState.finished,
          endedAt: start.add(const Duration(seconds: 1200)),
        );
        w.clock.set(start.add(const Duration(minutes: 30)));
        final overview = (await RunOverviewService(
          session: w.session,
          clock: w.clock,
        ).load()).single;
        // Voraussetzung des Tests: Die Lücke kostet Bewegungszeit.
        expect(overview.paceTime!, lessThan(overview.movingTime!));
        final r = (await reader.load(withPaceSamples: false)).single;
        expect(
          r.movingSeconds,
          overview.paceTime!.inMicroseconds / Duration.microsecondsPerSecond,
        );
        // Distanz und Zeit passen zusammen (3 m/s), nicht die lange Zeit.
        expect(r.distanceMeters! / r.movingSeconds, closeTo(3.0, 0.15));
      },
    );

    test('unfertiger Lauf und leerer Speicher: keine Läufe', () async {
      expect(await reader.load(), isEmpty);
      await w.session.runs.create(startedAt: DateTime.utc(2030, 1, 5, 8));
      expect(await reader.load(), isEmpty);
    });
  });
}
