import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Stand der Seite „Kamera finden“ (FR-0220).
enum CameraFinderPhase {
  /// Kameraliste und Recht werden gelesen.
  loading,

  /// Höchstens eine nutzbare Kamera: keine Auswahl nötig, keine Vorschau.
  onlyOne,

  /// Ohne Kamera-Recht keine Vorschau.
  noPermission,

  /// Vorschau läuft (oder ist im Hintergrund angehalten).
  running,

  /// Vorschau endete mit Fehler ([CameraFinderController.stopReason]).
  stopped,
}

/// Steuert die Kamerasuche (FR-0220, PAR-227, PAR-228): startet die Vorschau aller nutzbaren
/// Rückkameras, führt je Kamera das Fenster für Fingerprüfung und Lichtmenge, leitet die
/// Empfehlung ab und speichert nur die Wahl ([apply]). Vorschaubilder und Zahlen bleiben im
/// Speicher, nichts davon geht in ein Log. Wiederverwendbar für die Suche aller Nutzer.
class CameraFinderController extends ChangeNotifier {
  CameraFinderController({required this.camera, required this.choice});

  final PpgCamera camera;
  final PpgCameraChoiceStore choice;

  CameraFinderPhase _phase = CameraFinderPhase.loading;
  CameraFinderPhase get phase => _phase;

  /// Die nutzbaren Kameras in der Reihenfolge von [PpgCamera.cameras].
  List<PpgCameraInfo> get cameras => List.unmodifiable(_cameras);
  List<PpgCameraInfo> _cameras = const [];

  final Map<PpgCameraRef, PpgCameraFinderWindow> _windows = {};
  final Map<PpgCameraRef, PpgCameraStopReason> _failed = {};
  final Set<PpgCameraRef> _passed = {};
  Map<PpgCameraRef, int> _textures = const {};

  PpgPreviewMode? _mode;

  /// Betrieb der laufenden Vorschau; `null` vor dem Start.
  PpgPreviewMode? get mode => _mode;

  PpgCameraRef? _live;

  /// Im Wechselbetrieb die gerade offene Kamera.
  PpgCameraRef? get live => _live;

  PpgCameraStopReason? _stopReason;
  PpgCameraStopReason? get stopReason => _stopReason;

  PpgCameraRef? _selected;

  /// Vom Nutzer angetippte Kamera; überstimmt die Empfehlung.
  PpgCameraRef? get selected => _selected;

  StreamSubscription<PpgPreviewEvent>? _sub;
  bool _paused = false;
  bool _disposed = false;

  /// Vorschau läuft (abonniert).
  bool get previewing => _sub != null;

  /// Texture des Vorschaubilds von [ref]; `null` = keine (Fläche in der Farbe der Zahlen).
  int? textureOf(PpgCameraRef ref) => _textures[ref];

  /// Grund, wenn [ref] keine Vorschau liefert.
  PpgCameraStopReason? failureOf(PpgCameraRef ref) => _failed[ref];

  /// Stand je Kamera (Fenster nach PAR-227).
  PpgCameraFinderState stateOf(PpgCameraInfo info) =>
      (_windows[info.ref] ?? PpgCameraFinderWindow(info)).state;

  /// Hellste Lichtmenge aller Kameras (Bezug des Balkens „Licht“); `null` ohne Lichtmenge.
  double? get maxLight {
    double? m;
    for (final c in _cameras) {
      final l = stateOf(c).light;
      if (l != null && (m == null || l > m)) m = l;
    }
    return m;
  }

  /// Empfehlung nach PAR-228 über die Kameras mit Vorschau; im Wechsel erst, wenn jede von
  /// ihnen einen vollen Durchgang hatte (PAR-227).
  PpgCameraRef? get recommendation {
    final active = [
      for (final c in _cameras)
        if (!_failed.containsKey(c.ref)) c,
    ];
    if (active.isEmpty) return null;
    if (_mode == PpgPreviewMode.alternating &&
        !active.every((c) => _passed.contains(c.ref))) {
      return null;
    }
    return recommendPpgCamera([for (final c in active) stateOf(c)]);
  }

  /// Was „Übernehmen“ speichern würde: die angetippte Kamera, sonst die Empfehlung.
  PpgCameraRef? get target => _selected ?? recommendation;

  bool get canApply => _phase == CameraFinderPhase.running && target != null;

  /// Liest die Kameras, fragt bei Bedarf das Kamera-Recht und startet die Vorschau.
  Future<void> load() async {
    List<PpgCameraInfo> all;
    try {
      all = await camera.cameras();
    } catch (_) {
      all = const [];
    }
    if (_disposed) return;
    _cameras = [
      for (final c in all)
        if (c.usable) c,
    ];
    if (_cameras.length < 2) {
      _set(CameraFinderPhase.onlyOne);
      return;
    }
    var a = await camera.availability();
    if (a == PpgCameraAvailability.permissionDenied) {
      a = await camera.requestPermission();
    }
    if (_disposed) return;
    if (a != PpgCameraAvailability.available) {
      _set(CameraFinderPhase.noPermission);
      return;
    }
    _phase = CameraFinderPhase.running;
    _start();
  }

  void _start() {
    if (_sub != null || _disposed) return;
    _windows.clear();
    _failed.clear();
    _passed.clear();
    _textures = const {};
    _mode = null;
    _live = null;
    late final StreamSubscription<PpgPreviewEvent> sub;
    sub = camera
        .preview([for (final c in _cameras) c.ref])
        .listen(
          _on,
          onDone: () {
            if (identical(_sub, sub)) _sub = null;
          },
        );
    _sub = sub;
    notifyListeners();
  }

  void _on(PpgPreviewEvent e) {
    switch (e) {
      case PpgPreviewStarted(:final mode, :final textures):
        _mode = mode;
        _textures = textures;
      case PpgPreviewTurn(camera: final ref):
        final prev = _live;
        if (prev != null && prev != ref) _passed.add(prev);
        _live = ref;
      case PpgPreviewFrame(camera: final ref):
        final info = _cameras.where((c) => c.ref == ref).firstOrNull;
        if (info == null) return;
        (_windows[ref] ??= PpgCameraFinderWindow(info)).add(e);
      case PpgPreviewCameraFailed(camera: final ref, :final reason):
        _failed[ref] = reason;
        if (_selected == ref) _selected = null;
      case PpgPreviewStopped(:final reason):
        _sub = null;
        if (reason == PpgCameraStopReason.background) {
          // Wie Hintergrund: beim Zurückkommen neu starten.
          _paused = true;
        } else {
          _stopReason = reason;
          _phase = CameraFinderPhase.stopped;
        }
    }
    if (!_disposed) notifyListeners();
  }

  /// Tipp auf das Bild einer nutzbaren Kamera mit Vorschau.
  void select(PpgCameraRef ref) {
    if (_phase != CameraFinderPhase.running) return;
    if (!_cameras.any((c) => c.ref == ref) || _failed.containsKey(ref)) return;
    _selected = ref;
    notifyListeners();
  }

  /// App im Hintergrund: Vorschau beenden (Taschenlampe aus).
  Future<void> pause() async {
    if (_sub == null) return;
    _paused = true;
    await _stop();
    if (!_disposed) notifyListeners();
  }

  /// App wieder im Vordergrund: Vorschau neu starten, wenn sie angehalten war.
  void resume() {
    if (!_paused || _phase != CameraFinderPhase.running) return;
    _paused = false;
    _start();
  }

  Future<void> _stop() async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
  }

  /// Beendet die Vorschau und speichert [target] als Ergebnis der Kamerasuche
  /// (`ppgCameraAuto`) bzw. mit [manual] als Wahl von Hand (`ppgCameraManual`). Sonst wird
  /// nichts geschrieben. Scheitert das Speichern, wirft es [StorageException] weiter, und die
  /// Vorschau läuft weiter.
  Future<PpgCameraRef?> apply({bool manual = false}) async {
    final ref = target;
    if (!canApply || ref == null) return null;
    if (manual) {
      await choice.setManual(ref);
    } else {
      await choice.setAuto(ref);
    }
    await _stop();
    return ref;
  }

  void _set(CameraFinderPhase p) {
    _phase = p;
    if (!_disposed) notifyListeners();
  }

  /// Zurück oder Seite geschlossen: Vorschau beenden, nichts speichern.
  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
