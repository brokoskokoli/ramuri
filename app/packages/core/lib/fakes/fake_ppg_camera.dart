import 'dart:async';

import '../ports/ppg_camera.dart';
import '../src/ppg/ppg_evaluator.dart';

/// Fake der Kamera. Bildet die Zusagen des Ports nach: Torch ist an, solange der
/// Strom läuft, und nach jedem Ende (Abbestellen, [stop], Fehler, Hintergrund) aus.
class FakePpgCamera implements PpgCamera {
  FakePpgCamera([this._availability = PpgCameraAvailability.available]);

  PpgCameraAvailability _availability;
  StreamController<PpgCameraEvent>? _controller;

  /// Torch und Gerät sind offen (Zustand der Hardware).
  bool torchOn = false;
  int startCount = 0;
  int stopCount = 0;
  int permissionRequests = 0;

  /// `false`: der Strom sendet nie [PpgCameraStarted] (Kamera hängt beim Öffnen).
  bool sendStarted = true;

  /// Liste für [cameras]; Vorgabe: eine nutzbare Standardkamera `0`. Die erste mit
  /// `isDefault` ist die Standardkamera.
  List<PpgCameraInfo> cameraList = const [
    PpgCameraInfo(
      ref: PpgCameraRef('0'),
      focalLengthMm: 4.2,
      isDefault: true,
      frameRate: 60,
    ),
  ];

  /// Zahl der Aufrufe von [cameras].
  int camerasCount = 0;

  /// Argument `camera` jedes [start] in Reihenfolge (`null` = ohne Angabe).
  final List<PpgCameraRef?> startedWith = [];

  @override
  Future<List<PpgCameraInfo>> cameras() async {
    camerasCount++;
    return List.unmodifiable(cameraList);
  }

  set availabilityState(PpgCameraAvailability a) => _availability = a;

  /// Antwort auf die Rechteanfrage; vorgabe: unverändert.
  PpgCameraAvailability? afterPermissionRequest;

  @override
  Future<PpgCameraAvailability> availability() async => _availability;

  @override
  Future<PpgCameraAvailability> requestPermission() async {
    permissionRequests++;
    _availability = afterPermissionRequest ?? _availability;
    return _availability;
  }

  @override
  Stream<PpgCameraEvent> start({PpgCameraRef? camera}) {
    late final StreamController<PpgCameraEvent> c;
    c = StreamController<PpgCameraEvent>(
      onListen: () {
        startCount++;
        startedWith.add(camera);
        var reason = switch (_availability) {
          PpgCameraAvailability.available => null,
          PpgCameraAvailability.noCamera => PpgCameraStopReason.noCamera,
          PpgCameraAvailability.noFlash => PpgCameraStopReason.noFlash,
          PpgCameraAvailability.permissionDenied =>
            PpgCameraStopReason.permissionDenied,
        };
        // Wie der Android-Teil: die angegebene Kamera oder die Standardkamera, nie eine andere.
        PpgCameraInfo? info;
        if (reason == null) {
          for (final i in cameraList) {
            if (camera == null ? i.isDefault : i.ref == camera) {
              info = i;
              break;
            }
          }
          reason = switch (info?.unusable) {
            _ when info == null => PpgCameraStopReason.noCamera,
            null => null,
            PpgCameraUnusable.noFlash => PpgCameraStopReason.noFlash,
            PpgCameraUnusable.frameRate => PpgCameraStopReason.frameRate,
            PpgCameraUnusable.other => PpgCameraStopReason.error,
          };
        }
        if (reason != null) {
          c.add(PpgCameraStopped(reason));
          c.close();
          return;
        }
        torchOn = true;
        if (sendStarted) c.add(PpgCameraStarted(60, info!.ref));
      },
      onCancel: () => _release(c),
    );
    _controller = c;
    return c.stream;
  }

  void _release(StreamController<PpgCameraEvent> c) {
    torchOn = false;
    if (identical(_controller, c)) _controller = null;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    final c = _controller;
    if (c == null) return;
    _release(c);
    await c.close();
  }

  void emitFrame(PpgFrame frame) => _controller?.add(PpgCameraFrame(frame));

  void emitDetails(PpgCameraDetails details) => _controller?.add(details);

  void emitLocked() => _controller?.add(const PpgCameraExposureLocked());

  /// Abbruch mit Grund (Kamera belegt, getrennt, Hintergrund ...): Torch aus, Strom endet.
  Future<void> abort(PpgCameraStopReason reason) async {
    final c = _controller;
    if (c == null) return;
    _release(c);
    c.add(PpgCameraStopped(reason));
    await c.close();
  }
}
