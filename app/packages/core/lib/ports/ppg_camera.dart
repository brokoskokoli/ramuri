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

  /// Anteil gesättigter Pixel (Helligkeit ab 250 von 255) über alle bisherigen Bilder, 0 bis 1.
  final double? saturatedFraction;

  /// Ohne Inhalte (Gesundheitsdaten gehören nicht in Logs).
  @override
  String toString() => 'PpgCameraDetails';
}

/// Kamera läuft, Torch an; [fps] ist die gewählte feste Bildrate.
final class PpgCameraStarted extends PpgCameraEvent {
  const PpgCameraStarted(this.fps);
  final int fps;
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

  /// Startet die Aufnahme beim Abonnieren. Der Strom endet mit [PpgCameraStopped]
  /// (Abbruch mit Grund) oder, wenn die App abbestellt oder [stop] ruft, ohne Ereignis.
  /// Abbestellen schaltet Torch aus und schließt Sitzung und Gerät.
  Stream<PpgCameraEvent> start();

  /// Beendet eine laufende Aufnahme (Torch aus, Sitzung und Gerät zu); der Strom endet.
  Future<void> stop();
}
