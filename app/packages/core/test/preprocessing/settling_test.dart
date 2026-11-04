import 'package:core/core.dart';
import 'package:test/test.dart';

import 'hr_support.dart';
import 'motion_support.dart';
import 'settling_flank_test.dart' as flank;
import 'support.dart';

List<(DateTime, DateTime)> spans(RunPreprocessing r) => [
  for (final i in r.settling.intervals) (i.start, i.end),
];

DateTime min(num m) => at(m * 60);

void main() {
  group('PAR-011 Einschwingzeit', () {
    test('3 min nach Start, sonst nichts bei gleichmäßigem Lauf', () {
      final r = feed(track([(600, 3)])).result(at: at(600));
      expect(spans(r), [(t0, min(3))]);
      expect(r.settling.method, 'settling');
      expect(r.settling.parameterVersion, 2);
    });

    test('nach manueller Pause 3 min ab Fortsetzen', () {
      final run = RunPreprocessor(start: t0);
      track([(300, 3)]).forEach(run.addPosition);
      run.pause(at(300));
      run.resume(at(400));
      track([(300, 3)], from: 400, north: 900).forEach(run.addPosition);
      expect(spans(run.result(at: at(700))), [
        (t0, min(3)),
        (at(400), at(400 + 180)),
      ]);
    });

    test('ein Fortsetzen genau zum Abfragezeitpunkt zählt schon', () {
      final run = RunPreprocessor(start: t0);
      track([(300, 3)]).forEach(run.addPosition);
      run.pause(at(300));
      run.resume(at(400));
      expect(spans(run.result(at: at(400))).last, (at(400), at(580)));
    });

    test('nach erkannter Pause 3 min ab dem Wiederbeginn der Bewegung', () {
      // Tempowechsel ausgeschaltet, damit nur das Pausenende wirkt.
      const p = PreprocessingParameters(
        parameterVersion: 2,
        settlingPaceChange: 100,
      );
      final run = feed(track([(300, 3), (60, 0), (300, 3)]), p: p);
      final r = run.result(at: at(660));
      expect(r.movement.resumedAt, hasLength(1));
      final resume = r.movement.resumedAt.single;
      expect(resume.isAfter(at(360)), isTrue);
      expect(spans(r), [
        (t0, min(3)),
        (resume, resume.add(const Duration(minutes: 3))),
      ]);
    });

    // 600 s mit 3 m/s, danach [speed] m/s. Beide 2-min-Fenster sind erst bei
    // 720 s verschieden voll.
    List<(DateTime, DateTime)> change(double speed) =>
        spans(feed(track([(600, 3), (200, speed)])).result(at: at(800)));

    test('Tempowechsel 0,251 löst aus, 0,249 nicht (Haversine-Rundung)', () {
      expect(change(3.251), [(t0, min(3)), (at(720), at(900))]);
      expect(change(3.249), [(t0, min(3))]);
    });

    // Segmente mit exakt darstellbaren Metern: die Grenze 0,25 selbst.
    List<(DateTime, DateTime)> exact(double second) {
      final p = SettlingProcessor(
        const PreprocessingParameters.v2(),
        start: t0,
      );
      for (var s = 1; s <= 800; s++) {
        p.add(
          MotionSegment(
            start: at(s - 1),
            end: at(s),
            meters: s <= 600 ? 3.0 : second,
            isGap: false,
          ),
        );
      }
      return [
        for (final i in p.result(restarts: []).intervals) (i.start, i.end),
      ];
    }

    test('Tempowechsel genau 0,25 löst aus, knapp darunter nicht', () {
      expect(exact(3.25), [(t0, min(3)), (at(720), at(900))]);
      expect(exact(3.2499), [(t0, min(3))]);
    });

    test('Tempowechsel nach unten zählt ebenso', () {
      expect(change(2.749), [(t0, min(3)), (at(720), at(900))]);
      expect(change(2.751), [(t0, min(3))]);
    });

    test('nur mit zwei vollständigen Fenstern: erst ab 4 min', () {
      // Sprung nach 100 s. Früher wäre das frühere Fenster noch unvollständig.
      final r = feed(track([(100, 2), (200, 4)])).result(at: at(300));
      // Einmaliges Auslösen bei 240 s (erste Auswertung, vorher darunter):
      // recent 4, before (2*100+4*20)/120 = 2,67. Die Abweichung bleibt
      // darüber, die Flanke löst nicht erneut aus: [240, 420].
      expect(spans(r), [(t0, min(3)), (min(4), at(240 + 180))]);
    });

    test('stetig steigendes Tempo löst nur an der Flanke aus', () {
      // 600 s mit 3, danach je 60 s mit 3,5 / 4 / 4,5 / 5 m/s. Mittel
      // (t-2min,t] = 3 + 0,5 x/120 mit x s nach 600; Abweichung >= 0,25 erst
      // bei x = 60 (t=660). Danach wächst sie weiter, bleibt darüber: ein
      // Auslösen, [660, 840].
      // Exakte 1-s-Segmente: die Grenze 0,25 hängt nicht an der Rundung.
      final p = flank.exactRun([
        (600, 3),
        (60, 3.5),
        (60, 4),
        (60, 4.5),
        (60, 5),
      ]);
      expect(flank.spans(p), [(t0, min(3)), (at(660), at(840))]);
    });

    test('Pulswerte werden nicht verschoben', () {
      final values = beat(0, 200, 120);
      final run = RunPreprocessor(start: t0);
      track([(200, 3)]).forEach(run.addPosition);
      values.forEach(run.addHeartRate);
      final r = run.result(at: at(200));
      expect(
        r.heartRate.acceptedValues.map((v) => v.time),
        values.map((v) => v.time),
      );
      expect(r.heartRate.acceptedValues.first.time, t0);
    });

    test('Live = Gesamt je Präfix, Eingabe unverändert', () {
      final pts = track([(300, 3), (60, 0), (200, 3.5)]);
      final copy = [...pts];
      final live = RunPreprocessor(start: t0);
      for (var i = 0; i < pts.length; i += 7) {
        pts.sublist(i, (i + 7).clamp(0, pts.length)).forEach(live.addPosition);
        final upto = (i + 7).clamp(0, pts.length);
        final whole = feed(pts.take(upto).toList());
        final now = pts[upto - 1].time;
        expect(
          spans(live.result(at: now)),
          spans(whole.result(at: now)),
          reason: 'Präfix $upto',
        );
      }
      expect(pts, orderedEquals(copy));
    });
  });
}
