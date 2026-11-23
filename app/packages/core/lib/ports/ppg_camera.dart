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

/// Bildstatistik eines Bilds (keine Pixel).
final class PpgCameraFrame extends PpgCameraEvent {
  const PpgCameraFrame(this.frame);
  final PpgFrame frame;
}

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
/// tatsächlich geöffnete Kamera.
final class PpgCameraStarted extends PpgCameraEvent {
  const PpgCameraStarted(this.fps, this.camera);
  final int fps;
  final PpgCameraRef camera;
}

/// Belichtung und Weißabgleich sind gesperrt (2,5 s nach Aufnahmebeginn).
final class PpgCameraExposureLocked extends PpgCameraEvent {
  const PpgCameraExposureLocked();
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
  Stream<PpgCameraEvent> start({PpgCameraRef? camera});

  /// Beendet eine laufende Aufnahme (Torch aus, Sitzung und Gerät zu); der Strom endet.
  Future<void> stop();
}
