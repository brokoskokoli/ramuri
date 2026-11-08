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
