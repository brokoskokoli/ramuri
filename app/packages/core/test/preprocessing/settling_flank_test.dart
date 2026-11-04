import 'package:core/core.dart';
import 'package:test/test.dart';

import 'motion_support.dart';
import 'support.dart';

List<(DateTime, DateTime)> spans(SettlingProcessor p) => [
  for (final i in p.result(restarts: const []).intervals) (i.start, i.end),
];

/// Je (Dauer s, Tempo m/s) 1-s-Segmente ab Sekunde 0; Meter exakt darstellbar.
SettlingProcessor exactRun(List<(int, double)> legs) {
  final p = SettlingProcessor(const PreprocessingParameters.v2(), start: t0);
  var s = 0;
  for (final (duration, speed) in legs) {
    for (var i = 0; i < duration; i++) {
      p.add(
        MotionSegment(
          start: at(s),
          end: at(s + 1),
          meters: speed,
          isGap: false,
        ),
      );
      s++;
    }
  }
  return p;
}

void main() {
  group('PAR-011 Flanke', () {
    test('echter Tempowechsel löst genau einmal aus', () {
      // 600 s mit 3, danach 3,5 bis 1200. Mittel (t-2min,t]: 3 + 0,5 x/120
      // mit x s nach 600; genau 0,25 bei x = 60 (390/120 = 3,25 exakt).
      // Die Abweichung bleibt bis x = 180 darüber (0,25 bei x=180, danach
      // darunter), ohne neues Auslösen: [660, 840].
      expect(spans(exactRun([(600, 3), (600, 3.5)])), [
        (t0, at(180)),
        (at(660), at(840)),
      ]);
    });

    test('zwei Wechsel lösen zweimal aus', () {
      // Wie oben, die Abweichung fällt ab 781 unter 0,25 und ist ab 840 null.
      // Zurück auf 3 ab 1000: Abweichung 0,25 erstmals bei t = 1060
      // ((3,5*60 + 3*60)/120 = 3,25 gegen 3,5). Ende 1060 + 180 = 1240.
      expect(spans(exactRun([(600, 3), (400, 3.5), (500, 3)])), [
        (t0, at(180)),
        (at(660), at(840)),
        (at(1060), at(1240)),
      ]);
    });

    test('Schwelle 0,25 knapp innen und außen bleibt', () {
      // 3 -> 3,25: Abweichung genau 0,25 bei t = 720 (390/120 = 3,25).
      expect(spans(exactRun([(600, 3), (200, 3.25)])), [
        (t0, at(180)),
        (at(720), at(900)),
      ]);
      expect(spans(exactRun([(600, 3), (200, 3.2499)])), [(t0, at(180))]);
    });

    test('Standzeit zählt nicht ins Mittel: 0,5 m/s zählt, 0,499 nicht', () {
      // 3 -> 0,5: recent = 3 - 2,5 x/120, Abweichung 0,25 bei x = 12
      // (330/120 = 2,75): Auslösen bei 612. Bei 0,499 (< 0,5) gehen die
      // Segmente nicht ein, das Mittel bleibt 3.
      expect(spans(exactRun([(600, 3), (200, 0.5)])), [
        (t0, at(180)),
        (at(612), at(792)),
      ]);
      expect(spans(exactRun([(600, 3), (200, 0.499)])), [(t0, at(180))]);
    });

    test('15-s-Ampel bei 3 m/s: nur 3 min ab Pausenende, kein Echo', () {
      // Stillstand 600..615, Pause erkannt bei 610, Wiederbeginn: Kandidat
      // ab 615, 3 s gehalten, Ende 618. Die 15 Stillstandssegmente gehen
      // nicht ins Mittel, beide Fenster bleiben 3 m/s: Abweichung 0. Auch
      // bei 2 min (738) und 4 min (858) nach dem Stopp kein Echo.
      final r = feed(track([(600, 3), (15, 0), (600, 3)]));
      final res = r.result(at: at(1215));
      expect(res.movement.resumedAt, [at(618)]);
      expect(spans2(res), [(t0, at(180)), (at(618), at(798))]);
    });

    test('erkannte und manuelle Pause wirken gleich', () {
      final auto = feed(track([(600, 3), (60, 0), (600, 3)]));
      final autoRes = auto.result(at: at(1260));
      // Wiederbeginn bei 660 + 3 s = 663.
      expect(autoRes.movement.resumedAt, [at(663)]);
      expect(spans2(autoRes), [(t0, at(180)), (at(663), at(843))]);

      final manual = RunPreprocessor(start: t0);
      track([(600, 3)]).forEach(manual.addPosition);
      manual.pause(at(600));
      manual.resume(at(660));
      track([(600, 3)], from: 660, north: 3000).forEach(manual.addPosition);
      expect(spans2(manual.result(at: at(1260))), [
        (t0, at(180)),
        (at(660), at(840)),
      ]);
    });

    test('Lücke 235 s, danach 3,3 m/s: Vergleich gegen kurzes Fenster', () {
      // Segmente bis 300 mit 3, Lücke 300..535, dann 3,3. Bei 536: recent
      // 1 Segment 3,3, before (296,416] enthält 4 s mit 3: Abweichung 0,3,
      // Auslösen. Bis 539 bleibt das frühere Fenster gefüllt, danach leer
      // (nicht auswertbar); ab 656 ist es 3,3: Abweichung 0. Ein Auslösen.
      final p = SettlingProcessor(
        const PreprocessingParameters.v2(),
        start: t0,
      );
      for (var s = 1; s <= 300; s++) {
        p.add(
          MotionSegment(start: at(s - 1), end: at(s), meters: 3, isGap: false),
        );
      }
      p.add(
        MotionSegment(start: at(300), end: at(535), meters: 0, isGap: true),
      );
      for (var s = 536; s <= 800; s++) {
        p.add(
          MotionSegment(
            start: at(s - 1),
            end: at(s),
            meters: 3.3,
            isGap: false,
          ),
        );
      }
      expect(spans(p), [(t0, at(180)), (at(536), at(716))]);
    });
  });
}

List<(DateTime, DateTime)> spans2(RunPreprocessing r) => [
  for (final i in r.settling.intervals) (i.start, i.end),
];
