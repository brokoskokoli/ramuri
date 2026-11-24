import '../../ports/ppg_camera.dart';
import 'ppg_parameters.dart';

/// Lichtmenge eines Vorschaubilds der Kamerasuche (FR-0220, PAR-228): mittlere Helligkeit Rot
/// der Bildmitte geteilt durch (Belichtungszeit in s × ISO / 100). Die Belichtungsautomatik
/// gleicht die Helligkeit aus; erst geteilt durch Belichtung und Verstärkung wird vergleichbar,
/// wie viel Licht ankommt. `null`, wenn eine Angabe fehlt, nicht endlich ist oder Belichtung
/// bzw. ISO nicht positiv sind.
double? ppgCameraLight(double? r, double? g, int? exposureNs, int? iso) {
  if (r == null || g == null || exposureNs == null || iso == null) return null;
  if (!r.isFinite || !g.isFinite || exposureNs <= 0 || iso <= 0) return null;
  return r / (exposureNs / 1e9 * iso / ppgCameraFinderIsoReference);
}

/// Stand einer Kamera in der Kamerasuche: gleitendes Mittel über die Bilder der letzten
/// PAR-227 ([ppgCameraFinderWindowSeconds]) Sensorzeit.
final class PpgCameraFinderState {
  const PpgCameraFinderState({
    required this.camera,
    required this.fingerDetected,
    required this.light,
    this.frames = 0,
    this.meanRed,
    this.meanGreen,
    this.exposureNs,
    this.iso,
  });

  final PpgCameraInfo camera;

  /// Fingerprüfung nach PAR-219 über das Fenster: Mittel Rot / Mittel Grün ≥ 1,5 und Rot > 0.
  final bool fingerDetected;

  /// Mittlere Lichtmenge ([ppgCameraLight]) der Bilder im Fenster, die alle Angaben haben;
  /// `null`, wenn keines sie hat.
  final double? light;

  /// Bilder im Fenster.
  final int frames;

  /// Mittel von Rot und Grün im Fenster (nur Anzeige im Entwicklermodus).
  final double? meanRed;
  final double? meanGreen;

  /// Belichtungszeit und ISO des letzten Bilds (nur Anzeige im Entwicklermodus).
  final int? exposureNs;
  final int? iso;

  /// Ohne Werte (gehören nicht in Logs).
  @override
  String toString() => 'PpgCameraFinderState';
}

/// Gleitendes Fenster je Kamera der Kamerasuche (PAR-227): sammelt die Zahlen der
/// Vorschaubilder nach Sensorzeit und fasst sie zu [PpgCameraFinderState] zusammen. Nur im
/// Speicher, nichts wird gespeichert.
final class PpgCameraFinderWindow {
  PpgCameraFinderWindow(this.camera);

  final PpgCameraInfo camera;
  final List<PpgPreviewFrame> _frames = [];

  /// Nimmt ein Bild auf und verwirft Bilder, die mehr als PAR-227 Sensorzeit älter sind als
  /// das neueste. Ein Bild mit nicht steigender Zeit (neue Zählung) beginnt das Fenster neu.
  void add(PpgPreviewFrame f) {
    if (_frames.isNotEmpty && f.t < _frames.last.t) _frames.clear();
    _frames.add(f);
    final from = f.t - ppgCameraFinderWindowSeconds;
    _frames.removeWhere((x) => x.t <= from);
  }

  bool get isEmpty => _frames.isEmpty;

  PpgCameraFinderState get state {
    if (_frames.isEmpty) {
      return PpgCameraFinderState(
        camera: camera,
        fingerDetected: false,
        light: null,
      );
    }
    var r = 0.0, g = 0.0, light = 0.0;
    var lights = 0;
    for (final f in _frames) {
      r += f.r;
      g += f.g;
      final l = ppgCameraLight(f.r, f.g, f.exposureNs, f.iso);
      if (l != null) {
        light += l;
        lights++;
      }
    }
    final n = _frames.length;
    return PpgCameraFinderState(
      camera: camera,
      fingerDetected: r > 0 && r >= ppgMinRedGreenRatio * g,
      light: lights == 0 ? null : light / lights,
      frames: n,
      meanRed: r / n,
      meanGreen: g / n,
      exposureNs: _frames.last.exposureNs,
      iso: _frames.last.iso,
    );
  }
}

/// Empfehlung der Kamerasuche nach PAR-228 aus [states] in der Reihenfolge von
/// [PpgCamera.cameras] (Standardkamera zuerst). Kandidaten sind die nutzbaren Kameras mit
/// erkanntem Finger (PAR-219) und bekannter Lichtmenge. Unter ihnen zählen zuerst nur die mit
/// der höchsten festen Bildrate ([PpgCameraInfo.frameRate], 60 vor 30; unbekannt zählt am
/// niedrigsten); darunter gewinnt die größte Lichtmenge. Liegt die zweitbeste weniger als
/// 10 % darunter, gewinnt die frühere der beiden in der Liste. Ohne Kandidat `null`.
PpgCameraRef? recommendPpgCamera(List<PpgCameraFinderState> states) {
  final candidates = [
    for (final s in states)
      if (s.camera.usable && s.fingerDetected && s.light != null) s,
  ];
  if (candidates.isEmpty) return null;
  var topRate = -1;
  for (final s in candidates) {
    final rate = s.camera.frameRate ?? 0;
    if (rate > topRate) topRate = rate;
  }
  final top = [
    for (final s in candidates)
      if ((s.camera.frameRate ?? 0) == topRate) s,
  ];
  // Größte und zweitgrößte Lichtmenge; bei Gleichstand gilt die frühere in der Liste.
  PpgCameraFinderState? best, second;
  for (final s in top) {
    if (best == null || s.light! > best.light!) {
      second = best;
      best = s;
    } else if (second == null || s.light! > second.light!) {
      second = s;
    }
  }
  if (second == null) return best!.camera.ref;
  final close =
      best!.light! - second.light! <
      ppgCameraFinderLightTieRelative * best.light!;
  if (close && top.indexOf(second) < top.indexOf(best)) {
    return second.camera.ref;
  }
  return best.camera.ref;
}
