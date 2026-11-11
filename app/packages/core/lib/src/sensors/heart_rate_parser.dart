import '../preprocessing/measurement.dart' show SensorContact;

/// Ausgewertetes Paket der Heart Rate Measurement (0x2A37).
///
/// Der Wert ist roh: Die Plausibilität (PAR-007) und den Kontakt (PAR-008)
/// bewertet der Herzfrequenzfilter, damit verworfene Werte mit Grund
/// gespeichert werden (FR-0057). Energie bleibt ungenutzt (ADR-0006 Punkt 1);
/// RR-Intervalle reicht das Paket roh weiter (FR-0213, ADR-0006 Nachtrag).
class HeartRateMeasurement {
  const HeartRateMeasurement(
    this.beatsPerMinute,
    this.contact, {
    this.rrIntervals = const [],
  });

  final int beatsPerMinute;
  final SensorContact contact;

  /// RR-Intervalle des Pakets in Sendereihenfolge, unverändert in 1/1024 s
  /// (je uint16, 0..65535). Leer, wenn das Gerät keine sendet.
  final List<int> rrIntervals;

  @override
  bool operator ==(Object other) =>
      other is HeartRateMeasurement &&
      other.beatsPerMinute == beatsPerMinute &&
      other.contact == contact &&
      _listEquals(other.rrIntervals, rrIntervals);

  @override
  int get hashCode =>
      Object.hash(beatsPerMinute, contact, Object.hashAll(rrIntervals));

  // Bewusst ohne RR-Werte: Gesundheitsdaten gehören in keine Logzeile (SEC-0001).
  @override
  String toString() =>
      'HeartRateMeasurement($beatsPerMinute, $contact, rr: ${rrIntervals.length})';

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Auswertung der Bluetooth-Merkmale des Heart Rate Service.
abstract final class HeartRateParser {
  static const _format16Bit = 0x01;
  static const _energyBit = 0x08;
  static const _rrBit = 0x10;
  static const _contactShift = 1;
  static const _contactMask = 0x03;
  static const _contactSupportedBit = 0x02;
  static const _contactDetectedBit = 0x01;
  static const _byteMask = 0xFF;
  static const _byteBits = 8;
  static const _maxPercent = 100;

  /// Wertet 0x2A37 aus. Verkürzte Pakete liefern `null`, nie eine Ausnahme.
  ///
  /// RR (Flag-Bit 4): nach Puls und (Bit 3) Energy Expended folgen beliebig
  /// viele uint16 LE in 1/1024 s. Ein unvollständiges Feld (fehlende Energie,
  /// einzelnes Rest-Byte) verwirft nie den Puls: Vollständige Werte bleiben,
  /// ein loses letztes Byte entfällt.
  static HeartRateMeasurement? parseMeasurement(List<int> data) {
    if (data.isEmpty || data.any((b) => b < 0 || b > _byteMask)) return null;
    final flags = data[0];
    final is16Bit = flags & _format16Bit != 0;
    final needed = is16Bit ? 3 : 2;
    if (data.length < needed) return null;
    final bpm = is16Bit
        ? data[1] |
              (data[2] << _byteBits) // Little Endian
        : data[1];
    var i = needed;
    if (flags & _energyBit != 0) i += 2;
    final rr = <int>[];
    if (flags & _rrBit != 0) {
      for (; i + 1 < data.length; i += 2) {
        rr.add(data[i] | (data[i + 1] << _byteBits));
      }
    }
    return HeartRateMeasurement(
      bpm,
      _contact(flags),
      rrIntervals: List.unmodifiable(rr),
    );
  }

  /// Bits 1 und 2: 0 und 1 = nicht unterstützt, 2 = kein Kontakt,
  /// 3 = Kontakt erkannt. Kein Kontakt zählt als `poor` (PAR-008).
  static SensorContact _contact(int flags) {
    final c = (flags >> _contactShift) & _contactMask;
    if (c & _contactSupportedBit == 0) return SensorContact.unsupported;
    return c & _contactDetectedBit != 0
        ? SensorContact.good
        : SensorContact.poor;
  }

  /// Wertet 0x2A19 (Batteriestand in Prozent) aus. Leer oder über 100 %
  /// ergibt `null`: kein erfundener Wert (FR-0016).
  static int? parseBattery(List<int> data) {
    if (data.isEmpty) return null;
    final v = data[0];
    return v >= 0 && v <= _maxPercent ? v : null;
  }
}
