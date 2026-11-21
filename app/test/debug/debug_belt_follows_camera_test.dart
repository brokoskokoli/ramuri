import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'belt_camera_support.dart';

void main() {
  // FR-0217: Bilder der Fake-Kamera laufen durch die Fenstersuche aus `core`
  // (wie die Morgenmessung der App); deren Kamera-Abstände und die Gurt-Pakete
  // gehen in denselben Vergleich wie die Entwicklereinstellungen.
  testWidgets(
    'Gurt passend zur Fake-Kamera: Vergleich findet eine Zuordnung, die alte Art nicht',
    (tester) async {
      final mit = await runCameraWithBelt(tester, follow: true);
      final w = evaluatePpgBestWindow(mit.frames);
      expect(w.measurement.quality, isNot(PpgQuality.unusable));
      final cam = w.measurement.intervalsMs;
      expect(cam.where((v) => v.isFinite).length, greaterThan(20));
      final r = compareMorningWithBelt(cam, rrPackets(mit.readings));
      expect(
        r,
        isA<MorningBeltComparison>(),
        reason: 'neue Art: Zuordnung, nicht $r',
      );
      final c = r as MorningBeltComparison;
      // Gurt und Kamera stammen aus demselben Schlagplan: wenige ms Fehler.
      expect(c.ibiErrorMs, lessThan(20));
      expect(
        c.cost,
        lessThan(morningBeltCompareAmbiguityRatio * c.secondCost!),
      );

      // Gegenprobe: dieselben Kamera-Abstände, Gurt in der alten Art.
      final alt = await runCameraWithBelt(tester, follow: false);
      final packets = rrPackets(alt.readings);
      expect(packets, isNotEmpty);
      expect(compareMorningWithBelt(cam, packets), isA<MorningBeltNoMatch>());
    },
  );
}
