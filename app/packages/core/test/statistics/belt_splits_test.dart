import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// WP25 B2: Kilometerabschnitte eines Bandlaufs aus dem Bandverlauf.
final _t0 = DateTime.utc(2030, 2, 25, 8);

BeltTrack _track(List<(int, int, double)> parts) => BeltTrack([
  for (final (a, b, v) in parts)
    BeltPiece(
      span: TimeSpan(
        start: _t0.add(Duration(seconds: a)),
        end: _t0.add(Duration(seconds: b)),
      ),
      speedMetersPerSecond: v,
      inclinePercent: 0,
    ),
]);

void main() {
  late RecalcWorld w;
  setUp(() async => w = await RecalcWorld.create());

  Future<RunPreprocessing> pre(int seconds, {int bpm = 150}) async {
    final run = await w.session.runs.create(
      startedAt: _t0,
      mode: RunMode.treadmill,
    );
    await w.session.rawData.append(
      run.id,
      RawBatch(
        heartRates: [
          for (var s = 0; s <= seconds; s++)
            RawHeartRate(
              time: _t0.add(Duration(seconds: s)),
              source: 'strap',
              bpm: s < 300 ? bpm : bpm + 20,
              contact: SensorContact.good,
            ),
        ],
      ),
    );
    final end = _t0.add(Duration(seconds: seconds));
    await w.session.runs.setState(run.id, RunState.finished, endedAt: end);
    final stored = (await w.session.runs.get(run.id))!;
    return replayRunPreprocessing(
      run: stored,
      end: end,
      raw: await w.session.rawData.read(run.id),
      gaps: const [],
      parameters: const PreprocessingParameters.v4(),
    );
  }

  test('Geschwindigkeitswechsel, Stillstand und angebrochener Rest', () async {
    // 0-250 s mit 2 m/s (500 m), 250-350 s Stillstand, 350-1000 s mit 4 m/s
    // (2600 m): 3100 m, Grenzen bei 1000 m (Zeit 250+125 s) und 2000 m.
    final belt = _track([(0, 250, 2), (250, 350, 0), (350, 1000, 4)]);
    final s = computeBeltSplits(await pre(1000), belt);
    expect(s.splits.map((x) => x.lengthMeters), [1000, 1000, 1000, 100]);
    expect(s.splits.map((x) => x.isPartial), [false, false, false, true]);
    // Km 1: 250 s + 125 s Bewegung (Stillstand zählt nicht).
    expect(s.splits[0].time, const Duration(seconds: 375));
    expect(s.splits[0].paceSecondsPerKm, closeTo(375, 1e-6));
    expect(s.splits[1].time, const Duration(seconds: 250));
    expect(s.splits[1].paceSecondsPerKm, closeTo(250, 1e-6));
    expect(s.splits[3].time, const Duration(seconds: 25));
    // Summe = Bewegungszeit des Bandes.
    final sum = s.splits.fold(Duration.zero, (a, x) => a + x.time);
    expect(sum, belt.moving);
    expect(s.marks, isEmpty);
    expect(s.ascentMeters, isNull);
    expect(s.splits.every((x) => !x.hasPositionGap), isTrue);
    // Puls: Wechsel bei 300 s liegt in Km 1 (Mittel 150 und 170 gewichtet).
    expect(s.splits[1].heartRateAverageBpm, 170);
  });

  test(
    'computeKilometerSplits mit belt rechnet aus dem Band, in Meilen',
    () async {
      final p = await pre(600);
      final belt = _track([(0, 600, 3)]);
      final s = computeKilometerSplits(p, unitMeters: mileMeters, belt: belt);
      expect(s.splits, hasLength(2)); // 1800 m = 1 Meile + 190,656 m
      expect(s.splits.first.lengthMeters, mileMeters);
      expect(s.splits.last.isPartial, isTrue);
      expect(s.splits.last.lengthMeters, closeTo(1800 - mileMeters, 1e-6));
    },
  );

  test(
    'genau voller Abschnitt: kein angebrochener Rest; ohne Bewegung leer',
    () async {
      final p = await pre(400);
      expect(computeBeltSplits(p, _track([(0, 250, 4)])).splits, hasLength(1));
      expect(computeBeltSplits(p, _track([(0, 250, 0)])).splits, isEmpty);
    },
  );

  test(
    'Mittelwerte des Bandes: Geschwindigkeit, Steigung nur wenn bekannt',
    () {
      final t = BeltTrack([
        BeltPiece(
          span: TimeSpan(
            start: _t0,
            end: _t0.add(const Duration(seconds: 100)),
          ),
          speedMetersPerSecond: 3,
          inclinePercent: 1,
        ),
        BeltPiece(
          span: TimeSpan(
            start: _t0.add(const Duration(seconds: 100)),
            end: _t0.add(const Duration(seconds: 400)),
          ),
          speedMetersPerSecond: 4,
          inclinePercent: 3,
        ),
      ]);
      expect(t.averageSpeedMetersPerSecond, closeTo(1500 / 400, 1e-9));
      expect(t.averageInclinePercent, closeTo(2.5, 1e-9));
      final unknown = BeltTrack([
        ...t.pieces,
        BeltPiece(
          span: TimeSpan(
            start: _t0.add(const Duration(seconds: 400)),
            end: _t0.add(const Duration(seconds: 500)),
          ),
          speedMetersPerSecond: 3,
          inclinePercent: null,
        ),
      ]);
      expect(unknown.averageInclinePercent, isNull);
    },
  );
}
