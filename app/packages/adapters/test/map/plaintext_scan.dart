import 'dart:io';
import 'dart:typed_data';

/// Ein Treffer des Klartext-Scans (Name der Signatur, Offset).
class PlainHit {
  PlainHit(this.name, this.offset);
  final String name;
  final int offset;
  @override
  String toString() => '$name@$offset';
}

/// Gzip mit Anhang hinter dem Strom (Positivkontrolle: Der Strom endet nicht am Ende der Eingabe).
List<int> gzipWithTail(String text) => [
  ...gzip.encode(text.codeUnits),
  ...List.filled(64, 0x41),
];

const List<int> _gz = [0x1f, 0x8b, 0x08];

int _find(Uint8List b, List<int> needle, int from) {
  outer:
  for (var i = from; i + needle.length <= b.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (b[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Signaturen aus R008 Hinweis 2 und 10. Kurze Signaturen kommen in verschlüsselten Daten zufällig vor (3 Byte etwa
/// einmal je 16 MiB); darum sind PNG, JPEG und WebP hier länger als ihre Kurzform: PNG mit ganzer Kennung, JPEG
/// `FF D8 FF` plus JFIF- oder Exif-Kopf, WebP `RIFF`, vier Byte, `WEBP`.
final Map<String, List<int>> _fixed = {
  'pbf': 'transportation'.codeUnits,
  'pbf2': 'landcover'.codeUnits,
  'png': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  'jpeg': [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46],
  'sqlite': 'SQLite format 3'.codeUnits,
};

/// Alle Treffer. gzip zählt nur, wenn ein Streaming-Inflate ab der Signatur Ausgabe liefert (Anhang erlaubt, kein
/// `gzip.decode`: Das scheitert am Anhang).
List<PlainHit> plaintextHits(Uint8List b) {
  final hits = <PlainHit>[];
  _fixed.forEach((name, sig) {
    final i = _find(b, sig, 0);
    if (i >= 0) hits.add(PlainHit(name.startsWith('pbf') ? 'pbf' : name, i));
  });
  // JPEG mit Exif-Kopf: FF D8 FF E1 xx xx "Exif".
  for (
    var i = _find(b, const [0xff, 0xd8, 0xff, 0xe1], 0);
    i >= 0;
    i = _find(b, const [0xff, 0xd8, 0xff, 0xe1], i + 1)
  ) {
    if (i + 10 <= b.length && b[i + 6] == 0x45 && b[i + 7] == 0x78) {
      hits.add(PlainHit('jpeg', i));
      break;
    }
  }
  // WebP: RIFF ???? WEBP.
  for (
    var i = _find(b, 'RIFF'.codeUnits, 0);
    i >= 0;
    i = _find(b, 'RIFF'.codeUnits, i + 1)
  ) {
    if (i + 12 <= b.length &&
        b[i + 8] == 0x57 &&
        b[i + 9] == 0x45 &&
        b[i + 10] == 0x42 &&
        b[i + 11] == 0x50) {
      hits.add(PlainHit('webp', i));
      break;
    }
  }
  for (var i = _find(b, _gz, 0); i >= 0; i = _find(b, _gz, i + 1)) {
    var out = 0;
    try {
      final conv = gzip.decoder.startChunkedConversion(
        _CountingSink((n) => out += n),
      );
      final end = i + (1 << 20) > b.length ? b.length : i + (1 << 20);
      conv.add(Uint8List.sublistView(b, i, end));
    } catch (_) {
      // kein gültiger Strom ab hier
    }
    if (out > 0) {
      hits.add(PlainHit('gzip', i));
      break;
    }
  }
  return hits;
}

class _CountingSink implements Sink<List<int>> {
  _CountingSink(this.onBytes);
  final void Function(int) onBytes;
  @override
  void add(List<int> data) => onBytes(data.length);
  @override
  void close() {}
}
