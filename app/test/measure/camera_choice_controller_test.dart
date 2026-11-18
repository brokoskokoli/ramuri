import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_measure_controller.dart';
import 'package:running_app/features/measure/resting_measure_controller.dart';

import 'measure_support.dart';

// Kamerawahl der Kamera-Messung (FR-0220): Ruhepuls und Morgenmessung starten die
// Kamera aus resolvePpgCamera. Alle Kameras und Werte erfunden.

const _std = PpgCameraRef('0');
const _second = PpgCameraRef('0', '2');
const _noFlash = PpgCameraRef('1');

const _cameras = [
  PpgCameraInfo(ref: _std, focalLengthMm: 5.4, isDefault: true),
  PpgCameraInfo(ref: _second, focalLengthMm: 2.2),
  PpgCameraInfo(ref: _noFlash, unusable: PpgCameraUnusable.noFlash),
];

class _Setup {
  _Setup(this.session, this.clock, this.cam);

  final StorageSession session;
  final FakeClock clock;
  final FakePpgCamera cam;

  SettingsDeveloperModeStore get dev =>
      SettingsDeveloperModeStore(session.settings, clock);
  SettingsPpgCameraChoiceStore get choice =>
      SettingsPpgCameraChoiceStore(session.settings, clock);

  /// Wie die Launcher: dieselbe Regel für beide Messungen.
  Future<PpgCameraRef?> Function() get chooser =>
      () =>
          choosePpgCamera(camera: cam, developerMode: dev.read, choice: choice);

  static Future<_Setup> make() async => _Setup(
    await FakeStorage().open(testKey),
    FakeClock(DateTime.utc(2026, 11, 18, 5, 30)),
    FakePpgCamera()..cameraList = _cameras,
  );

  RestingMeasureController resting() => RestingMeasureController(
    camera: cam,
    clock: clock,
    evaluate: evalFinalOnly,
    autoTick: false,
    cameraChoice: chooser,
  );

  MorningMeasureController morning() => MorningMeasureController(
    camera: cam,
    store: (session as MorningStorage).morning,
    windowStore: SettingsMorningWindowStore(session.settings, clock),
    clock: clock,
    device: () async => (manufacturer: 'Testhersteller', model: 'Modell 1'),
    autoTick: false,
    cameraChoice: chooser,
  );
}

void main() {
  for (final kind in ['Ruhepuls', 'Morgenmessung']) {
    group(kind, () {
      Future<RestingMeasureController> start(_Setup s) async {
        final RestingMeasureController engine;
        if (kind == 'Ruhepuls') {
          engine = s.resting();
        } else {
          engine = s.morning().engine;
        }
        await engine.startNow();
        await pump();
        return engine;
      }

      test('gewählte zweite Kamera wird gestartet', () async {
        final s = await _Setup.make();
        await s.dev.set(true);
        await s.choice.setManual(_second);
        final c = await start(s);
        expect(s.cam.startedWith, [_second]);
        expect(c.startedCamera, _second);
        expect(c.phase, RestingMeasurePhase.measuring);
        await c.cancel();
      });

      test(
        'nach Ausschalten des Entwicklermodus wieder die Standardkamera',
        () async {
          final s = await _Setup.make();
          await s.dev.set(true);
          await s.choice.setManual(_second);
          await (await start(s)).cancel();
          await s.dev.set(false);
          final c = await start(s);
          expect(s.cam.startedWith, [_second, null]);
          expect(c.startedCamera, _std);
          // Die Wahl bleibt gespeichert.
          expect(await s.choice.readManual(), _second);
          await c.cancel();
        },
      );

      test('Ergebnis der Kamerasuche gilt auch ohne Entwicklermodus', () async {
        final s = await _Setup.make();
        await s.choice.setAuto(_second);
        final c = await start(s);
        expect(s.cam.startedWith, [_second]);
        await c.cancel();
      });

      test(
        'nichts gespeichert: Standardkamera ohne Angabe, Liste nicht gelesen',
        () async {
          final s = await _Setup.make();
          await s.dev.set(true);
          final c = await start(s);
          expect(s.cam.startedWith, [null]);
          expect(s.cam.camerasCount, 0);
          expect(c.startedCamera, _std);
          await c.cancel();
        },
      );

      test('nicht nutzbare Wahl von Hand: Standardkamera', () async {
        final s = await _Setup.make();
        await s.dev.set(true);
        await s.choice.setManual(_noFlash);
        final c = await start(s);
        expect(s.cam.startedWith, [null]);
        await c.cancel();
      });
    });
  }

  test('Kamera verschwindet zwischen Liste und Start: Ende mit Grund, keine andere', () async {
    final s = await _Setup.make();
    await s.dev.set(true);
    await s.choice.setManual(_second);
    // Die Liste nennt sie noch, beim Öffnen ist sie weg (Fake prüft beim Abonnieren).
    final c = RestingMeasureController(
      camera: s.cam,
      clock: s.clock,
      evaluate: evalFinalOnly,
      autoTick: false,
      cameraChoice: () async {
        final r = await s.chooser();
        s.cam.cameraList = const [PpgCameraInfo(ref: _std, isDefault: true)];
        return r;
      },
    );
    await c.startNow();
    await pump();
    expect(s.cam.startedWith, [_second]);
    expect(s.cam.startCount, 1);
    expect(c.phase, RestingMeasurePhase.stopped);
    expect(c.stopCause, RestingStopCause.noCamera);
    expect(s.cam.torchOn, isFalse);
  });

  test('Fehler beim Lesen der Wahl: Standardkamera, keine Ausnahme', () async {
    final s = await _Setup.make();
    final c = RestingMeasureController(
      camera: s.cam,
      clock: s.clock,
      evaluate: evalFinalOnly,
      autoTick: false,
      cameraChoice: () async => throw StateError('nicht lesbar'),
    );
    await c.startNow();
    await pump();
    expect(s.cam.startedWith, [null]);
    expect(c.phase, RestingMeasurePhase.measuring);
    await c.cancel();
  });

  test('Hintergrund während der Kamerawahl: kein Start', () async {
    final s = await _Setup.make();
    final gate = Completer<PpgCameraRef?>();
    final c = RestingMeasureController(
      camera: s.cam,
      clock: s.clock,
      evaluate: evalFinalOnly,
      autoTick: false,
      cameraChoice: () => gate.future,
    );
    final f = c.startNow();
    await pump();
    await c.onBackground();
    gate.complete(_second);
    await f;
    expect(s.cam.startCount, 0);
    expect(c.stopCause, RestingStopCause.background);
  });
}
