import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

void main() {
  group('Kennzahlen eines Laufs aus den gespeicherten Rohdaten', () {
    Future<(RunFigures, StoredRun)> figuresOf(RecalcWorld w, int id) async {
      final run = (await w.session.runs.get(id))!;
      final raw = await w.session.rawData.read(id);
      final gaps = await w.session.markers.gaps(id);
      final pre = replayRunPreprocessing(
        run: run,
        end: run.endedAt!,
        raw: raw,
        gaps: gaps,
        parameters: const PreprocessingParameters.v3(),
      );
      return (RunFigures.fromRun(run: run, preprocessing: pre), run);
    }

    test('30 min mit 3 m/s: Strecke, Pace, Bestpace, Puls, Tag', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(
        DateTime.utc(2030, 2, 25, 23, 0),
        utcOffset: const Duration(hours: 2),
      );
      final (f, run) = await figuresOf(w, id);
      expect(f.distanceMeters, closeTo(5400, 5));
      expect(f.averagePaceSecondsPerKm, closeTo(1000 / 3, 1));
      expect(f.bestPaceSecondsPerKm, closeTo(1000 / 3, 1));
      expect(f.heartRateAverageBpm, 150);
      expect(f.heartRateMaxBpm, 150);
      expect(f.heartRateSampleCount, greaterThan(1000));
      // Ende 23:30 UTC + 2 h = 01:30 am Folgetag (lokaler Kalendertag, K21).
      expect(f.day, '2030-02-26');
      expect(f.day, dayOfRun(run));
      expect(f.trimpPoints, isNull); // nicht übergeben: nicht verfügbar
      expect(f.zoneTimes, isNull);
    });

    test('Lauf ohne Puls: kein Durchschnitt, kein Maximum, keine 0', () async {
      final w = await RecalcWorld.create();
      final run = await w.session.runs.create(
        startedAt: DateTime.utc(2030, 2, 1, 8),
      );
      final start = DateTime.utc(2030, 2, 1, 8);
      await w.session.rawData.append(
        run.id,
        RawBatch(
          positions: [
            for (var s = 0; s <= 600; s++)
              RawPosition(
                time: start.add(Duration(seconds: s)),
                source: 'gps',
                latitude: 10 + s * 3.0 / 111194.9,
                longitude: 20,
                accuracyMeters: 5,
              ),
          ],
        ),
      );
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(seconds: 600)),
      );
      final (f, _) = await figuresOf(w, run.id);
      expect(f.heartRateAverageBpm, isNull);
      expect(f.heartRateMaxBpm, isNull);
      expect(f.heartRateSampleCount, 0);
      expect(f.distanceMeters, isNotNull);
      // 1800 m: Bestpace vorhanden; ein Lauf unter 1 km hätte keine.
      expect(f.bestPaceSecondsPerKm, isNotNull);
      expect(f.day, '2030-02-01'); // ohne Versatz gilt der UTC-Tag
    });

    test('Lauf unter 1 km: Bestpace nicht verfügbar', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 4);
      final (f, _) = await figuresOf(w, id); // 720 m
      expect(f.distanceMeters, lessThan(1000));
      expect(f.bestPaceSecondsPerKm, isNull);
      expect(f.averagePaceSecondsPerKm, isNotNull);
    });

    test('nicht beendeter Lauf wird abgelehnt', () async {
      final w = await RecalcWorld.create();
      final run = await w.session.runs.create(
        startedAt: DateTime.utc(2030, 2, 1, 8),
      );
      final pre = RunPreprocessor(start: run.startedAt)
          .result(at: run.startedAt);
      expect(
        () => RunFigures.fromRun(run: run, preprocessing: pre),
        throwsArgumentError,
      );
    });

    test('Positionslücke in Bewegung zählt nicht zur Pace-Zeit (K20)', () {
      final start = DateTime.utc(2030, 2, 1, 8);
      final r = RunPreprocessor(start: start);
      for (var s = 0; s <= 600; s++) {
        if (s > 300 && s < 330) continue; // 30 s ohne Position
        r.addPosition(
          RawPosition(
            time: start.add(Duration(seconds: s)),
            source: 'gps',
            latitude: 10 + s * 3.0 / 111194.9,
            longitude: 20,
            accuracyMeters: 5,
          ),
        );
      }
      final pre = r.result(at: start.add(const Duration(seconds: 600)));
      final loss = movingTimeInPositionGaps(pre);
      expect(loss.inSeconds, inInclusiveRange(25, 35));
    });
  });
}
