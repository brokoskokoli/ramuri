// WP13 D: Route eines Laufs für die Miniatur, lazy, mit Pausen und Lücken unterbrochen (FR-0056).
import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

void main() {
  final start = DateTime.utc(2030, 1, 10, 8);

  test('Lauf ohne Pause: eine Linie, auf die Höchstzahl ausgedünnt', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(start, minutes: 20);
    final route = await loadRunRoute(w.session, id, maxPoints: 50);
    expect(route.length, 1);
    expect(route.single.length, lessThanOrEqualTo(60));
    expect(route.single.length, greaterThan(2));
  });

  test('manuelle Pause: zwei Linien, nie über die Pause verbunden', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(start, minutes: 20);
    final gap = await w.session.markers.openGap(
      id,
      RunGapKind.manualPause,
      start.add(const Duration(minutes: 8)),
    );
    await w.session.markers.closeGap(
      gap,
      start.add(const Duration(minutes: 12)),
    );
    final route = await loadRunRoute(w.session, id);
    expect(route.length, 2);
    // Zwischen den Teilen liegen 4 Minuten Weg (3 m/s): die Teile berühren sich nicht.
    final a = route[0].last;
    final b = route[1].first;
    expect((b.latitude - a.latitude).abs(), greaterThan(0.005));
  });

  // Ausfall nach Absturz (FR-0193) wie eine Pause (FR-0042): die Linie ist unterbrochen (FR-0204). Die Positionen
  // laufen durch, die Vorverarbeitung sieht also keine GPS-Lücke; ohne die Lücke als Pause wäre die Linie verbunden.
  Future<(RecalcWorld, int)> runWithGap(
    RunGapKind kind, {
    bool close = true,
  }) async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(start, minutes: 20);
    final gap = await w.session.markers.openGap(
      id,
      kind,
      start.add(const Duration(minutes: 8)),
    );
    if (close) {
      await w.session.markers.closeGap(
        gap,
        start.add(const Duration(minutes: 12)),
      );
    }
    return (w, id);
  }

  test(
    'Ausfall nach Absturz: zwei Linien, nie über den Ausfall verbunden',
    () async {
      final (w, id) = await runWithGap(RunGapKind.interruption);
      final route = await loadRunRoute(w.session, id);
      expect(route.length, 2);
      final a = route[0].last;
      final b = route[1].first;
      expect((b.latitude - a.latitude).abs(), greaterThan(0.005));
    },
  );

  test('offener Ausfall bis Laufende: die Linie endet am Ausfall', () async {
    final (w, id) = await runWithGap(RunGapKind.interruption, close: false);
    final route = await loadRunRoute(w.session, id);
    // Die Linie endet bei Minute 8; zwischen Minute 8 und Laufende (Minute 20) liegt kein Punkt.
    const perMinute = 180 / (earthRadiusMeters * 3.141592653589793 / 180);
    final first = route.first.first.latitude;
    expect(route.first.last.latitude - first, closeTo(8 * perMinute, 1e-6));
    for (final part in route) {
      for (final p in part) {
        final minute = (p.latitude - first) / perMinute;
        expect(
          minute <= 8 + 1e-6 || minute >= 20 - 1e-6,
          isTrue,
          reason: 'Punkt bei Minute $minute liegt im Ausfall',
        );
      }
    }
  });

  test('Gegenprobe: Signalverlust gleicher Lage ist keine Pause', () async {
    final (w, id) = await runWithGap(RunGapKind.positionLoss);
    final route = await loadRunRoute(w.session, id);
    // Positionen ohne Lücke: eine Linie, wie ohne markierte Lücke.
    expect(route.length, 1);
    final (w2, id2) = await runWithGap(RunGapKind.positionLoss, close: false);
    expect(await loadRunRoute(w2.session, id2), hasLength(1));
  });

  test(
    'Lauf ohne Positionen (Laufband): leer, unbekannter Lauf: leer',
    () async {
      final w = await RecalcWorld.create();
      final run = await w.session.runs.create(startedAt: start);
      await w.session.rawData.append(
        run.id,
        RawBatch(
          heartRates: [
            for (var i = 0; i < 60; i++)
              RawHeartRate(
                time: start.add(Duration(seconds: i)),
                source: 'strap',
                bpm: 140,
                contact: SensorContact.good,
              ),
          ],
        ),
      );
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(minutes: 1)),
      );
      expect(await loadRunRoute(w.session, run.id), isEmpty);
      expect(await loadRunRoute(w.session, 999), isEmpty);
    },
  );
}
