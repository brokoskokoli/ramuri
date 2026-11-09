import 'package:core/core.dart';
import 'package:test/test.dart';

const double _mPerDeg = earthRadiusMeters * 3.141592653589793 / 180;
final DateTime _start = DateTime.utc(2030, 5, 1, 8);

/// Läuft [seconds] mit 3 m/s nach Norden. In [noPosition] (Sekunden) kommen
/// keine Positionen; [pause] ist eine manuelle Pause (von, bis).
RunPreprocessing _run(
  int seconds, {
  (int, int)? noPosition,
  (int, int)? pause,
  bool heartRate = true,
  int tail = 0,
}) {
  final pre = RunPreprocessor(
    start: _start,
    parameters: const PreprocessingParameters.v4(),
  );
  var metres = 0.0;
  for (var i = 0; i <= seconds; i++) {
    final t = _start.add(Duration(seconds: i));
    if (pause != null && i == pause.$1) pre.pause(t);
    if (pause != null && i == pause.$2) pre.resume(t);
    if (pause != null && i >= pause.$1 && i < pause.$2) continue;
    // Die Strecke läuft in der Lücke weiter (Läufer unterwegs ohne Signal).
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
    }
    if (heartRate) {
      pre.addHeartRate(
        RawHeartRate(
          time: t,
          source: 'strap',
          bpm: 140 + i ~/ 100,
          contact: SensorContact.good,
        ),
      );
    }
    metres += 3.0;
  }
  return pre.result(at: _start.add(Duration(seconds: seconds + tail)));
}

/// 1000 m mit 4 m/s (250 s), dann steht der Läufer [stillSeconds] Sekunden mit
/// laufenden Positionen (unter der Mindestdauer des Stillstands, also noch
/// Bewegungszeit). Der Rest ist 4 m lang und braucht 1 + [stillSeconds]
/// Sekunden.
RunPreprocessing _restRun(
  int stillSeconds, {
  PreprocessingParameters parameters = const PreprocessingParameters.v4(),
}) {
  final pre = RunPreprocessor(start: _start, parameters: parameters);
  RawPosition at(int i, double metres) => RawPosition(
    time: _start.add(Duration(seconds: i)),
    source: 'gps',
    latitude: 10 + metres / _mPerDeg,
    longitude: 20,
    accuracyMeters: 5,
  );
  for (var i = 0; i <= 251; i++) {
    pre.addPosition(at(i, i * 4.0));
  }
  for (var k = 1; k <= stillSeconds; k++) {
    pre.addPosition(at(251 + k, 251 * 4.0));
  }
  return pre.result(at: _start.add(Duration(seconds: 251 + stillSeconds)));
}

Duration _sum(KilometerSplits s) =>
    s.splits.fold(Duration.zero, (a, b) => a + b.time);

void main() {
  test('Methode und Version tragen die Kennung (NFR-0001, NFR-0005)', () {
    final s = computeKilometerSplits(_run(60));
    expect(s.method, 'kilometer-splits');
    expect(s.methodVersion, 1);
  });

  test('volle Kilometer plus angebrochener letzter mit Länge', () {
    final pre = _run(1200); // 3600 m
    final s = computeKilometerSplits(pre);
    expect(s.splits.map((e) => e.index), [1, 2, 3, 4]);
    expect(s.splits.take(3).every((e) => !e.isPartial), isTrue);
    expect(s.splits.take(3).every((e) => e.lengthMeters == 1000), isTrue);
    final last = s.splits.last;
    expect(last.isPartial, isTrue);
    expect(last.lengthMeters, closeTo(600, 1));
    // 3 m/s: 333,3 s/km
    for (final e in s.splits) {
      expect(e.paceSecondsPerKm, closeTo(333.3, 0.5));
    }
    expect(s.marks.map((m) => m.index), [1, 2, 3]);
  });

  test('FR-0211: Summe der Kilometerzeiten gleich Bewegungszeit', () {
    final pre = _run(1200);
    expect(pre.movement.movingTime, greaterThan(Duration.zero));
    expect(_sum(computeKilometerSplits(pre)), pre.movement.movingTime);
  });

  test('Summe gleich Bewegungszeit auch mit Pause', () {
    final pre = _run(1500, pause: (300, 500));
    final s = computeKilometerSplits(pre);
    expect(pre.movement.movingTime, lessThan(pre.movement.totalTime));
    expect(_sum(s), pre.movement.movingTime);
    // Die Pause zählt nicht zur Pace. Die Sekunde zwischen dem letzten Punkt
    // (s 299) und der Pause (s 300) trägt keine Strecke: Der erste Kilometer
    // braucht 1 s mehr, alle anderen exakt 3 m/s.
    expect(s.splits.first.paceSecondsPerKm, closeTo(334.33, 0.01));
    for (final e in s.splits.skip(1)) {
      expect(e.paceSecondsPerKm, closeTo(333.33, 0.01));
    }
  });

  test(
    'Summe gleich Bewegungszeit mit GPS-Lücke; Kilometer gekennzeichnet',
    () {
      final pre = _run(1500, noPosition: (150, 250));
      expect(pre.position.gaps, isNotEmpty);
      final s = computeKilometerSplits(pre);
      expect(_sum(s), pre.movement.movingTime);
      final flagged = [
        for (final e in s.splits)
          if (e.hasPositionGap) e.index,
      ];
      expect(flagged, [1]);
      // Pace ohne Lückenzeit (K20), nicht von der Lücke verfälscht.
      expect(s.splits.first.paceSecondsPerKm, closeTo(333.33, 0.01));
      expect(s.splits.first.time, greaterThan(const Duration(seconds: 400)));
      expect(s.splits[1].hasPositionGap, isFalse);
    },
  );

  test('Puls: Durchschnitt je Kilometer, null statt 0 ohne Puls', () {
    final withHr = computeKilometerSplits(_run(1200));
    for (final e in withHr.splits) {
      expect(e.heartRateAverageBpm, inInclusiveRange(140, 152));
    }
    expect(
      withHr.splits.first.heartRateAverageBpm!,
      lessThan(withHr.splits.last.heartRateAverageBpm!),
    );
    final without = computeKilometerSplits(_run(1200, heartRate: false));
    expect(without.splits, isNotEmpty);
    for (final e in without.splits) {
      expect(e.heartRateAverageBpm, isNull);
    }
  });

  test('Puls fehlt nur in einem Kilometer: dort null, sonst Wert', () {
    final pre = RunPreprocessor(
      start: _start,
      parameters: const PreprocessingParameters.v4(),
    );
    for (var i = 0; i <= 700; i++) {
      final t = _start.add(Duration(seconds: i));
      pre.addPosition(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + i * 3.0 / _mPerDeg,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      // Puls nur im ersten Kilometer (bis 330 s).
      if (i < 330) {
        pre.addHeartRate(
          RawHeartRate(
            time: t,
            source: 'strap',
            bpm: 150,
            contact: SensorContact.good,
          ),
        );
      }
    }
    final s = computeKilometerSplits(
      pre.result(at: _start.add(const Duration(seconds: 700))),
    );
    expect(s.splits.first.heartRateAverageBpm, 150);
    expect(s.splits[1].heartRateAverageBpm, isNull);
  });

  test('Meilen statt Kilometer (NFR-0006)', () {
    final pre = _run(1200); // 3600 m = 2 Meilen + 381 m
    final s = computeKilometerSplits(pre, unitMeters: mileMeters);
    expect(s.unitMeters, mileMeters);
    expect(s.splits.length, 3);
    expect(s.splits.first.lengthMeters, mileMeters);
    expect(s.splits.last.isPartial, isTrue);
    expect(s.splits.last.lengthMeters, closeTo(3600 - 2 * mileMeters, 1));
    expect(_sum(s), pre.movement.movingTime);
  });

  test('Kilometermarken liegen auf der Route bei 1000 m, 2000 m', () {
    final s = computeKilometerSplits(_run(1200));
    expect(s.marks.length, 3);
    for (final m in s.marks) {
      expect(
        m.position.latitude,
        closeTo(10 + m.index * 1000 / _mPerDeg, 1e-5),
      );
      expect(m.position.longitude, 20);
    }
  });

  test('genau voller letzter Kilometer ohne angebrochenen Abschnitt', () {
    final pre = _run(1000); // 3000 m
    final s = computeKilometerSplits(pre);
    expect(s.splits.length, 3);
    expect(s.splits.every((e) => !e.isPartial), isTrue);
    expect(_sum(s), pre.movement.movingTime);
  });

  test('genau voller letzter Kilometer mit Bewegungszeit danach', () {
    // Der letzte Punkt liegt bei 3000 m; der Lauf geht danach noch 20 s weiter
    // (Zeit ohne neue Strecke). Die Summe bleibt die Bewegungszeit.
    final pre = _run(1000, tail: 20);
    final bare = _run(1000);
    expect(
      pre.movement.movingTime,
      greaterThan(bare.movement.movingTime),
      reason: 'die Zeit danach zählt als Bewegung',
    );
    final s = computeKilometerSplits(pre);
    expect(_sum(s), pre.movement.movingTime);
  });

  test('Puls im Stillstand ohne Autopause zählt nicht zum Kilometermittel', () {
    final pre = RunPreprocessor(
      start: _start,
      parameters: const PreprocessingParameters.v4(),
    );
    // 100 s mit 3 m/s bei 150 bpm, dann 60 s Stillstand; der Puls steigt dabei
    // langsam (0,5 bpm/s), damit ihn der Ausreißerfilter nicht verwirft.
    for (var i = 0; i <= 160; i++) {
      final t = _start.add(Duration(seconds: i));
      pre.addPosition(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + (i < 100 ? i : 100) * 3.0 / _mPerDeg,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      pre.addHeartRate(
        RawHeartRate(
          time: t,
          source: 'strap',
          bpm: i < 100 ? 150 : 150 + (i - 100) ~/ 2,
          contact: SensorContact.good,
        ),
      );
    }
    final r = pre.result(at: _start.add(const Duration(seconds: 160)));
    expect(r.heartRate.acceptedValues.last.bpm, greaterThan(170));
    final s = computeKilometerSplits(r);
    expect(s.splits.single.heartRateAverageBpm, closeTo(150, 1));
  });

  test('unter einem Kilometer: nur der angebrochene Abschnitt', () {
    final pre = _run(100); // 300 m
    final s = computeKilometerSplits(pre);
    expect(s.splits.length, 1);
    expect(s.splits.single.isPartial, isTrue);
    expect(s.splits.single.lengthMeters, closeTo(300, 1));
    expect(s.marks, isEmpty);
    expect(_sum(s), pre.movement.movingTime);
  });

  test('ohne Strecke keine Abschnitte', () {
    final pre = RunPreprocessor(start: _start);
    final s = computeKilometerSplits(
      pre.result(at: _start.add(const Duration(minutes: 5))),
    );
    expect(s.splits, isEmpty);
    expect(s.marks, isEmpty);
    expect(s.ascentMeters, isNull);
    expect(s.descentMeters, isNull);
  });

  test('Anstieg und Gefälle sind die des Höhenprofils', () {
    final pre = RunPreprocessor(start: _start);
    // Rampe 10 m hoch (je 5 m, Schwelle 3 m), dann 6 m herunter.
    final heights = <double>[
      100.0,
      105,
      110,
      110,
      110,
      110,
      110,
      104,
      104,
      104,
      104,
      104,
      104,
    ];
    for (var i = 0; i < heights.length; i++) {
      final t = _start.add(Duration(seconds: i * 40));
      pre.addPosition(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + i * 100 / _mPerDeg,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      pre.addAltitude(
        RawAltitude(
          time: t,
          source: 'gps',
          meters: heights[i],
          verticalAccuracyMeters: 3,
        ),
      );
    }
    final r = pre.result(at: _start.add(const Duration(seconds: 520)));
    final s = computeKilometerSplits(r);
    expect(s.ascentMeters, r.altitude.ascentMeters);
    expect(s.descentMeters, r.altitude.descentMeters);
    expect(s.ascentMeters, greaterThan(0));
    expect(s.descentMeters, greaterThan(0));
    // Netto stimmt mit dem geglätteten Profil überein (Schwelle 3 m).
    final net =
        r.altitude.smoothed.last.meters - r.altitude.smoothed.first.meters;
    expect(s.ascentMeters! - s.descentMeters!, closeTo(net, 3));
  });

  group('Rest-Pace unter der Stillstandsgrenze (OQ-0076, PAR-014)', () {
    test(
      'knapp darunter: keine Pace, Länge und Zeit bleiben, Summe stimmt',
      () {
        // Rest 4 m in 8 s = 0,4999... m/s.
        final pre = _restRun(7);
        final s = computeKilometerSplits(pre);
        final rest = s.splits.last;
        expect(rest.isPartial, isTrue);
        expect(rest.lengthMeters, closeTo(4, 1e-6));
        expect(rest.time, const Duration(seconds: 8));
        expect(rest.paceSecondsPerKm, isNull);
        expect(s.splits.first.paceSecondsPerKm, closeTo(250, 0.01));
        expect(_sum(s), pre.movement.movingTime);
      },
    );

    test('knapp darüber: die Pace bleibt', () {
      // Rest 4 m in 7 s = 0,57 m/s.
      final pre = _restRun(6);
      final s = computeKilometerSplits(pre);
      expect(s.splits.last.paceSecondsPerKm, closeTo(1750, 0.01));
      expect(_sum(s), pre.movement.movingTime);
    });

    test(
      'genau auf der Grenze gilt noch als Bewegung, ein Haar darüber nicht',
      () {
        final length = computeKilometerSplits(_restRun(7))
            .splits
            .last
            .lengthMeters;
        final speed = length / 8; // der Rest braucht genau 8 s
        final exact = computeKilometerSplits(
          _restRun(
            7,
            parameters: PreprocessingParameters(
              parameterVersion: currentParameterVersion,
              standstillBelow: speed,
            ),
          ),
        );
        expect(exact.splits.last.paceSecondsPerKm, isNotNull);
        final above = computeKilometerSplits(
          _restRun(
            7,
            parameters: PreprocessingParameters(
              parameterVersion: currentParameterVersion,
              standstillBelow: speed * 1.0001,
            ),
          ),
        );
        expect(above.splits.last.paceSecondsPerKm, isNull);
      },
    );

    test('Tempobasis wie die Pace: Lückenzeit zählt nicht mit', () {
      // Rest 200 m in 401 s, davon 351 s Lücke ohne Positionen: auf der ganzen
      // Zeit wären es 0,499 m/s (keine Pace), ohne die Lücke 4 m/s.
      final pre = RunPreprocessor(
        start: _start,
        parameters: const PreprocessingParameters.v4(),
      );
      for (var i = 0; i <= 300; i++) {
        pre.addPosition(
          RawPosition(
            time: _start.add(Duration(seconds: i)),
            source: 'gps',
            latitude: 10 + i * 4.0 / _mPerDeg,
            longitude: 20,
            accuracyMeters: 5,
          ),
        );
      }
      final run = pre.result(at: _start.add(const Duration(seconds: 651)));
      final s = computeKilometerSplits(run);
      final rest = s.splits.last;
      expect(rest.isPartial, isTrue);
      expect(rest.time, const Duration(seconds: 401));
      expect(rest.positionGapTime, const Duration(seconds: 351));
      expect(rest.paceSecondsPerKm, closeTo(250, 0.01));
      expect(_sum(s), run.movement.movingTime);
    });
  });
}
