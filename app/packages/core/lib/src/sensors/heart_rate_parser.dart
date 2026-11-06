import '../preprocessing/measurement.dart' show SensorContact;

/// Ausgewertetes Paket der Heart Rate Measurement (0x2A37).
///
/// Der Wert ist roh: Die Plausibilität (PAR-007) und den Kontakt (PAR-008)
/// bewertet der Herzfrequenzfilter, damit verworfene Werte mit Grund
/// gespeichert werden (FR-0057). RR-Intervalle und Energie bleiben ungenutzt
/// (ADR-0006 Punkt 1).
class HeartRateMeasurement {
  const HeartRateMeasurement(this.beatsPerMinute, this.contact);

  final int beatsPerMinute;
  final SensorContact contact;

  @override
  bool operator ==(Object other) =>
      other is HeartRateMeasurement &&
      other.beatsPerMinute == beatsPerMinute &&
      other.contact == contact;

  @override
  int get hashCode => Object.hash(beatsPerMinute, contact);

  @override
  String toString() => 'HeartRateMeasurement($beatsPerMinute, $contact)';
}

/// Auswertung der Bluetooth-Merkmale des Heart Rate Service.
abstract final class HeartRateParser {
  static const _format16Bit = 0x01;
  static const _contactShift = 1;
  static const _contactMask = 0x03;
  static const _contactSupportedBit = 0x02;
  static const _contactDetectedBit = 0x01;
  static const _byteMask = 0xFF;
  static const _byteBits = 8;
  static const _maxPercent = 100;

  /// Wertet 0x2A37 aus. Verkürzte Pakete liefern `null`, nie eine Ausnahme.
  /// Zusätzliche Bytes (Energie, RR) werden ignoriert.
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
    return HeartRateMeasurement(bpm, _contact(flags));
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
