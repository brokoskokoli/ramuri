import 'package:core/core.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

/// Treibt eine Sitzung und merkt sich die Rohpunkte so, wie sie sie bekommt
/// (Punktzeit = Empfang minus Alter), damit die Historie dieselben Daten
/// neu rechnen kann (K20).
class _Drive {
  final clock = FakeClock(t0);
  late final s = RecordingSession(clock: clock);
  final raw = <StoredRaw<RawPosition>>[];
  final manual = <StoredGap>[];
  double north = 0;

  void point({int ageMs = 0, double? at}) {
    final n = at ?? north;
    s.addPosition(
      LocationSample(
        time: clock.now(),
        ageMs: ageMs,
        latitude: 10 + n / 111195,
        longitude: 20,
        accuracyMeters: 5,
      ),
    );
    raw.add(
      StoredRaw(
        raw.length,
        RawPosition(
          time: clock.now().subtract(Duration(milliseconds: ageMs)),
          source: 'gps',
          latitude: 10 + n / 111195,
          longitude: 20,
          accuracyMeters: 5,
        ),
      ),
    );
  }

  void move(int seconds) {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      north += 3;
      point();
    }
  }

  void wait(int seconds) => clock.advance(Duration(seconds: seconds));

  void pause() {
    s.pause();
    manual.add(
      StoredGap(
        id: manual.length,
        kind: RunGapKind.manualPause,
        start: clock.now(),
      ),
    );
  }

  void resume() {
    s.resume();
    final g = manual.removeLast();
    manual.add(
      StoredGap(id: g.id, kind: g.kind, start: g.start, end: clock.now()),
    );
  }

  RunPreprocessing replay({required DateTime end, bool finished = true}) {
    return replayRunPreprocessing(
      run: StoredRun(
        id: 1,
        state: finished ? RunState.finished : RunState.active,
        startedAt: t0,
        endedAt: finished ? end : null,
      ),
      end: end,
      raw: StoredRawData(
        positions: raw,
        heartRates: const [],
        altitudes: const [],
        steps: const [],
        unavailable: const [],
      ),
      gaps: manual,
      parameters: const PreprocessingParameters.v4(),
    );
  }
}

void main() {
  group('Lückenzeit in Bewegung: Live gleich Historie (K20)', () {
    test('verspäteter Punkt: Empfang nach 12 s, Messzeit 9 s: keine Lücke', () {
      final d = _Drive()..s.start();
      d.move(60);
      d.wait(12);
      d.north += 36;
      d.point(ageMs: 3000); // Fix 9 s nach dem letzten Punkt gemessen
      d.move(60);
      final live = d.s.snapshot().positionLossMovingTime;
      final pre = d.replay(end: d.clock.now());
      final history = movingTimeInPositionGaps(pre);
      expect(pre.position.gaps, isEmpty);
      // Nur die 1 s vom Start bis zum ersten Punkt (Wartezeit, keine Lücke).
      expect(history, const Duration(seconds: 1));
      expect(live, history);
    });

    test('Lücke, manuelle Pause und Neuverankerung: Snapshot gleich '
        'Neuberechnung, auch während die Lücke offen ist', () {
      final d = _Drive()..s.start();
      d.move(60);
      d.wait(15); // echte Lücke (> PAR-004)
      d.move(30);
      d.pause();
      d.wait(20);
      d.resume();
      d.move(30);
      // Positionssprung: drei zueinander passende Punkte 2 km entfernt.
      for (var i = 0; i < 4; i++) {
        d.wait(1);
        d.point(at: d.north + 2000 + i * 3);
      }
      d.north += 2012;
      d.move(30);

      // Offene Lücke: 14 s ohne Punkt, Zwischenstand.
      d.wait(14);
      final openLive = d.s.snapshot().positionLossMovingTime;
      final openHistory = movingTimeInPositionGaps(
        d.replay(end: d.clock.now(), finished: false),
      );
      expect(openHistory, greaterThan(Duration.zero));
      expect(openLive, openHistory);

      d.move(10);
      d.s.finish();
      final end = d.clock.now();
      final pre = d.replay(end: end);
      final live = d.s.snapshot();
      expect(pre.position.gaps.length, greaterThanOrEqualTo(2));
      expect(live.positionLossMovingTime, movingTimeInPositionGaps(pre));
      expect(live.movingTime, pre.movement.movingTime);
      expect(live.distanceMeters, pre.position.distanceMeters);
      // Die Pace-Zeit der Historie ist dieselbe Differenz wie live.
      final figures = RunFigures.fromRun(
        run: StoredRun(
          id: 1,
          state: RunState.finished,
          startedAt: t0,
          endedAt: end,
        ),
        preprocessing: pre,
        laps: const [],
      );
      expect(figures.paceTime, live.movingTime! - live.positionLossMovingTime);
    });
  });
}
