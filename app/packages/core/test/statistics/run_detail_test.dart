import 'dart:isolate';
import 'dart:math' as math;

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
  (int, int)? noHeartRate,
  (int, int)? still,
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
    // Im Stillstand bleibt die Position stehen, das Signal läuft weiter.
    var metres = i * 3.0;
    if (still != null) {
      if (i >= still.$2) {
        metres = (i - (still.$2 - still.$1)) * 3.0;
      } else if (i >= still.$1) {
        metres = still.$1 * 3.0;
      }
    }
    final lost = noPosition != null && i >= noPosition.$1 && i < noPosition.$2;
    if (!lost) {
      pre.addPosition(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + metres / _mPerDeg,
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
    final noHr =
        noHeartRate != null && i >= noHeartRate.$1 && i < noHeartRate.$2;
    if (heartRate && !noHr) {
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

  test('Pulslücke trennt nur den Puls; Position läuft durch', () {
    final d = _detail(_run(300, noHeartRate: (100, 160)), 300);
    expect(d.heartRate, hasLength(2));
    expect(d.route, hasLength(1));
    expect(d.pace, hasLength(1));
    expect(d.altitude, hasLength(1));
    // Zwischen den Teilen liegt die Lücke, keine Linie über sie hinweg.
    expect(
      d.heartRate[1].first.seconds - d.heartRate[0].last.seconds,
      greaterThanOrEqualTo(60),
    );
  });

  test('Stillstand unterbricht die Pace-Linie, Route läuft durch', () {
    final d = _detail(_run(300, still: (100, 160)), 300);
    expect(d.pace, hasLength(2));
    expect(d.route, hasLength(1));
    expect(d.heartRate, hasLength(1));
    // Im Stillstand gibt es keinen Pace-Punkt.
    expect(d.pace[1].first.seconds - d.pace[0].last.seconds, greaterThan(30));
  });

  test('Ausdünnen behält die einzelne Spitze (Min/Max je Abschnitt)', () {
    const n = 3000;
    // Spitze und Tal (je 25 s), breit genug für den Median (30 s), aber
    // schmaler als der Abstand der Stützpunkte beim Ausdünnen.
    int bpm(int i) => i >= 1000 && i < 1025
        ? 162
        : (i >= 2000 && i < 2025 ? 122 : 140 + i % 3);
    final spiked = RunPreprocessor(
      start: _start,
      parameters: const PreprocessingParameters.v4(),
    );
    for (var i = 0; i <= n; i++) {
      spiked.addHeartRate(
        RawHeartRate(
          time: _start.add(Duration(seconds: i)),
          source: 'strap',
          bpm: bpm(i),
          contact: SensorContact.good,
        ),
      );
    }
    final full = _detail(
      spiked.result(at: _start.add(const Duration(seconds: n))),
      n,
      maxPoints: 100000,
    );
    final thin = _detail(
      spiked.result(at: _start.add(const Duration(seconds: n))),
      n,
      maxPoints: 40,
    );
    double hi(RunDetailData d) =>
        d.heartRate.expand((x) => x).map((x) => x.value).reduce(math.max);
    double lo(RunDetailData d) =>
        d.heartRate.expand((x) => x).map((x) => x.value).reduce(math.min);
    final points = thin.heartRate.fold<int>(0, (a, x) => a + x.length);
    expect(points, lessThanOrEqualTo(40));
    expect(
      points,
      lessThan(full.heartRate.fold<int>(0, (a, x) => a + x.length)),
    );
    expect(hi(thin), hi(full));
    expect(lo(thin), lo(full));
    expect(hi(full), greaterThan(155));
    expect(lo(full), lessThan(130));
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

  test(
    'Ausdünnen mit Lücke: Anfang und Ende jedes Teils bleiben (Puls, Pace)',
    () {
      final pre = _run(
        3000,
        noHeartRate: (1000, 1100),
        noPosition: (2000, 2100),
      );
      final full = _detail(pre, 3000, maxPoints: 100000);
      final thin = _detail(pre, 3000, maxPoints: 200);
      for (final (name, f, t) in [
        ('Puls', full.heartRate, thin.heartRate),
        ('Pace', full.pace, thin.pace),
      ]) {
        expect(f.length, greaterThan(1), reason: '$name hat eine Lücke');
        expect(t, hasLength(f.length), reason: name);
        expect(
          t.fold<int>(0, (n, p) => n + p.length),
          lessThan(f.fold<int>(0, (n, p) => n + p.length)),
          reason: '$name wurde ausgedünnt',
        );
        for (var i = 0; i < f.length; i++) {
          expect(t[i].first.seconds, f[i].first.seconds, reason: '$name $i');
          expect(t[i].last.seconds, f[i].last.seconds, reason: '$name $i');
        }
      }
    },
  );

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

  test('isolateOffload rechnet wirklich in einem anderen Isolate', () async {
    String? name(int _) => Isolate.current.debugName;
    expect(await inlineOffload(name, 0), Isolate.current.debugName);
    expect(await isolateOffload(name, 0), isNot(Isolate.current.debugName));
  });

  test(
    'Rechnung im eigenen Isolate: Daten sind sendbar, Ergebnis gleich',
    () async {
      final w = await RecalcWorld.create();
      final run = await w.session.runs.create(startedAt: _start);
      const n = 600;
      await w.session.rawData.append(
        run.id,
        RawBatch(
          positions: [
            for (var i = 0; i <= n; i++)
              if (i < 200 || i > 260)
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
        ),
      );
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: _start.add(const Duration(seconds: n)),
      );
      Future<(RunSummary, RunDetailData)> build(Offload offload) async {
        final summary = (await RunSummaryService(
          session: w.session,
          clock: w.clock,
          offload: offload,
        ).load(run.id))!;
        final detail = await offload(buildRunDetailJob, (
          pre: summary.preprocessing,
          start: summary.run.startedAt,
          end: summary.run.endedAt!,
          pauses: summary.manualPauses,
        ));
        return (summary, detail);
      }

      final (inlineSummary, inlineDetail) = await build(inlineOffload);
      final (isoSummary, isoDetail) = await build(isolateOffload);
      expect(isoDetail.route, hasLength(2));
      expect(
        [for (final p in isoDetail.route) p.length],
        [for (final p in inlineDetail.route) p.length],
      );
      expect(
        isoSummary.preprocessing.position.acceptedPoints.length,
        inlineSummary.preprocessing.position.acceptedPoints.length,
      );
      expect(
        isoSummary.figures.distanceMeters,
        inlineSummary.figures.distanceMeters,
      );
    },
  );

  test('Zusammenfassung: Wiedergabe läuft über den Offload', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
    final calls = <Object>[];
    Future<R> counting<A, R>(R Function(A) job, A argument) {
      calls.add(job);
      return inlineOffload(job, argument);
    }

    final summary = await RunSummaryService(
      session: w.session,
      clock: w.clock,
      offload: counting,
    ).load(id);
    expect(summary, isNotNull);
    // Eigene Wiedergabe; die Kurzfassung des Laufs fehlt, wird also über
    // denselben Offload gerechnet (zweiter Aufruf).
    expect(calls, everyElement(same(replayJob)));
    expect(calls.length, greaterThanOrEqualTo(2));
  });
}
