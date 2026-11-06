import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

const double _mPerDeg = earthRadiusMeters * 3.141592653589793 / 180;
final DateTime _start = DateTime.utc(2026, 5, 1, 8);

/// Läuft [seconds] mit 3 m/s nach Norden, Puls und Höhe je Sekunde. In
/// [noPosition] (Sekunden) kommen keine Positionen; [pause] ist eine manuelle
/// Pause (von, bis).
RunPreprocessing _run(
  int seconds, {
  (int, int)? noPosition,
  (int, int)? pause,
  bool heartRate = true,
}) {
  final pre = RunPreprocessor(
    start: _start,
    parameters: const PreprocessingParameters.v4(),
  );
  for (var i = 0; i <= seconds; i++) {
    final t = _start.add(Duration(seconds: i));
    if (pause != null && i == pause.$1) pre.pause(t);
    if (pause != null && i == pause.$2) pre.resume(t);
    final paused = pause != null && i >= pause.$1 && i < pause.$2;
    if (paused) continue;
    final lost = noPosition != null && i >= noPosition.$1 && i < noPosition.$2;
    if (!lost) {
      pre.addPosition(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + i * 3 / _mPerDeg,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      pre.addAltitude(
        RawAltitude(
          time: t,
          source: 'gps',
          meters: 100 + (i % 60).toDouble(),
          verticalAccuracyMeters: 3,
        ),
      );
    }
    if (heartRate) {
      pre.addHeartRate(
        RawHeartRate(
          time: t,
          source: 'strap',
          bpm: 140 + i % 10,
          contact: SensorContact.good,
        ),
      );
    }
  }
  return pre.result(at: _start.add(Duration(seconds: seconds)));
}

RunDetailData _detail(
  RunPreprocessing pre,
  int seconds, {
  List<TimeSpan> pauses = const [],
  int maxPoints = 2000,
}) => buildRunDetail(
  pre,
  start: _start,
  end: _start.add(Duration(seconds: seconds)),
  pauses: pauses,
  maxPoints: maxPoints,
);

void main() {
  test('Lauf ohne Lücke: je Reihe ein zusammenhängender Teil', () {
    final d = _detail(_run(300), 300);
    expect(d.route, hasLength(1));
    expect(d.pace, hasLength(1));
    expect(d.heartRate, hasLength(1));
    expect(d.altitude, hasLength(1));
    expect(d.totalSeconds, 300);
    expect(d.pace.single.first.value, closeTo(1000 / 3, 1));
  });

  test('Positionslücke trennt Route, Pace und Höhe; Puls läuft durch', () {
    final d = _detail(_run(300, noPosition: (100, 160)), 300);
    expect(d.route, hasLength(2));
    expect(d.pace, hasLength(2));
    expect(d.altitude, hasLength(2));
    expect(d.heartRate, hasLength(1));
    // Der Sprung zwischen den Teilen ist nicht Teil einer Linie.
    expect(d.route[0].last.latitude, lessThan(d.route[1].first.latitude));
    expect(d.route[0].length + d.route[1].length, greaterThan(200));
  });

  test('Manuelle Pause trennt alle Reihen', () {
    final pre = _run(300, pause: (100, 130));
    final d = _detail(
      pre,
      300,
      pauses: [
        TimeSpan(
          start: _start.add(const Duration(seconds: 100)),
          end: _start.add(const Duration(seconds: 130)),
        ),
      ],
    );
    expect(d.route, hasLength(2));
    expect(d.pace, hasLength(2));
    expect(d.heartRate, hasLength(2));
    expect(d.altitude, hasLength(2));
    expect(d.pauses.single.start, 100);
    expect(d.pauses.single.end, 130);
  });

  test('Lauf ohne Puls: keine Pulsreihe, nie 0', () {
    final d = _detail(_run(120, heartRate: false), 120);
    expect(d.hasHeartRate, isFalse);
    expect(d.heartRate, isEmpty);
    expect(d.hasRoute, isTrue);
  });

  test('Ausdünnen begrenzt die Punkte, erhält Teile, Anfang und Ende', () {
    final pre = _run(3000, noPosition: (1000, 1100));
    final full = _detail(pre, 3000, maxPoints: 100000);
    final thin = _detail(pre, 3000, maxPoints: 200);
    expect(thin.route, hasLength(full.route.length));
    final points = thin.route.fold<int>(0, (n, p) => n + p.length);
    expect(points, lessThanOrEqualTo(210));
    for (var i = 0; i < thin.route.length; i++) {
      expect(thin.route[i].first.latitude, full.route[i].first.latitude);
      expect(thin.route[i].last.latitude, full.route[i].last.latitude);
    }
    expect(thin.pace, hasLength(full.pace.length));
    expect(
      thin.heartRate.single.first.seconds,
      full.heartRate.single.first.seconds,
    );
  });

  test('Messung: vier Stunden mit 1 Hz', () {
    final sw = Stopwatch()..start();
    final pre = _run(14400, noPosition: (5000, 5100));
    final prepared = sw.elapsedMilliseconds;
    sw.reset();
    final d = _detail(pre, 14400);
    final built = sw.elapsedMilliseconds;
    final points = d.route.fold<int>(0, (n, p) => n + p.length);
    // ignore: avoid_print
    print(
      'MESSUNG 4h: Vorverarbeitung ${prepared}ms, Zeichendaten ${built}ms, '
      'Routenpunkte $points von ${pre.position.acceptedPoints.length}',
    );
    expect(points, lessThanOrEqualTo(2010));
    expect(d.route, hasLength(2));
  });

  test(
    'Messung: Zusammenfassung eines Vier-Stunden-Laufs aus dem Speicher',
    () async {
      final w = await RecalcWorld.create();
      final run = await w.session.runs.create(startedAt: _start);
      const n = 14400;
      await w.session.rawData.append(
        run.id,
        RawBatch(
          positions: [
            for (var i = 0; i <= n; i++)
              if (i < 5000 || i > 5100)
                RawPosition(
                  time: _start.add(Duration(seconds: i)),
                  source: 'gps',
                  latitude: 10 + i * 3 / _mPerDeg,
                  longitude: 20,
                  accuracyMeters: 5,
                ),
          ],
          heartRates: [
            for (var i = 0; i <= n; i++)
              RawHeartRate(
                time: _start.add(Duration(seconds: i)),
                source: 'strap',
                bpm: 150,
                contact: SensorContact.good,
              ),
          ],
          altitudes: [
            for (var i = 0; i <= n; i++)
              RawAltitude(
                time: _start.add(Duration(seconds: i)),
                source: 'gps',
                meters: 100 + (i % 60).toDouble(),
                verticalAccuracyMeters: 3,
              ),
          ],
        ),
      );
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: _start.add(const Duration(seconds: n)),
      );
      final sw = Stopwatch()..start();
      final summary = (await RunSummaryService(
        session: w.session,
        clock: w.clock,
      ).load(run.id))!;
      final loaded = sw.elapsedMilliseconds;
      sw.reset();
      final d = buildRunDetail(
        summary.preprocessing,
        start: summary.run.startedAt,
        end: summary.run.endedAt!,
      );
      // ignore: avoid_print
      print(
        'MESSUNG 4h Speicher: Lesen+Wiedergabe+Zusammenfassung ${loaded}ms, '
        'Zeichendaten ${sw.elapsedMilliseconds}ms',
      );
      expect(d.route, hasLength(2));
      expect(d.heartRate.fold<int>(0, (a, p) => a + p.length), lessThan(2010));
    },
  );
}
