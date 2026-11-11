import 'dart:typed_data';

/// Strenger JSON-Leser für eine Zeile des Archivs (RFC 8259).
///
/// `dart:convert` genügt nicht: Es meldet doppelte Schlüssel nicht, liest zu
/// große Ganzzahlen stillschweigend als `double` und lässt keine Wahl
/// zwischen Ganzzahl und Gleitkommazahl. Der Vertrag verlangt alle drei
/// (`docs/contracts/archive.md`, Abschnitt 4).
///
/// Ergebnis: `Map<String, Object?>` (Einfügereihenfolge), `List<Object?>`,
/// `String`, `int` (nur Schreibweise ohne Bruch und Exponent, signed 64 Bit),
/// `double` (endlich), `bool`, `null`. Jede Verletzung wirft
/// [FormatException] ohne den Text zu nennen.
Object? parseArchiveJson(String text) {
  final p = _Parser(text);
  p._ws();
  final v = p._value(0);
  p._ws();
  if (p._i != text.length) throw _bad;
  return v;
}

const FormatException _bad = FormatException('JSON ungültig');

/// Tiefe, ab der verschachteltes JSON abgelehnt wird (Archivzeilen sind flach).
const int _maxDepth = 16;

class _Parser {
  _Parser(this._s);

  final String _s;
  int _i = 0;

  void _ws() {
    while (_i < _s.length) {
      final c = _s.codeUnitAt(_i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _i++;
      } else {
        break;
      }
    }
  }

  int _peek() => _i < _s.length ? _s.codeUnitAt(_i) : -1;

  Object? _value(int depth) {
    if (depth > _maxDepth) throw _bad;
    final c = _peek();
    switch (c) {
      case 0x7B: // {
        return _object(depth);
      case 0x5B: // [
        return _array(depth);
      case 0x22: // "
        return _string();
      case 0x74:
        return _literal('true', true);
      case 0x66:
        return _literal('false', false);
      case 0x6E:
        return _literal('null', null);
      default:
        if (c == 0x2D || (c >= 0x30 && c <= 0x39)) return _number();
        throw _bad;
    }
  }

  Object? _literal(String word, Object? value) {
    if (!_s.startsWith(word, _i)) throw _bad;
    _i += word.length;
    return value;
  }

  Map<String, Object?> _object(int depth) {
    _i++;
    final map = <String, Object?>{};
    _ws();
    if (_peek() == 0x7D) {
      _i++;
      return map;
    }
    while (true) {
      _ws();
      if (_peek() != 0x22) throw _bad;
      final key = _string();
      if (map.containsKey(key)) throw _bad;
      _ws();
      if (_peek() != 0x3A) throw _bad;
      _i++;
      _ws();
      map[key] = _value(depth + 1);
      _ws();
      final c = _peek();
      _i++;
      if (c == 0x7D) return map;
      if (c != 0x2C) throw _bad;
    }
  }

  List<Object?> _array(int depth) {
    _i++;
    final list = <Object?>[];
    _ws();
    if (_peek() == 0x5D) {
      _i++;
      return list;
    }
    while (true) {
      _ws();
      list.add(_value(depth + 1));
      _ws();
      final c = _peek();
      _i++;
      if (c == 0x5D) return list;
      if (c != 0x2C) throw _bad;
    }
  }

  String _string() {
    _i++;
    final out = StringBuffer();
    var start = _i;
    while (true) {
      if (_i >= _s.length) throw _bad;
      final c = _s.codeUnitAt(_i);
      if (c == 0x22) {
        out.write(_s.substring(start, _i));
        _i++;
        return out.toString();
      }
      if (c < 0x20) throw _bad;
      if (c != 0x5C) {
        _i++;
        continue;
      }
      out.write(_s.substring(start, _i));
      _i++;
      if (_i >= _s.length) throw _bad;
      final e = _s.codeUnitAt(_i++);
      switch (e) {
        case 0x22:
          out.writeCharCode(0x22);
        case 0x5C:
          out.writeCharCode(0x5C);
        case 0x2F:
          out.writeCharCode(0x2F);
        case 0x62:
          out.writeCharCode(0x08);
        case 0x66:
          out.writeCharCode(0x0C);
        case 0x6E:
          out.writeCharCode(0x0A);
        case 0x72:
          out.writeCharCode(0x0D);
        case 0x74:
          out.writeCharCode(0x09);
        case 0x75:
          if (_i + 4 > _s.length) throw _bad;
          var u = 0;
          for (var k = 0; k < 4; k++) {
            final d = _hex(_s.codeUnitAt(_i + k));
            if (d < 0) throw _bad;
            u = u * 16 + d;
          }
          _i += 4;
          out.writeCharCode(u);
        default:
          throw _bad;
      }
      start = _i;
    }
  }

  static int _hex(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }

  static final RegExp _numberPattern = RegExp(
    r'-?(?:0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?',
  );

  Object _number() {
    final m = _numberPattern.matchAsPrefix(_s, _i);
    if (m == null) throw _bad;
    _i = m.end;
    final text = m[0]!;
    if (m[1] == null && m[2] == null) {
      // Passt nicht in 64 Bit: kein Ersatz durch double.
      return int.tryParse(text) ?? (throw _bad);
    }
    final d = double.parse(text);
    if (!d.isFinite) throw _bad;
    return d;
  }
}

/// Ob [s] gültiges Unicode ist (keine einzelnen Surrogate).
bool isValidArchiveText(String s) {
  final u = s.codeUnits;
  for (var i = 0; i < u.length; i++) {
    final c = u[i];
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 < u.length && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF) {
        i++;
        continue;
      }
      return false;
    }
    if (c >= 0xDC00 && c <= 0xDFFF) return false;
  }
  return true;
}

/// BLOB-Wert als kleingeschriebener Hex-Text (zwei Zeichen je Byte).
String encodeArchiveBlob(Uint8List bytes) {
  final b = StringBuffer();
  for (final x in bytes) {
    b.write(x.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// Gegenstück zu [encodeArchiveBlob]; `null` bei ungerader Länge oder anderen
/// Zeichen als `0-9a-f`.
Uint8List? decodeArchiveBlob(String s) {
  if (s.length.isOdd) return null;
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final hi = _hexDigit(s.codeUnitAt(2 * i));
    final lo = _hexDigit(s.codeUnitAt(2 * i + 1));
    if (hi < 0 || lo < 0) return null;
    out[i] = hi << 4 | lo;
  }
  return out;
}

int _hexDigit(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x61 && c <= 0x66) return c - 0x57;
  return -1;
}
