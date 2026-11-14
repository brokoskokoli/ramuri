import 'dart:typed_data';

import '../src/ppg/ppg_evaluator.dart' show PpgQuality;
import '../src/preprocessing/measurement.dart' show RrPacket;
import '../src/profile/resting_hr_origin.dart' show RestingPosture;
import 'storage.dart' show StorageException, StorageFailure;
import 'storage_raw.dart' show StoredRrPacket;

/// Schlafdauer in Stufen (PAR-164K), freiwillige Selbstangabe bei der
/// Morgenmessung. Spalte `morning_measurements.sleep_band`.
enum SleepBand {
  under5('under5'),
  from5to6('from5to6'),
  from6to7('from6to7'),
  from7to8('from7to8'),
  over8('over8');

  const SleepBand(this.code);

  /// Wert in der Datenbank und im Archiv.
  final String code;

  static SleepBand? fromCode(String? code) {
    for (final b in values) {
      if (b.code == code) return b;
    }
    return null;
  }
}

/// Eine Kamera-Morgenmessung (FR-0215), wie sie gespeichert wird. Gespeichert
/// werden nur Messungen mit Puls ([PpgQuality.good] oder
/// [PpgQuality.limited]); der Ruhepuls wird auf eine Nachkommastelle gerundet
/// ([roundedRestingHr]). `null` bei RMSSD und Zeitrauschen heißt nicht
/// verfügbar, nie 0.
class MorningMeasurement {
  const MorningMeasurement({
    required this.measuredAt,
    required this.utcOffset,
    required this.posture,
    required this.deviceManufacturer,
    required this.deviceModel,
    required this.method,
    required this.methodVersion,
    required this.quality,
    required this.restingHrBpm,
    required this.cameraIntervalsMs,
    required this.beforeValidation,
    required this.outsideWindow,
    this.rmssdMs,
    this.timingNoiseMs,
    this.sleepBand,
  });

  /// Beginn der Messung (UTC im Speicher).
  final DateTime measuredAt;

  /// Versatz des Ortes zu UTC zu diesem Zeitpunkt (ganze Sekunden).
  final Duration utcOffset;
  final RestingPosture posture;

  /// `Build.MANUFACTURER` und `Build.MODEL`, keine Seriennummer.
  final String deviceManufacturer;
  final String deviceModel;
  final String method;
  final int methodVersion;
  final PpgQuality quality;
  final double restingHrBpm;
  final double? rmssdMs;
  final double? timingNoiseMs;
  final SleepBand? sleepBand;

  /// Kamera-Schlagabstände in ms (abgeleitete Zahlen, keine Bilder).
  final List<double> cameraIntervalsMs;

  /// Intern "vor der Validierung gemessen" (K62 Punkt 6); ändert weder Anzeige
  /// noch Rechnung, trennt nur später die Daten.
  final bool beforeValidation;

  /// "außerhalb des Morgenfensters": gespeichert, zählt nicht für die Reihe.
  final bool outsideWindow;

  /// Ruhepuls auf eine Nachkommastelle gerundet, wie er gespeichert wird.
  double get roundedRestingHr => roundRestingHr(restingHrBpm);

  /// Ohne Inhalte (Gesundheitsdaten gehören nicht in Logs).
  @override
  String toString() => 'MorningMeasurement';
}

/// Gespeicherte Morgenmessung samt Id.
class StoredMorningMeasurement {
  const StoredMorningMeasurement(this.id, this.value);

  final int id;
  final MorningMeasurement value;
}

/// Ruhepuls auf eine Nachkommastelle (halbe Werte weg von null).
double roundRestingHr(double bpm) => (bpm * 10).round() / 10;

/// Packt Schlagabstände (ms) als float32 little endian, 4 Byte je Wert
/// (Spalte `camera_ibi`); NaN markiert ein ungültiges Intervall.
Uint8List encodeCameraIntervals(List<double> intervalsMs) {
  final out = Uint8List(intervalsMs.length * 4);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < intervalsMs.length; i++) {
    view.setFloat32(i * 4, intervalsMs[i], Endian.little);
  }
  return out;
}

/// Umkehrung von [encodeCameraIntervals]; eine Länge, die kein Vielfaches
/// von 4 ist, ist ein Fehler.
List<double> decodeCameraIntervals(List<int> bytes) {
  if (bytes.length % 4 != 0) {
    throw const StorageException(StorageFailure.failed);
  }
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return List.unmodifiable([
    for (var i = 0; i < bytes.length; i += 4) view.getFloat32(i, Endian.little),
  ]);
}

/// Morgenmessungen (FR-0215) mit der Gurt-RR derselben Zeit (nur
/// Entwicklermodus, K61). Gehören keinem Lauf: [StorageSession.deleteRun]
/// berührt sie nicht, [StorageSession.deleteAll] leert sie. Jede Methode wirft
/// nur [StorageException].
abstract interface class MorningStore {
  /// Speichert die Messung samt Gurt-RR-Paketen in einer Transaktion (alles
  /// oder nichts) und gibt die Id zurück. Ungültiger Wert (siehe
  /// [checkMorningForStorage]): `rejected`.
  Future<int> add(
    MorningMeasurement measurement, {
    List<RrPacket> beltPackets = const [],
  });

  /// Alle Messungen nach Zeitpunkt, dann Id sortiert.
  Future<List<StoredMorningMeasurement>> list();

  /// Trägt die freiwillige Schlafstufe nach (oder löscht sie mit `null`); alles
  /// andere der Messung bleibt unverändert. Unbekannte Messung: `notFound`.
  Future<void> setSleepBand(int measurementId, SleepBand? band);

  /// Gurt-RR-Pakete der Messung nach Empfangszeit, dann Id sortiert; ohne
  /// Pakete leer. Unbekannte Messung: `notFound`.
  Future<List<StoredRrPacket>> beltPackets(int measurementId);
}

/// Ein Speicher, der Morgenmessungen führt; getrennt von [StorageSession]
/// (wie `WarningStorage`).
abstract interface class MorningStorage {
  MorningStore get morning;
}

/// Prüfung vor dem Speichern, gleich für Fake und Datenbank.
void checkMorningForStorage(
  MorningMeasurement m, {
  List<RrPacket> beltPackets = const [],
}) {
  bool bad(double? v, {bool allowZero = true}) =>
      v != null && (!v.isFinite || v < 0 || (!allowZero && v == 0));
  final invalid =
      m.quality == PpgQuality.unusable ||
      bad(m.restingHrBpm, allowZero: false) ||
      bad(m.rmssdMs) ||
      bad(m.timingNoiseMs) ||
      m.cameraIntervalsMs.any((v) => !v.isNaN && bad(v, allowZero: false)) ||
      m.method.isEmpty ||
      m.methodVersion < 1 ||
      m.utcOffset.inSeconds.abs() > 18 * 3600 ||
      m.utcOffset.inMicroseconds % Duration.microsecondsPerSecond != 0 ||
      beltPackets.any(
        (p) =>
            p.intervals.isEmpty || p.intervals.any((v) => v < 0 || v > 0xFFFF),
      );
  if (invalid) throw const StorageException(StorageFailure.rejected);
}
