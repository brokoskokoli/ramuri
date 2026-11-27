import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/camera_finder_controller.dart';

// Kamerasuche (FR-0220, PAR-227, PAR-228): Controller mit der Fake-Kamera. Alle Kameras
// und Zahlen erfunden.

const _std = PpgCameraRef('0');
const _second = PpgCameraRef('0', '2');
const _noFlash = PpgCameraRef('1');

const _cameras = [
  PpgCameraInfo(ref: _std, isDefault: true, frameRate: 60),
  PpgCameraInfo(ref: _second, frameRate: 30),
  PpgCameraInfo(ref: _noFlash, unusable: PpgCameraUnusable.noFlash),
];

/// Zeichnet jeden Schreibzugriff auf; Lesen und Schreiben gehen an [inner].
class _SpyChoice implements PpgCameraChoiceStore {
  _SpyChoice(this.inner);
  final PpgCameraChoiceStore inner;
  final List<String> writes = [];
  bool fail = false;

  @override
  Future<PpgCameraRef?> readAuto() => inner.readAuto();
  @override
  Future<PpgCameraRef?> readManual() => inner.readManual();
  @override
  Future<void> setAuto(PpgCameraRef? camera) async {
    if (fail) throw const StorageException(StorageFailure.failed);
    writes.add('auto:${camera?.key}');
    await inner.setAuto(camera);
  }

  @override
  Future<void> setManual(PpgCameraRef? camera) async {
    if (fail) throw const StorageException(StorageFailure.failed);
    writes.add('manual:${camera?.key}');
    await inner.setManual(camera);
  }
}

/// Zählt die Abfragen von Recht und Verfügbarkeit; wirft auf Wunsch beim Lesen der Liste.
class _CountingCamera extends FakePpgCamera {
  int availabilityCalls = 0;
  bool camerasThrow = false;

  @override
  Future<List<PpgCameraInfo>> cameras() async {
    if (camerasThrow) throw StateError('synthetischer Fehler');
    return super.cameras();
  }

  @override
  Future<PpgCameraAvailability> availability() {
    availabilityCalls++;
    return super.availability();
  }
}

PpgPreviewFrame _frame(
  PpgCameraRef ref,
  double t, {
  bool finger = true,
  int exposureNs = 10000000,
}) => PpgPreviewFrame(
  camera: ref,
  t: t,
  r: finger ? 200 : 167,
  g: finger ? 40 : 194,
  exposureNs: exposureNs,
  iso: 100,
);

typedef _S = ({
  _CountingCamera cam,
  _SpyChoice choice,
  SettingsDeveloperModeStore dev,
  CameraFinderController c,
});

Future<_S> _setup({List<PpgCameraInfo> cameras = _cameras}) async {
  final session = await FakeStorage().open(Uint8List(32));
  final clock = FakeClock(DateTime.utc(2026, 11, 24));
  final cam = _CountingCamera()..cameraList = cameras;
  final choice = _SpyChoice(
    SettingsPpgCameraChoiceStore(session.settings, clock),
  );
  return (
    cam: cam,
    choice: choice,
    dev: SettingsDeveloperModeStore(session.settings, clock),
    c: CameraFinderController(camera: cam, choice: choice),
  );
}

void main() {
  test(
    'startet die Vorschau aller nutzbaren Kameras, Taschenlampe an',
    () async {
      final s = await _setup();
      await s.c.load();
      await pumpEventQueue();
      expect(s.c.phase, CameraFinderPhase.running);
      expect(s.cam.previewWith.single, [_std, _second]);
      expect(s.cam.previewOn, isTrue);
      expect(s.cam.torchOn, isTrue);
      expect(s.c.cameras.map((c) => c.ref), [_std, _second]);
      s.c.dispose();
    },
  );

  test('Standard ohne Finger, zweite mit Finger: Empfehlung zweite, Übernehmen setzt das '
      'Suchergebnis, danach startet die Messung die zweite Kamera', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    expect(s.c.recommendation, isNull);
    expect(s.c.canApply, isFalse);
    for (var i = 0; i < 10; i++) {
      s.cam
        ..emitPreview(_frame(_std, i * 0.1, finger: false))
        ..emitPreview(_frame(_second, i * 0.1));
    }
    await pumpEventQueue();
    expect(s.c.stateOf(_cameras[1]).fingerDetected, isTrue);
    expect(s.c.stateOf(_cameras[0]).fingerDetected, isFalse);
    expect(s.c.recommendation, _second);
    expect(s.c.canApply, isTrue);
    expect(await s.c.apply(), _second);
    expect(s.choice.writes, ['auto:0/2']);
    expect(s.cam.previewOn, isFalse);
    expect(s.cam.torchOn, isFalse);
    s.c.dispose();
    // Ohne Entwicklermodus und ohne Wahl von Hand gilt das Suchergebnis (resolvePpgCamera).
    expect(
      await choosePpgCamera(
        camera: s.cam,
        developerMode: s.dev.read,
        choice: s.choice,
      ),
      _second,
    );
  });

  test(
    'Tipp überstimmt die Empfehlung; feste Wahl setzt die Wahl von Hand',
    () async {
      final s = await _setup();
      await s.c.load();
      await pumpEventQueue();
      s.cam
        ..emitPreview(_frame(_std, 0, finger: false))
        ..emitPreview(_frame(_second, 0));
      await pumpEventQueue();
      expect(s.c.recommendation, _second);
      s.c.select(_std);
      expect(s.c.selected, _std);
      expect(s.c.target, _std);
      expect(await s.c.apply(manual: true), _std);
      expect(s.choice.writes, ['manual:0']);
      await s.dev.set(true);
      expect(
        await choosePpgCamera(
          camera: s.cam,
          developerMode: s.dev.read,
          choice: s.choice,
        ),
        _std,
      );
      s.c.dispose();
    },
  );

  test(
    'ohne Empfehlung und ohne Tipp ist Übernehmen gesperrt, nichts gespeichert',
    () async {
      final s = await _setup();
      await s.c.load();
      await pumpEventQueue();
      s.cam
        ..emitPreview(_frame(_std, 0, finger: false))
        ..emitPreview(_frame(_second, 0, finger: false));
      await pumpEventQueue();
      expect(s.c.recommendation, isNull);
      expect(s.c.canApply, isFalse);
      expect(await s.c.apply(), isNull);
      expect(s.choice.writes, isEmpty);
      // Nicht nutzbare oder unbekannte Kamera lässt sich nicht antippen.
      s.c.select(_noFlash);
      s.c.select(const PpgCameraRef('9'));
      expect(s.c.selected, isNull);
      s.c.dispose();
    },
  );

  test(
    'Zurück (dispose): Vorschau gestoppt, Taschenlampe aus, nichts gespeichert',
    () async {
      final s = await _setup();
      await s.c.load();
      await pumpEventQueue();
      s.cam.emitPreview(_frame(_second, 0));
      await pumpEventQueue();
      s.c.select(_second);
      s.c.dispose();
      await pumpEventQueue();
      expect(s.cam.previewOn, isFalse);
      expect(s.cam.torchOn, isFalse);
      expect(s.cam.previewStops, 1);
      expect(s.choice.writes, isEmpty);
    },
  );

  test('Hintergrund: Vorschau aus; Vordergrund: neu gestartet', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    await s.c.pause();
    expect(s.cam.previewOn, isFalse);
    expect(s.cam.torchOn, isFalse);
    s.c.resume();
    await pumpEventQueue();
    expect(s.cam.previewWith, hasLength(2));
    expect(s.cam.previewOn, isTrue);
    // Meldet die Kamera selbst „Hintergrund“, startet sie beim Zurückkommen ebenso neu.
    await s.cam.abortPreview(PpgCameraStopReason.background);
    await pumpEventQueue();
    expect(s.c.phase, CameraFinderPhase.running);
    expect(s.c.previewing, isFalse);
    s.c.resume();
    await pumpEventQueue();
    expect(s.cam.previewWith, hasLength(3));
    expect(s.choice.writes, isEmpty);
    s.c.dispose();
  });

  test(
    'Fehler einer Kamera: Grund je Kamera, nicht wählbar, nicht empfohlen',
    () async {
      final s = await _setup();
      await s.c.load();
      await pumpEventQueue();
      s.cam
        ..emitPreview(_frame(_second, 0))
        ..emitPreview(
          const PpgPreviewCameraFailed(_second, PpgCameraStopReason.busy),
        )
        ..emitPreview(_frame(_std, 0));
      await pumpEventQueue();
      expect(s.c.failureOf(_second), PpgCameraStopReason.busy);
      s.c.select(_second);
      expect(s.c.selected, isNull);
      expect(s.c.recommendation, _std);
      s.c.dispose();
    },
  );

  test('ausgefallene Kamera wird nicht empfohlen, auch mit 60 Bilder/s und mehr Licht', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    // Die Standardkamera (60 Bilder/s) hat Finger und viermal so viel Licht wie die
    // zweite (30 Bilder/s); ohne ihren Ausfall wäre sie die Empfehlung.
    s.cam
      ..emitPreview(_frame(_std, 0, exposureNs: 2500000))
      ..emitPreview(_frame(_second, 0));
    await pumpEventQueue();
    expect(s.c.recommendation, _std);
    s.cam.emitPreview(
      const PpgPreviewCameraFailed(_std, PpgCameraStopReason.disconnected),
    );
    await pumpEventQueue();
    expect(s.c.recommendation, _second);
    expect(s.c.target, _second);
    expect(await s.c.apply(), _second);
    expect(s.choice.writes, ['auto:0/2']);
    s.c.dispose();
  });

  test('angetippte Kamera fällt danach aus: Auswahl weg, Übernehmen speichert die Empfehlung', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    s.cam
      ..emitPreview(_frame(_std, 0))
      ..emitPreview(_frame(_second, 0));
    await pumpEventQueue();
    s.c.select(_second);
    expect(s.c.target, _second);
    s.cam.emitPreview(
      const PpgPreviewCameraFailed(_second, PpgCameraStopReason.busy),
    );
    await pumpEventQueue();
    expect(s.c.selected, isNull);
    expect(s.c.target, _std);
    expect(await s.c.apply(manual: true), _std);
    expect(s.choice.writes, ['manual:0']);
    s.c.dispose();
  });

  test('angetippte Kamera fällt aus, keine Empfehlung: Übernehmen gesperrt, nichts gespeichert', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    s.cam
      ..emitPreview(_frame(_std, 0, finger: false))
      ..emitPreview(_frame(_second, 0, finger: false));
    await pumpEventQueue();
    s.c.select(_second);
    expect(s.c.canApply, isTrue);
    s.cam.emitPreview(
      const PpgPreviewCameraFailed(_second, PpgCameraStopReason.busy),
    );
    await pumpEventQueue();
    expect(s.c.selected, isNull);
    expect(s.c.canApply, isFalse);
    expect(await s.c.apply(), isNull);
    expect(s.choice.writes, isEmpty);
    s.c.dispose();
  });

  test('Ende mit Fehler: Seite zeigt beendet, Übernehmen gesperrt', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    s.cam.emitPreview(_frame(_second, 0));
    await s.cam.abortPreview(PpgCameraStopReason.error);
    await pumpEventQueue();
    expect(s.c.phase, CameraFinderPhase.stopped);
    expect(s.c.canApply, isFalse);
    s.c.dispose();
  });

  test('Speichern scheitert: Fehler weiter, Vorschau läuft weiter', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    s.cam.emitPreview(_frame(_second, 0));
    await pumpEventQueue();
    s.choice.fail = true;
    await expectLater(s.c.apply(), throwsA(isA<StorageException>()));
    expect(s.cam.previewOn, isTrue);
    s.c.dispose();
  });

  test('Standardkamera verwenden: nur ohne Empfehlung und ohne Tipp, '
      'setzt das Suchergebnis auf die Standardkamera', () async {
    final s = await _setup();
    expect(s.c.canApplyDefault, isFalse); // vor dem Laden
    await s.c.load();
    await pumpEventQueue();
    expect(s.c.defaultCamera, _std);
    expect(s.c.canApplyDefault, isTrue);
    for (var i = 0; i < 10; i++) {
      s.cam.emitPreview(_frame(_second, i * 0.1));
    }
    await pumpEventQueue();
    expect(s.c.recommendation, _second);
    expect(s.c.canApplyDefault, isFalse);
    expect(await s.c.applyDefault(), isNull);
    expect(s.choice.writes, isEmpty);
    s.c.dispose();

    final t = await _setup();
    await t.c.load();
    await pumpEventQueue();
    expect(await t.c.applyDefault(), _std);
    expect(t.choice.writes, ['auto:0']);
    expect(t.cam.previewOn, isFalse);
    expect(t.cam.torchOn, isFalse);
    t.c.dispose();
  });

  test('Standardkamera verwenden auch nach Ende mit Fehler', () async {
    final s = await _setup();
    await s.c.load();
    await pumpEventQueue();
    await s.cam.abortPreview(PpgCameraStopReason.error);
    await pumpEventQueue();
    expect(s.c.phase, CameraFinderPhase.stopped);
    expect(s.c.canApplyDefault, isTrue);
    expect(await s.c.applyDefault(), _std);
    expect(s.choice.writes, ['auto:0']);
    s.c.dispose();
  });

  test('Standardkamera nicht nutzbar: kein Standardknopf', () async {
    final s = await _setup(
      cameras: const [
        PpgCameraInfo(
          ref: _std,
          isDefault: true,
          unusable: PpgCameraUnusable.noFlash,
        ),
        PpgCameraInfo(ref: _second, frameRate: 30),
        PpgCameraInfo(ref: PpgCameraRef('2'), frameRate: 30),
      ],
    );
    await s.c.load();
    await pumpEventQueue();
    expect(s.c.defaultCamera, isNull);
    expect(s.c.canApplyDefault, isFalse);
    expect(await s.c.applyDefault(), isNull);
    expect(s.choice.writes, isEmpty);
    s.c.dispose();
  });

  /// Keine Vorschau, keine Abfrage von Recht und Verfügbarkeit, kein Schreibzugriff.
  Future<void> expectNoPreview(_S s) async {
    await pumpEventQueue();
    expect(s.cam.previewWith, isEmpty);
    expect(s.cam.previewOn, isFalse);
    expect(s.cam.torchOn, isFalse);
    expect(s.cam.availabilityCalls, 0);
    expect(s.cam.permissionRequests, 0);
    expect(s.c.canApply, isFalse);
    expect(s.c.canApplyDefault, isFalse);
    expect(await s.c.apply(), isNull);
    expect(await s.c.apply(manual: true), isNull);
    expect(await s.c.applyDefault(), isNull);
    expect(s.choice.writes, isEmpty);
  }

  test('nur eine nutzbare Kamera: onlyOne, keine Vorschau', () async {
    final s = await _setup(cameras: [_cameras.first, _cameras.last]);
    await s.c.load();
    expect(s.c.phase, CameraFinderPhase.onlyOne);
    await expectNoPreview(s);
    s.c.dispose();
  });

  test('keine Kamera: noCamera, keine Vorschau, nichts gespeichert', () async {
    final s = await _setup(cameras: const []);
    await s.c.load();
    expect(s.c.phase, CameraFinderPhase.noCamera);
    await expectNoPreview(s);
    s.c.dispose();
  });

  test(
    'nur nicht nutzbare Kameras: noCamera, keine Vorschau, nichts gespeichert',
    () async {
      final s = await _setup(
        cameras: const [
          PpgCameraInfo(
            ref: _std,
            isDefault: true,
            unusable: PpgCameraUnusable.noFlash,
          ),
          PpgCameraInfo(
            ref: PpgCameraRef('2'),
            unusable: PpgCameraUnusable.frameRate,
          ),
        ],
      );
      await s.c.load();
      expect(s.c.phase, CameraFinderPhase.noCamera);
      expect(s.c.cameras, isEmpty);
      await expectNoPreview(s);
      s.c.dispose();
    },
  );

  test(
    'Kameraliste nicht lesbar: listFailed, keine Vorschau, nichts gespeichert',
    () async {
      final s = await _setup();
      s.cam.camerasThrow = true;
      await s.c.load();
      expect(s.c.phase, CameraFinderPhase.listFailed);
      expect(s.c.cameras, isEmpty);
      await expectNoPreview(s);
      s.c.dispose();
    },
  );

  test('ohne Kamera-Recht: Anfrage, dann Hinweis ohne Vorschau', () async {
    final s = await _setup();
    s.cam.availabilityState = PpgCameraAvailability.permissionDenied;
    await s.c.load();
    expect(s.cam.permissionRequests, 1);
    expect(s.c.phase, CameraFinderPhase.noPermission);
    expect(s.cam.previewWith, isEmpty);
    s.c.dispose();
  });

  test(
    'Wechsel: Bilder bleiben stehen, Empfehlung erst nach vollem Durchgang',
    () async {
      final s = await _setup();
      s.cam.previewMode = PpgPreviewMode.alternating;
      await s.c.load();
      await pumpEventQueue();
      expect(s.c.mode, PpgPreviewMode.alternating);
      s.cam.emitPreview(const PpgPreviewTurn(_std));
      for (var i = 0; i < 15; i++) {
        s.cam.emitPreview(_frame(_std, i * 0.1));
      }
      s.cam.emitPreview(const PpgPreviewTurn(_second));
      for (var i = 15; i < 30; i++) {
        s.cam.emitPreview(_frame(_second, i * 0.1, finger: false));
      }
      await pumpEventQueue();
      // Die Standardkamera hat Finger, aber die zweite ist noch nicht durch.
      expect(s.c.recommendation, isNull);
      // Das Fenster der Standardkamera steht, solange die zweite dran ist.
      expect(s.c.stateOf(_cameras[0]).frames, 15);
      expect(s.c.stateOf(_cameras[0]).fingerDetected, isTrue);
      s.cam.emitPreview(const PpgPreviewTurn(_std));
      await pumpEventQueue();
      expect(s.c.live, _std);
      expect(s.c.recommendation, _std);
      s.c.dispose();
    },
  );
}
