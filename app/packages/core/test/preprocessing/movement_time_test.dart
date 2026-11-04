import 'package:core/core.dart';
import 'package:test/test.dart';

import 'motion_support.dart';
import 'support.dart';

/// Punkte an festen Sekunden auf gleicher Höhe (Stillstand).
List<RawPosition> still(num north, List<num> secs) => [
  for (final s in secs) pos(s, north),
];

MovementResult mv(RunPreprocessor r, num sec) => r.result(at: at(sec)).movement;

void main() {
  group('Pause nach Stillstand (PAR-015: 10 s)', () {
    // 10 s Gehen mit 3 m/s, ab Sekunde 10 steht der Läufer bei 30 m.
    final walk = track([(10, 3)]);

    test('9,9 s Stillstand: keine Pause', () {
      final r = feed([
        ...walk,
        ...still(30, [12, 15, 19.9]),
      ]);
      expect(mv(r, 19.9).autoPauseState, AutoPauseState.moving);
      expect(mv(r, 19.9).movingTime, const Duration(milliseconds: 19900));
    });

    test('genau 10 s Stillstand: Pause ab diesem Zeitpunkt', () {
      final r = feed([
        ...walk,
        ...still(30, [12, 15, 20]),
      ]);
      final m = mv(r, 20);
      expect(m.autoPauseState, AutoPauseState.standstillPause);
      // Die ersten 10 s Stillstand bleiben Bewegungszeit.
      expect(m.movingTime, const Duration(seconds: 20));
      expect(mv(r, 30).movingTime, const Duration(seconds: 20));
      expect(mv(r, 30).totalTime, const Duration(seconds: 30));
    });
  });

  group('Fortsetzen (PAR-015: 3 s)', () {
    // Gehen bis 10 s, Stillstand bis 30 s (Pause ab 20 s), dann 3 m/s.
    List<RawPosition> walkStopMove(List<num> moveSecs) => [
      ...track([(10, 3)]),
      ...still(30, [15, 20, 30]),
      for (final s in moveSecs) pos(s, 30 + 3 * (s - 30)),
    ];

    test('2,9 s über der oberen Schwelle: kein Fortsetzen', () {
      final r = feed(walkStopMove([31, 32, 32.9]));
      expect(mv(r, 32.9).autoPauseState, AutoPauseState.standstillPause);
      expect(mv(r, 32.9).movingTime, const Duration(seconds: 20));
    });

    test(
      'genau 3 s: Fortsetzen ab diesem Zeitpunkt, die 3 s bleiben Pause',
      () {
        final r = feed(walkStopMove([31, 32, 33]));
        expect(mv(r, 33).autoPauseState, AutoPauseState.moving);
        expect(mv(r, 33).movingTime, const Duration(seconds: 20));
        expect(mv(r, 35).movingTime, const Duration(seconds: 22));
      },
    );
  });

  group('Hysterese (PAR-014)', () {
    /// Gehen, dann [secs] mit Tempo [v]; true, wenn eine Pause entsteht.
    bool pausesAt(double v) {
      final r = feed(track([(10, 3), (12, v)]));
      return mv(r, 22).autoPauseState == AutoPauseState.standstillPause;
    }

    /// Pause (Stillstand ab 10 s), dann [v] für 5 s; true, wenn fortgesetzt.
    bool resumesAt(double v) {
      final pts = [
        ...track([(10, 3)]),
        ...still(30, [15, 20, 30]),
        ...track([(5, v)], from: 30, north: 30, first: false),
      ];
      return mv(feed(pts), 35).autoPauseState == AutoPauseState.moving;
    }

    test(
      'untere Schwelle 0,5 m/s: knapp darunter Pause, knapp darüber nicht',
      () {
        expect(pausesAt(0.499), isTrue);
        expect(pausesAt(0.501), isFalse);
      },
    );

    test('obere Schwelle 0,8 m/s: knapp darunter kein Fortsetzen', () {
      expect(resumesAt(0.801), isTrue);
      expect(resumesAt(0.799), isFalse);
    });

    test(
      'das Band dazwischen (0,6 m/s) löst weder Pause noch Fortsetzen aus',
      () {
        expect(pausesAt(0.6), isFalse);
        expect(resumesAt(0.6), isFalse);
      },
    );

    test(
      'ein Wert im Band unterbricht einen laufenden Stillstandskandidaten',
      () {
        // 6 s Stillstand, 1 s Band, 6 s Stillstand: nie 10 s am Stück.
        final r = feed(track([(10, 3), (6, 0), (1, 0.6), (6, 0)]));
        expect(mv(r, 23).autoPauseState, AutoPauseState.moving);
      },
    );

    test(
      'ein Wert im Band unterbricht einen laufenden Bewegungskandidaten',
      () {
        final pts = [
          ...track([(10, 3)]),
          ...still(30, [15, 20, 30]),
          ...track(
            [(2, 3), (1, 0.6), (2, 3)],
            from: 30,
            north: 30,
            first: false,
          ),
        ];
        expect(
          mv(feed(pts), 35).autoPauseState,
          AutoPauseState.standstillPause,
        );
      },
    );
  });

  group('Bewegungszeit und Gesamtzeit (FR-0052)', () {
    test('Lauf mit Stopp: Bewegungszeit 127 s von 150 s', () {
      // 0-60 s Gehen, 60-90 s Stillstand (Pause ab 70 s), 90-150 s Gehen
      // (Fortsetzen ab 93 s).
      final pts = [
        ...track([(60, 3)]),
        ...still(180, [for (var s = 61; s <= 90; s++) s]),
        ...track([(60, 3)], from: 90, north: 180, first: false),
      ];
      final m = mv(feed(pts), 150);
      expect(m.totalTime, const Duration(seconds: 150));
      expect(m.movingTime, const Duration(seconds: 127));
      expect(m.movingTime, lessThan(m.totalTime));
      expect(m.movingIntervals.map((i) => (i.start, i.end)).toList(), [
        (at(0), at(70)),
        (at(93), at(150)),
      ]);
      expect(
        () => m.movingIntervals.add(m.movingIntervals.first),
        throwsUnsupportedError,
      );
    });

    test(
      'manuelle Pause zählt nie zur Bewegungszeit, immer zur Gesamtzeit',
      () {
        final r = RunPreprocessor(start: t0);
        track([(30, 3)]).forEach(r.addPosition);
        r.pause(at(30));
        expect(mv(r, 45).movingTime, const Duration(seconds: 30));
        expect(mv(r, 45).manuallyPaused, isTrue);
        r.resume(at(50));
        track(
          [(20, 3)],
          from: 51,
          north: 90,
          first: false,
        ).forEach(r.addPosition);
        final m = mv(r, 70);
        expect(m.totalTime, const Duration(seconds: 70));
        expect(m.movingTime, const Duration(seconds: 50)); // 30 + 20
        expect(m.manuallyPaused, isFalse);
        expect(m.autoPauseState, AutoPauseState.moving);
      },
    );

    test('vor dem ersten Punkt zählt die Zeit als Bewegung', () {
      final m = mv(RunPreprocessor(start: t0), 5);
      expect(m.movingTime, const Duration(seconds: 5));
      expect(m.totalTime, const Duration(seconds: 5));
      expect(m.autoPauseState, AutoPauseState.moving);
    });
  });

  group('PAR-004-Lücke löst keine Pause aus', () {
    test(
      'Lücke im Zustand moving zählt zur Bewegungszeit, Kandidat bricht ab',
      () {
        // 5 s Stillstand (10-15 s), 15 s Lücke ohne Punkte, wieder 6 s Stillstand.
        // Liefe der Kandidat über die Lücke, begänne die Pause bei 20 s.
        final pts = [
          ...track([(10, 3)]),
          ...still(30, [11, 12, 13, 14, 15]),
          ...still(30, [30, 31, 32, 33, 34, 36]),
        ];
        final r = feed(pts);
        expect(r.result(at: at(36)).position.gaps, hasLength(1));
        final m = mv(r, 36);
        expect(m.autoPauseState, AutoPauseState.moving);
        expect(m.movingTime, const Duration(seconds: 36));
        // Ab 30 s läuft ein neuer Kandidat: Pause bei 40 s.
        final r2 = feed([
          ...pts,
          ...still(30, [38, 40]),
        ]);
        expect(mv(r2, 40).autoPauseState, AutoPauseState.standstillPause);
        expect(mv(r2, 45).movingTime, const Duration(seconds: 40));
      },
    );

    test('Lücke im Zustand Pause bleibt Pause', () {
      final pts = [
        ...track([(10, 3)]),
        ...still(30, [15, 20, 25]),
        ...still(30, [50]),
      ];
      final m = mv(feed(pts), 50);
      expect(m.autoPauseState, AutoPauseState.standstillPause);
      expect(m.movingTime, const Duration(seconds: 20));
    });
  });
}
