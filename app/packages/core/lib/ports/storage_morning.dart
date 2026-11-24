import 'dart:typed_data';

import '../src/ppg/ppg_evaluator.dart'
    show PpgFrame, PpgQuality, PpgQualityReason;
import 'ppg_camera.dart'
    show PpgAwbVariant, PpgCameraDiagnostic, ppgIspValueCount;
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

/// Grund der Stufe „unbrauchbar“ einer gespeicherten Morgenmessung
/// (Spalte `morning_measurements.unusable_reason`, Name des Werts). Die Gründe
/// der Auswertung ([PpgQualityReason], gleiche Namen, [fromPpg]) und dazu
/// [restingHrOutOfRange]: die Auswertung lieferte einen Puls, er liegt aber
/// außerhalb PAR-017 (PAR-160K). Der Puls selbst wird dann nicht gespeichert.
enum MorningUnusableReason {
  insufficientData,
  invalidInput,
  weakSignal,
  tooManyDisturbances,
  frameGap,
  noFinger,
  flatSignal,
  analysisFailed,
  lowSignalQuality,
  someDisturbances,
  timingNoise,

  /// Nur Namensgleichheit mit [PpgQualityReason]: macht nie „unbrauchbar“ (PAR-230).
  fewConsistentBeats,

  /// Ruhepuls außerhalb PAR-017 (30 bis 120 bpm).
  restingHrOutOfRange;

  /// Derselbe Grund wie in der Auswertung.
  static MorningUnusableReason fromPpg(PpgQualityReason r) =>
      MorningUnusableReason.values.byName(r.name);

  /// Wert aus Datenbank oder Archiv; unbekannt: `null`.
  static MorningUnusableReason? fromName(String? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// Eine Kamera-Morgenmessung (FR-0215), wie sie gespeichert wird. Gespeichert
/// werden Messungen mit Puls ([PpgQuality.good] oder [PpgQuality.limited]) und,
/// nur im Entwicklermodus (K68), unbrauchbare ([PpgQuality.unusable], ohne
/// Puls, mit [unusableReason]); der Ruhepuls wird auf eine Nachkommastelle
/// gerundet ([roundedRestingHr]). `null` bei RMSSD und Zeitrauschen heißt nicht
/// verfügbar, nie 0. Unbrauchbare zählen nirgends ([isUsable]).
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
    required this.cameraIntervalsMs,
    required this.beforeValidation,
    required this.outsideWindow,
    this.restingHrBpm,
    this.windowStartS,
    this.windowEndS,
    this.restSkippedAfterS,
    this.unusableReason,
    this.rmssdMs,
    this.timingNoiseMs,
    this.sleepBand,
    this.chosen = false,
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

  /// Ruhepuls; `null` genau bei [PpgQuality.unusable].
  final double? restingHrBpm;
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

  /// Anfang und Ende des ausgewerteten Fensters in Sekunden seit
  /// Aufnahmebeginn (K66, Verfahren Version 2); beide oder keins (`null` =
  /// Verfahren ohne Fenstersuche). Die Validierung vergleicht genau dieses
  /// Fenster mit dem Gurt.
  final double? windowStartS;
  final double? windowEndS;

  /// Sekunden nach Beginn der Ruhephase, nach denen sie übersprungen wurde
  /// (K66); `null` = nicht übersprungen.
  final double? restSkippedAfterS;

  /// Grund der Stufe „unbrauchbar“; nur dort gesetzt (kann auch dann fehlen).
  final MorningUnusableReason? unusableReason;

  /// Vom Nutzer als gültige Messung des Tages gewählt (PAR-160K, Spalte
  /// `morning_measurements.chosen`). Geschrieben nur von [MorningStore.choose]
  /// und vom Archiv-Import; eine neue Messung ist nie gewählt. Ob sie zählt,
  /// entscheidet allein `countingMorningMeasurements`.
  final bool chosen;

  /// Darf der Nutzer sie als gültige Messung des Tages wählen (PAR-160K):
  /// brauchbar und im Morgenfenster.
  bool get isChoosable => isUsable && !outsideWindow;

  /// Zählt die Messung überhaupt (nicht unbrauchbar, K68).
  bool get isUsable => quality != PpgQuality.unusable;

  /// Ruhepuls auf eine Nachkommastelle gerundet, wie er gespeichert wird.
  double? get roundedRestingHr {
    final hr = restingHrBpm;
    return hr == null ? null : roundRestingHr(hr);
  }

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

/// Zeitstempelquelle der Kamera (Android `SENSOR_INFO_TIMESTAMP_SOURCE`).
enum CameraTimestampSource {
  unknown('unknown'),
  realtime('realtime');

  const CameraTimestampSource(this.code);

  /// Wert in der Datenbank und im Archiv.
  final String code;

  static CameraTimestampSource? fromCode(String? code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    return null;
  }
}

/// Kamera-Rohsignal einer Morgenmessung (K70, K72), nur im Entwicklermodus:
/// die Bildstatistik je Bild (Zeit, Mittel Rot und Grün, 16 Teilbereiche, keine
/// Pixel) samt Kamera-Angaben. `null` bei einer Angabe heißt: von der Kamera
/// nicht geliefert.
class MorningRawSignal {
  const MorningRawSignal({
    required this.frames,
    required this.frameGapCount,
    required this.frameGapTotalS,
    this.exposureTimeNs,
    this.iso,
    this.timestampSource,
    this.rollingShutterSkewNs,
    this.torchStrength,
    this.saturatedFraction,
    this.cameraId,
    this.physicalCameraId,
    this.focalLengthMm,
    this.ispFrames,
    this.diagnostics = const {},
    this.awbVariant,
  });

  final List<PpgFrame> frames;

  /// Werte der Bildverarbeitung je Bild (FR-0217, ADR-0011): je Eintrag von
  /// [frames] genau [ppgIspValueCount] Werte in der Reihenfolge von
  /// `PpgIspValue`, `NaN` = von der Kamera nicht gemeldet; `null` = nicht
  /// aufgezeichnet (ältere Messungen). Spalte `isp_frames`.
  final List<List<double>>? ispFrames;

  /// Tatsächlich gesetzte Diagnose-Schalter der Kamera (`PpgCameraStarted`);
  /// leer = Vorgabe des Verfahrens. Spalten `diag_*`.
  final Set<PpgCameraDiagnostic> diagnostics;

  /// Variante des festen Weißabgleichs; nur mit
  /// [PpgCameraDiagnostic.awbFixed]. Spalte `diag_awb_variant`.
  final PpgAwbVariant? awbVariant;

  /// Internes Merkmal „mit Diagnose-Einstellung der Kamera gemessen“ (FR-0217,
  /// E7c): mindestens ein Schalter war gesetzt. Ändert weder Anzeige noch
  /// Rechnung; die Messung geht nicht in die Validierung des Verfahrens ein.
  bool get withCameraDiagnostics => diagnostics.isNotEmpty;

  /// Belichtungszeit in Nanosekunden.
  final int? exposureTimeNs;
  final int? iso;
  final CameraTimestampSource? timestampSource;

  /// Rolling-Shutter-Versatz (Auslesedauer des Bilds) in Nanosekunden.
  final int? rollingShutterSkewNs;

  /// Stärke der Taschenlampe (Stufe der Kamera-API).
  final int? torchStrength;

  /// Anzahl der Bildlücken (Abstand über der Grenze der Auswertung) und ihre
  /// Gesamtdauer in Sekunden.
  final int frameGapCount;
  final double frameGapTotalS;

  /// Anteil gesättigter Pixel (0 bis 1); `null`, wenn die Kamera ihn nicht
  /// liefert.
  final double? saturatedFraction;

  /// Verwendete Kamera (FR-0220): Camera2-ID der geöffneten Kamera und, bei
  /// einer physischen Kamera einer logischen Mehrfachkamera, deren ID
  /// (`PpgCameraRef`); `null` = nicht bekannt (ältere Messungen). Eine
  /// physische Kamera gibt es nur mit [cameraId].
  final String? cameraId;
  final String? physicalCameraId;

  /// Kleinste Brennweite der verwendeten Kamera in mm (größer 0); `null` = nicht
  /// bekannt.
  final double? focalLengthMm;

  /// Ohne Inhalte (Gesundheitsdaten gehören nicht in Logs).
  @override
  String toString() => 'MorningRawSignal';
}

/// Bytes je Bild im Rohsignal: 35 float64 (t, r, g, r16, g16).
const int morningRawFrameBytes = 35 * 8;

/// Packt Bilder als float64 little endian, je Bild t, r, g, r16[0..15],
/// g16[0..15] (Spalte `frames`, [morningRawFrameBytes] Byte je Bild, bitgenau).
Uint8List encodeRawFrames(List<PpgFrame> frames) {
  final out = Uint8List(frames.length * morningRawFrameBytes);
  final view = ByteData.sublistView(out);
  var o = 0;
  void put(double v) {
    view.setFloat64(o, v, Endian.little);
    o += 8;
  }

  for (final f in frames) {
    put(f.t);
    put(f.r);
    put(f.g);
    f.r16.forEach(put);
    f.g16.forEach(put);
  }
  return out;
}

/// Umkehrung von [encodeRawFrames]; eine Länge, die kein Vielfaches von
/// [morningRawFrameBytes] ist, ist ein Fehler.
List<PpgFrame> decodeRawFrames(List<int> bytes) {
  if (bytes.length % morningRawFrameBytes != 0) {
    throw const StorageException(StorageFailure.failed);
  }
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  var o = 0;
  double get() {
    final v = view.getFloat64(o, Endian.little);
    o += 8;
    return v;
  }

  return List.unmodifiable([
    for (var i = 0; i < bytes.length ~/ morningRawFrameBytes; i++)
      PpgFrame(
        t: get(),
        r: get(),
        g: get(),
        r16: List.unmodifiable([for (var k = 0; k < 16; k++) get()]),
        g16: List.unmodifiable([for (var k = 0; k < 16; k++) get()]),
      ),
  ]);
}

/// Bytes je Bild der Werte der Bildverarbeitung: [ppgIspValueCount] float64.
const int morningIspFrameBytes = ppgIspValueCount * 8;

/// Packt die Werte der Bildverarbeitung als float64 little endian (Spalte
/// `isp_frames`, [morningIspFrameBytes] Byte je Bild, bitgenau samt `NaN`).
/// Ein Bild ohne genau [ppgIspValueCount] Werte ist ein Fehler.
Uint8List encodeIspFrames(List<List<double>> frames) {
  final out = Uint8List(frames.length * morningIspFrameBytes);
  final view = ByteData.sublistView(out);
  var o = 0;
  for (final f in frames) {
    if (f.length != ppgIspValueCount) {
      throw const StorageException(StorageFailure.rejected);
    }
    for (final v in f) {
      view.setFloat64(o, v, Endian.little);
      o += 8;
    }
  }
  return out;
}

/// Umkehrung von [encodeIspFrames]; eine Länge, die kein Vielfaches von
/// [morningIspFrameBytes] ist, ist ein Fehler.
List<List<double>> decodeIspFrames(List<int> bytes) {
  if (bytes.length % morningIspFrameBytes != 0) {
    throw const StorageException(StorageFailure.failed);
  }
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return List.unmodifiable([
    for (var i = 0; i < bytes.length ~/ morningIspFrameBytes; i++)
      List<double>.unmodifiable([
        for (var k = 0; k < ppgIspValueCount; k++)
          view.getFloat64((i * ppgIspValueCount + k) * 8, Endian.little),
      ]),
  ]);
}

/// Morgenmessungen (FR-0215) mit der Gurt-RR derselben Zeit (nur
/// Entwicklermodus, K61). Gehören keinem Lauf: [StorageSession.deleteRun]
/// berührt sie nicht, [StorageSession.deleteAll] leert sie. Jede Methode wirft
/// nur [StorageException], [choose] dazu [ArgumentError].
abstract interface class MorningStore {
  /// Speichert die Messung samt Gurt-RR-Paketen in einer Transaktion (alles
  /// oder nichts) und gibt die Id zurück. Ungültiger Wert (siehe
  /// [checkMorningForStorage]): `rejected`.
  ///
  /// [rawSignal] (Kamera-Rohsignal, nur Entwicklermodus, K70) wird in derselben
  /// Transaktion gespeichert und hängt an der Messung.
  Future<int> add(
    MorningMeasurement measurement, {
    List<RrPacket> beltPackets = const [],
    MorningRawSignal? rawSignal,
  });

  /// Alle Messungen nach Zeitpunkt, dann Id sortiert.
  Future<List<StoredMorningMeasurement>> list();

  /// Trägt die freiwillige Schlafstufe nach (oder löscht sie mit `null`); alles
  /// andere der Messung bleibt unverändert. Unbekannte Messung: `notFound`.
  Future<void> setSleepBand(int measurementId, SleepBand? band);

  /// Löscht die Schlafstufe an allen [measurementIds] in einer Transaktion
  /// (ganz oder gar nicht, PAR-164K: Abwählen an allen zählenden
  /// Morgenmessungen); alles andere der Messungen bleibt unverändert. Doppelte
  /// Ids sind erlaubt, eine leere Liste ändert nichts. Eine unbekannte Messung:
  /// `notFound`, und keine Messung ändert sich.
  Future<void> clearSleepBands(Iterable<int> measurementIds);

  /// Wählt die Messung als gültige Messung des Tages (PAR-160K): in einer
  /// Transaktion `chosen` an ihr setzen und an allen anderen Messungen derselben
  /// Reihe (Hersteller und Modell) am selben Ortstag (Zeitpunkt plus Versatz
  /// jeder Messung, wie `morningLocalDay`) löschen. Bestimmt die Schlafquelle
  /// des Tages vor der Wahl (`morningSleepSource` über alle zählenden
  /// Messungen des Ortstags) eine Stufe, steht diese Stufe danach in derselben
  /// Transaktion an der gewählten Messung (PAR-164K); sonst bleibt deren Stufe,
  /// wie sie ist. Unbekannte Messung: `notFound`; nicht wählbar
  /// ([MorningMeasurement.isChoosable] falsch): [ArgumentError]; in beiden
  /// Fällen ändert sich nichts.
  Future<void> choose(int measurementId);

  /// Gurt-RR-Pakete der Messung nach Empfangszeit, dann Id sortiert; ohne
  /// Pakete leer. Unbekannte Messung: `notFound`.
  Future<List<StoredRrPacket>> beltPackets(int measurementId);

  /// Kamera-Rohsignal der Messung oder `null`, wenn keins gespeichert wurde.
  /// Unbekannte Messung: `notFound`.
  Future<MorningRawSignal?> rawSignal(int measurementId);
}

/// Ein Speicher, der Morgenmessungen führt; getrennt von [StorageSession]
/// (wie `WarningStorage`).
abstract interface class MorningStorage {
  MorningStore get morning;
}

/// Höchstzahl Bilder des Rohsignals einer Messung: 120 s (`ppgSearchMaxRecordSeconds`) bei bis zu
/// 120 Bildern/s. Grund: Eine Archivzeile darf höchstens 16 MiB haben (der Leser lehnt größere als
/// beschädigt ab), das Rohsignal braucht als Hex 560 Byte je Bild (rund 8 MiB bei 14 400 Bildern,
/// gut das Doppelte Abstand); ab etwa 29 900 Bildern würde die App ein Archiv schreiben, das sie
/// selbst nicht mehr liest. Darüber wird das Speichern abgelehnt (`rejected`) statt still gekürzt:
/// Die Aufnahme endet nach 120 s, mehr Bilder sind ein Fehler des Aufrufers. Wert: PAR-216.
const int morningRawMaxFrames = 120 * 120;

/// Prüfung vor dem Speichern, gleich für Fake und Datenbank.
void checkMorningForStorage(
  MorningMeasurement m, {
  List<RrPacket> beltPackets = const [],
  MorningRawSignal? rawSignal,
}) {
  bool bad(double? v, {bool allowZero = true}) =>
      v != null && (!v.isFinite || v < 0 || (!allowZero && v == 0));
  final unusable = m.quality == PpgQuality.unusable;
  final ws = m.windowStartS;
  final we = m.windowEndS;
  final raw = rawSignal;
  final invalid =
      // Ruhepuls genau bei brauchbaren Messungen, Grund nur bei unbrauchbaren.
      (m.restingHrBpm == null) != unusable ||
      (!unusable && m.unusableReason != null) ||
      // Bei „unbrauchbar“ gibt es keine Kennwerte (Doku ALGORITHMUS.md Abschn. 11).
      (unusable && (m.rmssdMs != null || m.timingNoiseMs != null)) ||
      (ws == null) != (we == null) ||
      bad(ws) ||
      bad(we) ||
      (ws != null && we != null && we <= ws) ||
      bad(m.restSkippedAfterS) ||
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
      ) ||
      (raw != null &&
          (raw.frames.length > morningRawMaxFrames ||
              raw.frames.any(
                (f) =>
                    f.r16.length != 16 ||
                    f.g16.length != 16 ||
                    !f.t.isFinite ||
                    !f.r.isFinite ||
                    !f.g.isFinite ||
                    f.r16.any((v) => !v.isFinite) ||
                    f.g16.any((v) => !v.isFinite),
              ) ||
              raw.frameGapCount < 0 ||
              bad(raw.frameGapTotalS) ||
              (raw.exposureTimeNs != null && raw.exposureTimeNs! <= 0) ||
              (raw.iso != null && raw.iso! <= 0) ||
              (raw.rollingShutterSkewNs != null &&
                  raw.rollingShutterSkewNs! < 0) ||
              (raw.torchStrength != null && raw.torchStrength! < 0) ||
              (raw.saturatedFraction != null &&
                  !(raw.saturatedFraction! >= 0 &&
                      raw.saturatedFraction! <= 1)) ||
              (raw.physicalCameraId != null && raw.cameraId == null) ||
              (raw.focalLengthMm != null &&
                  !(raw.focalLengthMm!.isFinite && raw.focalLengthMm! > 0)) ||
              // Je Bild genau 19 Werte, endlich oder NaN (nicht gemeldet).
              (raw.ispFrames != null &&
                  (raw.ispFrames!.length != raw.frames.length ||
                      raw.ispFrames!.any(
                        (v) =>
                            v.length != ppgIspValueCount ||
                            v.any((x) => x.isInfinite),
                      ))) ||
              // Variante nur mit festem Weißabgleich.
              (raw.awbVariant != null &&
                  !raw.diagnostics.contains(PpgCameraDiagnostic.awbFixed))));
  if (invalid) throw const StorageException(StorageFailure.rejected);
}
