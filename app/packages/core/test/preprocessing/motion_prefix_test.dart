import 'package:core/core.dart';
import 'package:test/test.dart';

import 'motion_support.dart';
import 'support.dart';

/// Ereignis eines Laufs: Punkt, manuelle Pause oder Fortsetzen.
typedef Ev = ({RawPosition? point, bool? pause, DateTime time});

Ev pt(RawPosition x) => (point: x, pause: null, time: x.time);
Ev pa(num s) => (point: null, pause: true, time: at(s));
Ev re(num s) => (point: null, pause: false, time: at(s));

void applyTo(RunPreprocessor r, Ev e) {
  if (e.point != null) {
    r.addPosition(e.point!);
  } else if (e.pause!) {
    r.pause(e.time);
  } else {
    r.resume(e.time);
  }
}

void main() {
  // Gehen, Stillstand mit Pause, Ausreißer, verworfener Punkt, manuelle
  // Pause, Band, Lücke: berührt alle Zustände der neuen Werte.
  final events = <Ev>[
    ...track([(20, 3), (14, 0), (6, 3), (1, 9), (5, 3)], acc: 10).map(pt),
    pt(pos(47, 200, acc: 90)),
    pa(48),
    re(55),
    ...track([(4, 0.6), (8, 3)], from: 56, north: 150, first: false).map(pt),
    ...track([(3, 3)], from: 80, north: 201, first: false).map(pt),
  ];

  test('Live und Gesamt sind nach jedem Präfix gleich', () {
    final live = RunPreprocessor(start: t0);
    for (var i = 0; i < events.length; i++) {
      applyTo(live, events[i]);
      final t = events[i].time;
      // Zwischenabfragen (auch später) ändern nichts.
      live.result(at: t.add(const Duration(seconds: 7)));
      final full = RunPreprocessor(start: t0);
      events.take(i + 1).forEach((e) => applyTo(full, e));
      expect(
        motionFingerprint(live.result(at: t)),
        motionFingerprint(full.result(at: t)),
        reason: 'Präfix ${i + 1}',
      );
    }
  });

  test('der Lauf berührt Pause, Fortsetzen, Lücke und Median', () {
    final r = RunPreprocessor(start: t0);
    events.forEach((e) => applyTo(r, e));
    final m = r.result(at: at(83)).movement;
    expect(m.movingIntervals.length, greaterThanOrEqualTo(3));
    expect(m.movingTime, lessThan(m.totalTime));
    expect(r.result(at: at(83)).position.gaps, isNotEmpty);
    expect(r.result(at: at(83)).pace.medianSeries, isNotEmpty);
  });

  test('Eingaben bleiben unverändert, Ergebnislisten sind unveränderlich', () {
    String dump() => events
        .map(
          (e) =>
              '${e.time}/${e.point?.latitude}/${e.point?.accuracyMeters}/${e.pause}',
        )
        .join(',');
    final before = dump();
    final r = RunPreprocessor(start: t0);
    events.forEach((e) => applyTo(r, e));
    final res = r.result(at: at(83));
    expect(dump(), before);
    expect(() => res.pace.medianSeries.clear(), throwsUnsupportedError);
    expect(() => res.movement.movingIntervals.clear(), throwsUnsupportedError);
    expect(
      motionFingerprint(r.result(at: at(83))),
      motionFingerprint(res),
      reason: 'wiederholte Abfrage ändert nichts',
    );
  });

  test(
    'bekannte Grenze, siehe OQ-0020: Rauschen im Stand gilt als Bewegung',
    () {
      // Läufer steht. Gemeldet wird alle Sekunde abwechselnd +3 m und -3 m um
      // den wahren Ort (acc 5 m): jeder Schritt 6 m in 1 s, unter PAR-003.
      final pts = [for (var s = 0; s <= 60; s++) pos(s, s.isEven ? 3 : -3)];
      final r = feed(pts).result(at: at(60));
      // Festgehalten: das Spec-Verhalten, keine Wunschvorstellung.
      expect(r.position.distanceMeters, closeTo(60 * 6, 0.01));
      expect(r.movement.autoPauseState, AutoPauseState.moving);
      expect(r.movement.movingTime, r.movement.totalTime);
      expect(r.pace.liveSpeed, closeTo(6, 1e-6));
      expect(
        (r.pace.livePace as PaceValue).secondsPerKm,
        closeTo(1000 / 6, 1e-6),
      );
    },
  );
}
