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
  Stream<PpgCameraEvent> start() {
    late final StreamController<PpgCameraEvent> c;
    c = StreamController<PpgCameraEvent>(
      onListen: () {
        startCount++;
        final reason = switch (_availability) {
          PpgCameraAvailability.available => null,
          PpgCameraAvailability.noCamera => PpgCameraStopReason.noCamera,
          PpgCameraAvailability.noFlash => PpgCameraStopReason.noFlash,
          PpgCameraAvailability.permissionDenied =>
            PpgCameraStopReason.permissionDenied,
        };
        if (reason != null) {
          c.add(PpgCameraStopped(reason));
          c.close();
          return;
        }
        torchOn = true;
        c.add(const PpgCameraStarted(60));
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
