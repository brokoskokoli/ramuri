import 'package:core/core.dart';
import 'package:test/test.dart';

// Wartezeit von Abschnittsbeginn bis zum ersten Punkt (≤ PAR-004) zählt wie eine
// Lücke nicht in die Durchschnittspace (K20), ohne Doppelzählung mit einer
// Startlücke > PAR-004.
const double _mPerDeg = earthRadiusMeters * 3.141592653589793 / 180;
final DateTime _t0 = DateTime.utc(2030, 5, 1, 8);

/// 3 m/s, 1 Hz. Start: erster Punkt erst bei [startFix] s. Unterbrechung
/// [pauseAt, resumeAt) (pause/resume wie im Replay), danach erster Punkt bei
/// resumeAt + [resumeFix].
RunPreprocessing _run({
  required int total,
  int startFix = 0,
  int? pauseAt,
  int? resumeAt,
  int resumeFix = 0,
}) {
  final pre = RunPreprocessor(
    start: _t0,
    parameters: const PreprocessingParameters.v4(),
  );
  var m = 0.0;
  for (var i = startFix; i <= total; i++) {
    final t = _t0.add(Duration(seconds: i));
    if (pauseAt != null && i == pauseAt) pre.pause(t);
    if (resumeAt != null && i == resumeAt) pre.resume(t);
    if (pauseAt != null && i >= pauseAt && i < resumeAt! + resumeFix) {
      if (i >= resumeAt) m += 3;
      continue;
    }
    pre.addPosition(
      RawPosition(
        time: t,
        source: 'gps',
        latitude: 10 + m / _mPerDeg,
        longitude: 20,
        accuracyMeters: 5,
      ),
    );
    m += 3;
  }
  return pre.result(at: _t0.add(Duration(seconds: total)));
}

double _avg(RunPreprocessing p) {
  final t = p.movement.movingTime - movingTimeInPositionGaps(p);
  return t.inMicroseconds / 1e6 / (p.position.distanceMeters! / 1000);
}

void main() {
  group('Wartezeit auf den ersten Punkt (Ø-Pace, K20)', () {
    test('Start mit 8 s Wartezeit: 8 s sind Lückenzeit, Ø = Feldtempo', () {
      final p = _run(total: 480, startFix: 8);
      expect(p.position.gaps, isEmpty);
      expect(p.position.leadIns.length, 1);
      expect(movingTimeInPositionGaps(p), const Duration(seconds: 8));
      expect(_avg(p), closeTo(1000 / 3, 0.5));
    });

    test('Fortsetzen nach Pause mit 8 s Wartezeit: 8 s Lückenzeit', () {
      final p = _run(total: 548, pauseAt: 240, resumeAt: 300, resumeFix: 8);
      expect(p.position.gaps, isEmpty);
      expect(movingTimeInPositionGaps(p), const Duration(seconds: 8));
      expect(_avg(p), closeTo(1000 / 3, 1));
    });

    test('Pause vor dem ersten Punkt: die 5 s Wartezeit bis dahin sind '
        'Lückenzeit, Abfrage mittendrin gleich dem Ergebnis', () {
      final pre = RunPreprocessor(
        start: _t0,
        parameters: const PreprocessingParameters.v4(),
      );
      pre.pause(_t0.add(const Duration(seconds: 5)));
      // Stand während der Pause (kein offener Lead-in mehr).
      expect(
        movingTimeInPositionGaps(
          pre.result(at: _t0.add(const Duration(seconds: 8))),
        ),
        const Duration(seconds: 5),
      );
      pre.resume(_t0.add(const Duration(seconds: 20)));
      var m = 0.0;
      for (var i = 20; i <= 200; i++) {
        pre.addPosition(
          RawPosition(
            time: _t0.add(Duration(seconds: i)),
            source: 'gps',
            latitude: 10 + m / _mPerDeg,
            longitude: 20,
            accuracyMeters: 5,
          ),
        );
        m += 3;
      }
      final p = pre.result(at: _t0.add(const Duration(seconds: 200)));
      expect(p.position.gaps, isEmpty);
      expect(p.position.leadIns.length, 1);
      expect(movingTimeInPositionGaps(p), const Duration(seconds: 5));
    });

    test('12 s Wartezeit: eine Lücke, keine Doppelzählung', () {
      final p = _run(total: 552, pauseAt: 240, resumeAt: 300, resumeFix: 12);
      expect(p.position.gaps.length, 1);
      expect(p.position.leadIns, isEmpty);
      expect(movingTimeInPositionGaps(p), const Duration(seconds: 12));
      final s = _run(total: 492, startFix: 12);
      expect(s.position.gaps.length, 1);
      expect(movingTimeInPositionGaps(s), const Duration(seconds: 12));
    });

    test('genau PAR-004 (10 s) ist noch keine Lücke, zählt einmal', () {
      final p = _run(total: 490, startFix: 10);
      expect(p.position.gaps, isEmpty);
      expect(movingTimeInPositionGaps(p), const Duration(seconds: 10));
    });

    test('kein Punkt im Lead-in nach 5 s Stand der Abfrage: offen, zählt', () {
      final pre = RunPreprocessor(
        start: _t0,
        parameters: const PreprocessingParameters.v4(),
      );
      final p = pre.result(at: _t0.add(const Duration(seconds: 5)));
      expect(movingTimeInPositionGaps(p), const Duration(seconds: 5));
    });

    test('Kurzfassung und Kilometerabschnitte rechnen dasselbe', () {
      final p = _run(total: 548, pauseAt: 240, resumeAt: 300, resumeFix: 8);
      final stored = overviewOf(p, computedAt: _t0);
      final run = StoredRun(
        id: 1,
        state: RunState.finished,
        startedAt: _t0,
        endedAt: _t0.add(const Duration(seconds: 548)),
      );
      final o = RunOverview.fromStored(run, stored);
      expect(o.paceTime, p.movement.movingTime - movingTimeInPositionGaps(p));
      // Kilometerabschnitte: keine Lückenzeit, die Wartezeit ist in der Pace.
      final splits = computeKilometerSplits(p);
      expect(splits.splits.any((s) => s.hasPositionGap), isFalse);
    });

    test('Kilometer 1 mit 8 s Startwartezeit: kein Lückenhinweis, Pace ohne '
        'die 8 s, Zeit mit', () {
      final p = _run(total: 480, startFix: 8);
      final first = computeKilometerSplits(p).splits.first;
      expect(first.hasPositionGap, isFalse);
      expect(first.positionGapTime, Duration.zero);
      expect(first.time.inSeconds, greaterThan(330));
      expect(first.paceSecondsPerKm, closeTo(1000 / 3, 0.5));
      final withWait = first.time.inMicroseconds / 1e6;
      expect(first.paceSecondsPerKm, lessThan(withWait - 5));
    });
  });
}
