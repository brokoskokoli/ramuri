/// Hilfen für die XML-Formate des Exports (GPX, TCX).
library;

/// Text oder Attributwert für XML 1.0: Sonderzeichen escaped, in XML 1.0
/// unzulässige Zeichen (Steuerzeichen, einzelne Surrogate, U+FFFE/U+FFFF)
/// entfernt.
String xmlText(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    switch (r) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      case 0x27:
        b.write('&apos;');
      default:
        if (_allowed(r)) b.writeCharCode(r);
    }
  }
  return b.toString();
}

bool _allowed(int r) =>
    r == 0x9 ||
    r == 0xA ||
    r == 0xD ||
    (r >= 0x20 && r <= 0xD7FF) ||
    (r >= 0xE000 && r <= 0xFFFD) ||
    (r >= 0x10000 && r <= 0x10FFFF);

/// UTC-Zeit als ISO 8601 mit Millisekunden (`2030-01-01T08:00:00.000Z`);
/// Mikrosekunden werden abgeschnitten.
String xmlTime(DateTime t) {
  final u = t.toUtc();
  String p(int v, int n) => v.toString().padLeft(n, '0');
  return '${p(u.year, 4)}-${p(u.month, 2)}-${p(u.day, 2)}'
      'T${p(u.hour, 2)}:${p(u.minute, 2)}:${p(u.second, 2)}'
      '.${p(u.millisecond, 3)}Z';
}

/// Endliche Zahl als `xsd:decimal` ohne Exponent, mit so vielen Stellen, dass
/// sie beim Einlesen denselben `double` ergibt.
String xmlDecimal(double v) {
  if (!v.isFinite) throw ArgumentError.value(v, 'v', 'nicht endlich');
  final s = v.toString();
  final e = s.indexOf('e');
  if (e < 0) return s;
  final negative = s.startsWith('-');
  final mantissa = s.substring(negative ? 1 : 0, e);
  final exponent = int.parse(s.substring(e + 1));
  final dot = mantissa.indexOf('.');
  final digits = mantissa.replaceAll('.', '');
  final point = (dot < 0 ? mantissa.length : dot) + exponent;
  String out;
  if (point <= 0) {
    out = '0.${'0' * -point}$digits';
  } else if (point >= digits.length) {
    out = '$digits${'0' * (point - digits.length)}';
  } else {
    out = '${digits.substring(0, point)}.${digits.substring(point)}';
  }
  out = out.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (out.contains('.')) out = out.replaceFirst(RegExp(r'\.?0+$'), '');
  return negative ? '-$out' : out;
}
