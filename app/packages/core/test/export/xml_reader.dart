/// Minimaler, strenger XML-Leser nur für die Rücklese-Tests des Exports.
/// Kennt Elemente, Attribute, Text, Kommentare, die XML-Deklaration und die
/// fünf vordefinierten sowie numerische Entitäten. Wirft [FormatException]
/// bei unpassenden Tags, unbekannten Entitäten und rohen `<`/`&`.
library;

class XmlElement {
  XmlElement(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;
  final List<XmlElement> children = [];
  final StringBuffer _text = StringBuffer();

  String get text => _text.toString();

  /// Alle Nachfahren mit diesem Namen, in Dokumentreihenfolge.
  Iterable<XmlElement> all(String name) sync* {
    for (final c in children) {
      if (c.name == name) yield c;
      yield* c.all(name);
    }
  }

  Iterable<XmlElement> named(String name) =>
      children.where((c) => c.name == name);

  XmlElement? child(String name) {
    for (final c in children) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Namen aller Nachfahren.
  Set<String> get descendantNames => {
    for (final c in children) ...{c.name, ...c.descendantNames},
  };
}

XmlElement parseXml(String s) {
  var i = 0;
  XmlElement? root;
  final stack = <XmlElement>[];

  Never fail(String why) => throw FormatException(why, s, i);

  String decode(String raw) {
    final b = StringBuffer();
    var j = 0;
    while (j < raw.length) {
      final c = raw[j];
      if (c == '<') fail('rohes <');
      if (c != '&') {
        b.write(c);
        j++;
        continue;
      }
      final end = raw.indexOf(';', j);
      if (end < 0) fail('rohes &');
      final name = raw.substring(j + 1, end);
      switch (name) {
        case 'amp':
          b.write('&');
        case 'lt':
          b.write('<');
        case 'gt':
          b.write('>');
        case 'quot':
          b.write('"');
        case 'apos':
          b.write("'");
        default:
          if (name.startsWith('#x')) {
            b.writeCharCode(int.parse(name.substring(2), radix: 16));
          } else if (name.startsWith('#')) {
            b.writeCharCode(int.parse(name.substring(1)));
          } else {
            fail('unbekannte Entität $name');
          }
      }
      j = end + 1;
    }
    return b.toString();
  }

  while (i < s.length) {
    if (s.startsWith('<?', i)) {
      i = s.indexOf('?>', i) + 2;
    } else if (s.startsWith('<!--', i)) {
      i = s.indexOf('-->', i) + 3;
    } else if (s.startsWith('</', i)) {
      final end = s.indexOf('>', i);
      final name = s.substring(i + 2, end).trim();
      if (stack.isEmpty || stack.last.name != name) fail('unpassend </$name>');
      stack.removeLast();
      i = end + 1;
    } else if (s[i] == '<') {
      final end = s.indexOf('>', i);
      var body = s.substring(i + 1, end);
      final selfClosing = body.endsWith('/');
      if (selfClosing) body = body.substring(0, body.length - 1);
      final m = RegExp(r'^([\w:.-]+)').firstMatch(body) ?? fail('Tagname');
      final attrs = <String, String>{};
      for (final a in RegExp(
        r'([\w:.-]+)="([^"]*)"',
      ).allMatches(body.substring(m.end))) {
        if (attrs.containsKey(a[1])) fail('doppeltes Attribut');
        attrs[a[1]!] = decode(a[2]!);
      }
      final e = XmlElement(m[1]!, attrs);
      if (stack.isEmpty) {
        if (root != null) fail('zweites Wurzelelement');
        root = e;
      } else {
        stack.last.children.add(e);
      }
      if (!selfClosing) stack.add(e);
      i = end + 1;
    } else {
      var end = s.indexOf('<', i);
      if (end < 0) end = s.length;
      final text = decode(s.substring(i, end));
      if (stack.isEmpty) {
        if (text.trim().isNotEmpty) fail('Text außerhalb der Wurzel');
      } else {
        stack.last._text.write(text);
      }
      i = end;
    }
  }
  if (stack.isNotEmpty || root == null) fail('unvollständig');
  return root;
}
