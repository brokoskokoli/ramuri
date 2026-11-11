import 'dart:typed_data';

import '../src/preprocessing/measurement.dart';
import 'storage.dart';

enum RawChannel { position, heartRate, altitude, steps }

/// Gespeicherte Rohzeile samt Id (Verweis aus der Vorverarbeitung).
class StoredRaw<T extends RawSample> {
  const StoredRaw(this.id, this.value);

  final int id;
  final T value;
}

/// Rohzeile im Zustand `unavailable` ohne Wert (FR-0057), zum Schreiben und
/// Lesen. Zeilen mit Wert bleiben als [RawPosition] usw., auch wenn ihr
/// Zustand `unavailable` ist.
class RawUnavailable extends RawSample {
  const RawUnavailable({
    required this.channel,
    required super.time,
    required super.source,
  }) : super(state: MeasurementState.unavailable);

  final RawChannel channel;
}

/// Stapel neuer Rohwerte, der in einer Transaktion angehängt wird.
class RawBatch {
  const RawBatch({
    this.positions = const [],
    this.heartRates = const [],
    this.altitudes = const [],
    this.steps = const [],
    this.unavailable = const [],
    this.rrPackets = const [],
  });

  final List<RawPosition> positions;
  final List<RawHeartRate> heartRates;
  final List<RawAltitude> altitudes;
  final List<RawSteps> steps;
  final List<RawUnavailable> unavailable;

  /// RR-Intervalle je BLE-Paket (FR-0213), eigene Tabelle, kein [RawChannel].
  final List<RrPacket> rrPackets;

  bool get isEmpty =>
      positions.isEmpty &&
      heartRates.isEmpty &&
      altitudes.isEmpty &&
      steps.isEmpty &&
      unavailable.isEmpty &&
      rrPackets.isEmpty;
}

/// Gelesene Rohwerte eines Laufs, je Kanal nach Zeit, dann Id sortiert. Die
/// Liste `unavailable` enthält alle Kanäle gemischt, ebenso sortiert.
class StoredRawData {
  const StoredRawData({
    required this.positions,
    required this.heartRates,
    required this.altitudes,
    required this.steps,
    required this.unavailable,
    this.rrPackets = const [],
  });

  final List<StoredRaw<RawPosition>> positions;
  final List<StoredRaw<RawHeartRate>> heartRates;
  final List<StoredRaw<RawAltitude>> altitudes;
  final List<StoredRaw<RawSteps>> steps;
  final List<StoredRaw<RawUnavailable>> unavailable;

  /// Nach Empfangszeit, dann Id sortiert.
  final List<StoredRrPacket> rrPackets;
}

/// Gespeichertes RR-Paket samt Id.
class StoredRrPacket {
  const StoredRrPacket(this.id, this.value);

  final int id;
  final RrPacket value;
}

/// Packt RR-Werte als uint16 little endian (Spalte `rr`, ein Wert 2 Byte).
Uint8List encodeRrIntervals(List<int> intervals) {
  final out = Uint8List(intervals.length * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < intervals.length; i++) {
    view.setUint16(i * 2, intervals[i], Endian.little);
  }
  return out;
}

/// Umkehrung von [encodeRrIntervals]. Ungerade Länge ist ein Fehler.
List<int> decodeRrIntervals(List<int> bytes) {
  if (bytes.length.isOdd) {
    throw const StorageException(StorageFailure.failed);
  }
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return List.unmodifiable([
    for (var i = 0; i < bytes.length; i += 2) view.getUint16(i, Endian.little),
  ]);
}

/// Rohdaten (ADR-0004 Punkt 1): nur anhängen und lesen. Zeit ist UTC mit
/// Mikrosekunden. Wie viele Werte ein Stapel hat, entscheidet der Aufrufer
/// (WP06, ADR-0005 Punkt 5).
abstract interface class RawDataStore {
  /// Hängt den ganzen Stapel an oder nichts. Unbekannter Lauf: `notFound`;
  /// nicht endlicher (NaN) Wert: `rejected`.
  Future<void> append(int runId, RawBatch batch);

  Future<StoredRawData> read(int runId);
}

/// Prüft einen Stapel vor dem Schreiben; Fake und Adapter nutzen dieselbe
/// Regel, damit sie sich nicht auseinanderentwickeln.
void validateRawBatch(RawBatch b) {
  bool bad(double? v) => v != null && v.isNaN;
  final invalid =
      b.positions.any(
        (p) =>
            bad(p.latitude) ||
            bad(p.longitude) ||
            bad(p.accuracyMeters) ||
            bad(p.speedMetersPerSecond) ||
            bad(p.speedAccuracyMetersPerSecond) ||
            bad(p.verticalAccuracyMeters),
      ) ||
      b.altitudes.any((a) => bad(a.meters) || bad(a.verticalAccuracyMeters));
  final badRr = b.rrPackets.any(
    (p) => p.intervals.isEmpty || p.intervals.any((v) => v < 0 || v > 0xFFFF),
  );
  if (invalid || badRr) throw const StorageException(StorageFailure.rejected);
}
