/// CRC-16 des FIT-Protokolls: CRC-16/ARC (Polynom x^16 + x^15 + x^2 + 1,
/// bitumgekehrt 0xA001, Startwert 0, ohne Endverknüpfung). Bitweise
/// gerechnet, keine Tabelle aus fremdem Code. Mit [crc] lässt sich die Summe
/// fortsetzen; über Daten samt angehängter Summe (little-endian) ergibt sie 0.
int fitCrc16(Iterable<int> bytes, [int crc = 0]) {
  var c = crc & 0xFFFF;
  for (final byte in bytes) {
    c ^= byte & 0xFF;
    for (var bit = 0; bit < 8; bit++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xA001 : c >> 1;
    }
  }
  return c;
}
