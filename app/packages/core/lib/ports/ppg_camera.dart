import '../src/ppg/ppg_evaluator.dart';
import 'storage_morning.dart' show CameraTimestampSource;

/// Verfügbarkeit der Kamera-Messung (ADR-0011 Punkt 6). Ohne Kamera, Blitz oder
/// Recht bleibt die manuelle Eingabe (FR-0214); das ist kein Fehler.
enum PpgCameraAvailability { available, noCamera, noFlash, permissionDenied }

/// Warum die Aufnahme endete, ohne dass die App sie beendet hat. Jeder Fall ist ein
/// Ergebnis mit Grund, nie ein Absturz (ADR-0011 Punkt 6).
enum PpgCameraStopReason {
  permissionDenied,
  noCamera,
  noFlash,

  /// Kamera von einer anderen App belegt.
  busy,

  /// Kamera getrennt oder vom System entzogen.
  disconnected,

  /// Keine feste Bildrate von mindestens 30 fps.
  frameRate,

  /// Die App ging in den Hintergrund.
  background,

  /// Sonstiger Fehler der Kamera.
  error,
}

/// Kennung einer Rückkamera (FR-0220): [cameraId] ist die Camera2-ID der geöffneten
/// Kamera; [physicalCameraId] ist `null`, wenn diese Kamera selbst Bilder liefert, sonst
/// die ID einer physischen Kamera (eines Objektivs) der logischen Mehrfachkamera
/// [cameraId]. Zwei Kennungen sind gleich, wenn beide Felder gleich sind.
///
/// Kamera-Kennungen sind keine Gesundheitsdaten, aber gerätespezifisch: nicht in Logs
/// außerhalb des Debug-Builds; [toString] nennt sie deshalb nicht.
final class PpgCameraRef {
  const PpgCameraRef(this.cameraId, [this.physicalCameraId]);

  final String cameraId;
  final String? physicalCameraId;

  /// Gespeicherte Form `<cameraId>` bzw. `<cameraId>/<physicalCameraId>`
  /// (Einstellungen `ppgCameraManual`, `ppgCameraAuto`).
  String get key =>
      physicalCameraId == null ? cameraId : '$cameraId/$physicalCameraId';

  /// Liest die gespeicherte Form ([key]); Leeres oder Unpassendes ergibt `null`.
  static PpgCameraRef? parse(String? key) {
    if (key == null || key.isEmpty) return null;
    final parts = key.split('/');
    if (parts.length > 2 || parts.any((p) => p.isEmpty)) return null;
    return PpgCameraRef(parts[0], parts.length == 2 ? parts[1] : null);
  }

  @override
  bool operator ==(Object other) =>
      other is PpgCameraRef &&
      other.cameraId == cameraId &&
      other.physicalCameraId == physicalCameraId;

  @override
  int get hashCode => Object.hash(cameraId, physicalCameraId);

  @override
  String toString() => 'PpgCameraRef';
}

/// Warum eine Kamera nicht für die Messung taugt (nur Anzeige).
enum PpgCameraUnusable {
  /// Die Taschenlampe lässt sich mit dieser Kamera nicht einschalten.
  noFlash,

  /// Keine feste Bildrate zwischen 30 und 60 fps.
  frameRate,

  /// Sonst nicht nutzbar (keine passende Bildgröße, Eigenschaften nicht lesbar).
  other,
}

/// Beschreibung einer Rückkamera aus [PpgCamera.cameras] (FR-0220).
final class PpgCameraInfo {
  const PpgCameraInfo({
    required this.ref,
    this.focalLengthMm,
    this.isDefault = false,
    this.unusable,
    this.frameRate,
  });

  final PpgCameraRef ref;

  /// Kleinste Brennweite in mm (`LENS_INFO_AVAILABLE_FOCAL_LENGTHS`); `null`, wenn unbekannt.
  final double? focalLengthMm;

  /// Die Standardkamera: die erste Rückkamera mit Blitz (die Kamera ohne Angabe in [PpgCamera.start]).
  final bool isDefault;

  /// Grund, wenn die Kamera nicht nutzbar ist; `null` = nutzbar.
  final PpgCameraUnusable? unusable;

  /// Bilder pro Sekunde, mit denen die Messung auf dieser Kamera liefe (höchste feste
  /// Bildrate 30 bis 60, 60 vor 30, ADR-0011); `null` = unbekannt (FR-0220).
  final int? frameRate;

  /// Taschenlampe schaltbar, feste Bildrate 30 bis 60 fps und passende Bildgröße.
  bool get usable => unusable == null;

  @override
  String toString() => 'PpgCameraInfo';
}

/// Ereignis des Aufnahmestroms. Nach [PpgCameraStopped] endet der Strom.
sealed class PpgCameraEvent {
  const PpgCameraEvent();
}

/// Bildstatistik eines Bilds (keine Pixel). [isp] sind die von der Kamera zu
/// genau diesem Bild gemeldeten Werte der Bildverarbeitung und Belichtung
/// ([ppgIspValueCount] Werte in der Reihenfolge von [PpgIspValue], `NaN` = nicht
/// gemeldet); `null`, wenn sie nicht angefordert wurden ([PpgCamera.start] mit
/// `ispFrames`). Sie gehören bewusst nicht zu [PpgFrame]: die Auswertung sieht sie nie.
final class PpgCameraFrame extends PpgCameraEvent {
  const PpgCameraFrame(this.frame, [this.isp]);
  final PpgFrame frame;
  final List<double>? isp;
}

/// Diagnose-Schalter der Bildverarbeitung der Kamera (FR-0217, ADR-0011): nur
/// Morgenmessung im Entwicklermodus, Vorgabe jeweils aus. [wire] ist der Name im
/// Kanal und in der gespeicherten Form.
enum PpgCameraDiagnostic {
  /// Rauschunterdrückung aus (`NOISE_REDUCTION_MODE_OFF`).
  noiseReductionOff('noise_reduction_off'),

  /// Kantenschärfung aus (`EDGE_MODE_OFF`).
  edgeOff('edge_off'),

  /// Weißabgleich fest ab Start ([PpgAwbVariant]).
  awbFixed('awb_fixed'),

  /// Tonwertkurve linear (`TONEMAP_MODE_CONTRAST_CURVE`, (0,0)–(1,1)).
  tonemapLinear('tonemap_linear'),

  /// Linsenschattierung fest (`SHADING_MODE_OFF`).
  shadingOff('shading_off');

  const PpgCameraDiagnostic(this.wire);
  final String wire;

  static PpgCameraDiagnostic? fromWire(Object? s) {
    for (final d in values) {
      if (d.wire == s) return d;
    }
    return null;
  }
}

/// Wie der Weißabgleich fest ab Start gehalten wird: [matrix] = AWB aus mit den
/// Farbverstärkungen und der Matrix des ersten eingeschwungenen Ergebnisses
/// (spätestens bei 0,5 s), [lock] = AWB-Sperre ab dem ersten Bild.
enum PpgAwbVariant {
  matrix('matrix'),
  lock('lock');

  const PpgAwbVariant(this.wire);
  final String wire;

  static PpgAwbVariant? fromWire(Object? s) {
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// Werte der Bildverarbeitung je Bild in dieser Reihenfolge (Kanal, Speicher,
/// Messpaare-CSV). Zustände und Modi sind Ganzzahl-Codes der Kamera-API.
enum PpgIspValue {
  /// `COLOR_CORRECTION_GAINS` R, G gerade, G ungerade, B.
  gainR,
  gainGEven,
  gainGOdd,
  gainB,

  /// `CONTROL_AWB_STATE`.
  awbState,

  /// `CONTROL_AWB_MODE`.
  awbMode,

  /// `COLOR_CORRECTION_MODE`.
  colorCorrectionMode,

  /// `NOISE_REDUCTION_MODE`.
  noiseReductionMode,

  /// `EDGE_MODE`.
  edgeMode,

  /// `TONEMAP_MODE`.
  tonemapMode,

  /// `SHADING_MODE`.
  shadingMode,

  /// `SENSOR_EXPOSURE_TIME` in ns.
  exposureTimeNs,

  /// `SENSOR_SENSITIVITY`.
  sensitivity,

  /// `CONTROL_AE_STATE`.
  aeState,

  /// `SENSOR_FRAME_DURATION` in ns.
  frameDurationNs,

  /// `CONTROL_AF_MODE`.
  afMode,

  /// `LENS_FOCUS_DISTANCE` in Dioptrien.
  focusDistance,

  /// `LENS_OPTICAL_STABILIZATION_MODE`.
  oisMode,

  /// `LENS_STATE`.
  lensState,
}

/// Anzahl der Werte je Bild ([PpgIspValue]).
const int ppgIspValueCount = 19;

/// Kamera-Angaben der Aufnahme (K70, R010), gemeldet nach der Sperre von Belichtung
/// und Weißabgleich und danach gelegentlich erneuert (der Anteil gesättigter Pixel
/// wächst mit); der letzte Stand gilt. Nur Zahlen der Kamera-API, keine Bilder. Was
/// das Gerät nicht liefert, ist `null`.
final class PpgCameraDetails extends PpgCameraEvent {
  const PpgCameraDetails({
    this.exposureTimeNs,
    this.iso,
    this.timestampSource,
    this.rollingShutterSkewNs,
    this.torchStrength,
    this.saturatedFraction,
  });

  /// Belichtungszeit (`SENSOR_EXPOSURE_TIME`) in Nanosekunden.
  final int? exposureTimeNs;

  /// Empfindlichkeit (`SENSOR_SENSITIVITY`).
  final int? iso;

  /// `SENSOR_INFO_TIMESTAMP_SOURCE` der Kamera.
  final CameraTimestampSource? timestampSource;

  /// `SENSOR_ROLLING_SHUTTER_SKEW` in Nanosekunden.
  final int? rollingShutterSkewNs;

  /// `FLASH_STRENGTH_LEVEL` (erst ab Android 15).
  final int? torchStrength;

  /// Anteil gesättigter Pixel (Helligkeit ab 250 von 255, PAR-217) über alle bisherigen
  /// Bilder, 0 bis 1.
  final double? saturatedFraction;

  /// Ohne Inhalte (Gesundheitsdaten gehören nicht in Logs).
  @override
  String toString() => 'PpgCameraDetails';
}

/// Kamera läuft, Torch an; [fps] ist die gewählte feste Bildrate, [camera] die
/// tatsächlich geöffnete Kamera. [diagnostics] sind die tatsächlich gesetzten
/// Diagnose-Schalter (Teilmenge der angeforderten: nur, was die Kamera anbietet),
/// [awbVariant] die Variante bei [PpgCameraDiagnostic.awbFixed].
final class PpgCameraStarted extends PpgCameraEvent {
  const PpgCameraStarted(
    this.fps,
    this.camera, {
    this.diagnostics = const {},
    this.awbVariant,
  });
  final int fps;
  final PpgCameraRef camera;
  final Set<PpgCameraDiagnostic> diagnostics;
  final PpgAwbVariant? awbVariant;
}

/// Belichtung und Weißabgleich sind gesperrt: 2,5 s nach Aufnahmebeginn und nach
/// jedem Neu-Einschwingen ([PpgCameraRelocking], PAR-246). [t] ist die Sensorzeit
/// der Sperre (Sekunden seit Aufnahmebeginn wie [PpgFrame.t]); `null`, wenn die
/// Gegenseite sie nicht meldet (ältere Fassung: Verhalten wie bei der ersten Sperre).
final class PpgCameraExposureLocked extends PpgCameraEvent {
  const PpgCameraExposureLocked([this.t]);
  final double? t;
}

/// Nach einem Helligkeitssprung im Rot (PAR-245) und anschließender Ruhe beginnt
/// bei Sensorzeit [t] das Neu-Einschwingen der Belichtung; die neue Sperre folgt
/// 2,5 s später mit [PpgCameraExposureLocked] (PAR-246).
final class PpgCameraRelocking extends PpgCameraEvent {
  const PpgCameraRelocking(this.t);
  final double t;
}

/// Die Aufnahme wurde beendet: Torch aus, Sitzung und Gerät geschlossen.
final class PpgCameraStopped extends PpgCameraEvent {
  const PpgCameraStopped(this.reason);
  final PpgCameraStopReason reason;
}

/// Port: Rückkamera mit Blitz als Bildstatistik-Quelle für das Kamera-PPG (ADR-0011).
abstract interface class PpgCamera {
  /// Stand ohne Rechteanfrage.
  Future<PpgCameraAvailability> availability();

  /// Fragt das Kamera-Recht (nur bei Messbeginn) und liefert danach die Verfügbarkeit.
  /// Ablehnung ist kein Fehler.
  Future<PpgCameraAvailability> requestPermission();

  /// Alle Rückkameras ohne Rechteanfrage (Eigenschaften brauchen kein Kamera-Recht),
  /// auch die physischen Kameras einer logischen Mehrfachkamera (FR-0220). Reihenfolge:
  /// Standardkamera zuerst, dann nach `cameraId`, dann `physicalCameraId` (die Kamera
  /// selbst vor ihren physischen). Leer ohne Rückkamera oder bei einem Fehler.
  Future<List<PpgCameraInfo>> cameras();

  /// Startet die Aufnahme beim Abonnieren mit [camera], ohne Angabe mit der
  /// Standardkamera. Startet die angegebene Kamera nicht (unbekannt, nicht nutzbar,
  /// Fehler), endet der Strom mit [PpgCameraStopped] – nie mit einer anderen Kamera.
  /// Der Strom endet mit [PpgCameraStopped] (Abbruch mit Grund) oder, wenn die App
  /// abbestellt oder [stop] ruft, ohne Ereignis. Abbestellen schaltet Torch aus und
  /// schließt Sitzung und Gerät.
  ///
  /// [diagnostics] (Diagnose-Schalter) und [ispFrames] (Werte der
  /// Bildverarbeitung je Bild, [PpgCameraFrame.isp]) fordert nur die
  /// Morgenmessung im Entwicklermodus an (FR-0217); ohne Angabe gilt die Vorgabe
  /// des Verfahrens.
  Stream<PpgCameraEvent> start({
    PpgCameraRef? camera,
    Set<PpgCameraDiagnostic> diagnostics = const {},
    bool ispFrames = false,
  });

  /// Beendet eine laufende Aufnahme (Torch aus, Sitzung und Gerät zu); der Strom endet.
  Future<void> stop();
}
