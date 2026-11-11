import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/resting_measure_controller.dart';

import '../measure/measure_support.dart';

// WP27, Nachbesserung: Messungen mit der Fake-Kamera endeten bei hoher Last des
// Emulators als „unterbrochen“. Hier läuft der echte Controller mit seinem
// Wächter-Timer und der Fake-Kamera unter simulierter Last: Die Uhr des Controllers
// ist die Wanduhr (FakeClock, folgt der Testzeit), „Hänger“ der App sind Sprünge
// dieser Uhr ohne dass Timer laufen, „Rechenlast“ ist Zeit, die jedes verarbeitete
// Bild kostet. Alle Werte synthetisch.

class _Env {
  _Env(this.c, this.clock, this.cam, this.frameCost);
  final RestingMeasureController c;
  final FakeClock clock;
  final DebugTestPpgCamera cam;

  /// Dauer eines Aufbaus der Oberfläche (die App kommt in dieser Zeit nicht zum Zug).
  final Duration frameCost;
  bool dirty = false;
}

Future<_Env> _make(
  WidgetTester tester, {
  required double speed,
  Duration frameCost = Duration.zero,
}) async {
  final session = await FakeStorage().open(testKey);
  final clock = FakeClock(DateTime.utc(2026, 11, 11, 7, 0));
  final settings = session.settings;
  final cam = DebugTestPpgCamera(speed: speed, wallClock: clock.monotonic);
  final c = RestingMeasureController(
    camera: cam,
    profile: ProfileService(session.profile, clock, settings: settings),
    settings: settings,
    clock: clock,
    evaluate: evalFinalOnly,
  );
  final env = _Env(c, clock, cam, frameCost);
  // Oberfläche neu aufbauen: höchstens einmal je Takt der Ereignisschleife (ein
  // Aufbau fasst die Meldungen mehrerer Kamerabilder zusammen).
  c.addListener(() => env.dirty = true);
  addTearDown(c.dispose);
  return env;
}

/// Lässt [seconds] Wanduhrzeit vergehen (Testzeit und Uhr im Gleichschritt,
/// je [hang] ein Hänger von [hangFor] ohne laufende Timer).
Future<void> _run(
  WidgetTester tester,
  _Env e,
  double seconds, {
  double hangEvery = 0,
  Duration hangFor = Duration.zero,
  bool Function()? until,
}) async {
  const step = Duration(milliseconds: 5);
  var sinceHang = 0.0;
  for (var i = 0; i < seconds * 200; i++) {
    if (i % 200 == 0 || e.c.evaluating) {
      // Beenden (Kamera freigeben, Auswertung, Profil laden) läuft auf echten
      // Futures, nicht auf der Testzeit.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    if (until != null && until()) break;
    if (hangEvery > 0 && sinceHang >= hangEvery) {
      sinceHang = 0;
      e.clock.advance(hangFor);
    }
    e.clock.advance(step);
    await tester.pump(step);
    if (e.dirty) {
      e.dirty = false;
      e.clock.advance(e.frameCost);
    }
    sinceHang += step.inMicroseconds / 1e6;
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  // Die Schleife der Fake-Kamera läuft nach dem Abbestellen noch einen Takt.
  await tester.pump(const Duration(seconds: 1));
}

bool _ended(_Env e) =>
    e.c.phase == RestingMeasurePhase.result ||
    e.c.phase == RestingMeasurePhase.stopped;

void main() {
  group('Messung mit Fake-Kamera unter Last', () {
    testWidgets('ohne Last: Echtzeit und Zeitraffer enden mit Ergebnis', (
      tester,
    ) async {
      for (final speed in [1.0, 30.0]) {
        final e = await _make(tester, speed: speed);
        await e.c.startNow();
        await _run(tester, e, 100, until: () => _ended(e));
        expect(
          e.c.phase,
          RestingMeasurePhase.result,
          reason: 'x$speed: ${e.c.stopCause}',
        );
        e.c.discard();
      }
    });

    for (final hang in [0.9, 2.5, 4.0]) {
      testWidgets(
        'einzelne Hänger der App von $hang s: Messung gelingt (Wächter)',
        (tester) async {
          final e = await _make(tester, speed: 1);
          await e.c.startNow();
          await _run(
            tester,
            e,
            100,
            hangEvery: 7,
            hangFor: Duration(milliseconds: (hang * 1000).round()),
            until: () => _ended(e),
          );
          expect(
            e.c.phase,
            RestingMeasurePhase.result,
            reason: 'Ursache: ${e.c.stopCause}, nach ${e.clock.monotonic()}',
          );
        },
      );
    }

    testWidgets('Rechenlast, Fake hält die Echtzeit: Messung gelingt', (
      tester,
    ) async {
      // 25 ms Aufbau je Bild bei 33 ms Bildabstand: die App kommt kaum noch zum Zug.
      final e = await _make(
        tester,
        speed: 1,
        frameCost: const Duration(milliseconds: 25),
      );
      await e.c.startNow();
      await _run(tester, e, 120, until: () => _ended(e));
      expect(
        e.c.phase,
        RestingMeasurePhase.result,
        reason: 'Ursache: ${e.c.stopCause}, nach ${e.clock.monotonic()}',
      );
    });

    testWidgets(
      'Rechenlast im Zeitraffer (250 ms je Aufbau): Messung gelingt',
      (tester) async {
        final e = await _make(
          tester,
          speed: 30,
          frameCost: const Duration(milliseconds: 250),
        );
        await e.c.startNow();
        await _run(tester, e, 120, until: () => _ended(e));
        expect(
          e.c.phase,
          RestingMeasurePhase.result,
          reason: 'Ursache: ${e.c.stopCause}, nach ${e.clock.monotonic()}',
        );
      },
    );

    for (final hang in [0.9, 4.0, 10.0]) {
      testWidgets(
        'echtes Handy (Bilder mit Sensorzeit aus der Wanduhr), App hängt $hang s: '
        'Bilder kommen gebündelt nach, Messung gelingt',
        (tester) async {
          final session = await FakeStorage().open(testKey);
          final clock = FakeClock(DateTime.utc(2026, 11, 11, 7, 0));
          final cam = HoldingCamera();
          final c = RestingMeasureController(
            camera: cam,
            profile: ProfileService(
              session.profile,
              clock,
              settings: session.settings,
            ),
            settings: session.settings,
            clock: clock,
            evaluate: evalFinalOnly,
          );
          addTearDown(c.dispose);
          await c.startNow();
          await tester.pump();
          final src = FrameSource();
          var emitted = 0;
          var sinceHang = 0.0;
          for (var i = 0; i < 100 * 200; i++) {
            if (i % 200 == 0 || c.evaluating) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 5)),
              );
              await tester.pump();
            }
            if (c.phase == RestingMeasurePhase.result ||
                c.phase == RestingMeasurePhase.stopped) {
              break;
            }
            if (sinceHang >= 7) {
              sinceHang = 0;
              clock.advance(Duration(milliseconds: (hang * 1000).round()));
            }
            clock.advance(const Duration(milliseconds: 5));
            sinceHang += 0.005;
            await tester.pump(const Duration(milliseconds: 5));
            final wall = clock.monotonic().inMicroseconds / 1e6;
            while (emitted / 30 <= wall) {
              cam.emitFrame(src.next());
              emitted++;
            }
          }
          expect(
            c.phase,
            RestingMeasurePhase.result,
            reason: 'Ursache: ${c.stopCause}, nach ${clock.monotonic()}',
          );
        },
      );
    }
  });
}
