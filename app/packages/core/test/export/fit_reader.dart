/// Minimaler FIT-Leser nur für Tests, unabhängig vom Kodierer geschrieben:
/// prüft Kopf, Länge, Kopf- und Datei-CRC (eigene Nibble-Tabelle aus dem
/// Polynom) und liefert je Datennachricht die Rohwerte der Felder.
library;

/// Fehler beim Lesen, z. B. falsche Prüfsumme.
class FitFormatException implements Exception {
  FitFormatException(this.message);
  final String message;
  @override
  String toString() => 'FitFormatException: $message';
}

/// Eine Datennachricht: globale Nummer und Rohwerte je Feldnummer (vorzeichen-
/// behaftete Typen vorzeichenrichtig, sonst vorzeichenlos).
typedef FitMessage = ({int global, Map<int, int> fields});

class FitFile {
  FitFile(this.headerSize, this.protocol, this.profile, this.messages);
  final int headerSize;
  final int protocol;
  final int profile;
  final List<FitMessage> messages;

  Iterable<FitMessage> of(int global) =>
      messages.where((m) => m.global == global);
}

/// CRC-16/ARC nibbleweise, Tabelle aus dem Polynom 0xA001 erzeugt.
final List<int> _table = [
  for (var n = 0; n < 16; n++)
    () {
      var c = n;
      for (var i = 0; i < 4; i++) {
        c = (c & 1) != 0 ? (c >> 1) ^ 0xA001 : c >> 1;
      }
      return c;
    }(),
];

int testCrc(Iterable<int> bytes) {
  var crc = 0;
  for (final b in bytes) {
    var tmp = _table[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ _table[b & 0xF];
    tmp = _table[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ _table[(b >> 4) & 0xF];
  }
  return crc;
}

int _uint(List<int> b, int at, int size, bool bigEndian) {
  var v = 0;
  for (var i = 0; i < size; i++) {
    final byte = b[bigEndian ? at + i : at + size - 1 - i];
    v = (v << 8) | byte;
  }
  return v;
}

FitFile readFit(List<int> bytes) {
  if (bytes.length < 14) throw FitFormatException('zu kurz');
  final headerSize = bytes[0];
  if (headerSize != 12 && headerSize != 14) {
    throw FitFormatException('Kopfgröße');
  }
  if (String.fromCharCodes(bytes.sublist(8, 12)) != '.FIT') {
    throw FitFormatException('Kennung');
  }
  if (headerSize == 14) {
    final stored = _uint(bytes, 12, 2, false);
    if (stored != 0 && stored != testCrc(bytes.take(12))) {
      throw FitFormatException('Kopf-CRC');
    }
  }
  final dataSize = _uint(bytes, 4, 4, false);
  if (headerSize + dataSize + 2 != bytes.length) {
    throw FitFormatException('Länge');
  }
  final end = headerSize + dataSize;
  if (_uint(bytes, end, 2, false) != testCrc(bytes.take(end))) {
    throw FitFormatException('Datei-CRC');
  }
  if (testCrc(bytes) != 0) throw FitFormatException('Datei-CRC');

  final defs = <int, (int, bool, List<(int, int, int)>)>{};
  final messages = <FitMessage>[];
  var at = headerSize;
  while (at < end) {
    final h = bytes[at++];
    if (h & 0x80 != 0) throw FitFormatException('komprimierter Kopf');
    final local = h & 0x0F;
    if (h & 0x40 != 0) {
      if (h & 0x20 != 0) throw FitFormatException('Entwicklerfelder');
      final big = bytes[at + 1] == 1;
      final global = _uint(bytes, at + 2, 2, big);
      final n = bytes[at + 4];
      at += 5;
      final fields = <(int, int, int)>[];
      for (var i = 0; i < n; i++) {
        fields.add((bytes[at], bytes[at + 1], bytes[at + 2]));
        at += 3;
      }
      defs[local] = (global, big, fields);
    } else {
      final def = defs[local];
      if (def == null) throw FitFormatException('undefinierter Typ');
      final (global, big, fields) = def;
      final values = <int, int>{};
      for (final (number, size, base) in fields) {
        if (at + size > end) throw FitFormatException('abgeschnitten');
        var v = _uint(bytes, at, size, big);
        final signed = base == 0x01 || base == 0x83 || base == 0x85;
        if (signed && v >= 1 << (8 * size - 1)) v -= 1 << (8 * size);
        values[number] = v;
        at += size;
      }
      messages.add((global: global, fields: values));
    }
  }
  if (at != end) throw FitFormatException('Datenende');
  return FitFile(headerSize, bytes[1], _uint(bytes, 2, 2, false), messages);
}
