import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('parseArchiveJson', () {
    test('liest Objekte, Zahlen, Strings und Literale', () {
      expect(
        parseArchiveJson(
          ' {"a":1,"b":-2,"c":1.5,"d":1e2,"e":"x","f":null,"g":true,'
          '"h":[1,{"i":false}]}\r',
        ),
        {
          'a': 1,
          'b': -2,
          'c': 1.5,
          'd': 100.0,
          'e': 'x',
          'f': null,
          'g': true,
          'h': [
            1,
            {'i': false},
          ],
        },
      );
    });

    test('Ganzzahl und Gleitkommazahl bleiben unterscheidbar', () {
      expect(parseArchiveJson('1'), isA<int>());
      expect(parseArchiveJson('1.0'), isA<double>());
      expect(parseArchiveJson('1e0'), isA<double>());
      expect(parseArchiveJson('-0'), 0);
    });

    test('64-Bit-Grenzen: verlustfrei, darüber Fehler statt double', () {
      expect(parseArchiveJson('9223372036854775807'), 9223372036854775807);
      expect(parseArchiveJson('-9223372036854775808'), -9223372036854775808);
      expect(
        () => parseArchiveJson('9223372036854775808'),
        throwsFormatException,
      );
      expect(
        () => parseArchiveJson('-9223372036854775809'),
        throwsFormatException,
      );
    });

    test('nicht endliche Zahl ist ein Fehler', () {
      expect(() => parseArchiveJson('1E400'), throwsFormatException);
      expect(() => parseArchiveJson('-1e999'), throwsFormatException);
    });

    test('doppelter Schlüssel ist ein Fehler', () {
      expect(() => parseArchiveJson('{"a":1,"a":2}'), throwsFormatException);
      expect(
        () => parseArchiveJson('{"x":{"a":1,"a":1}}'),
        throwsFormatException,
      );
    });

    test(
      'Escapes inklusive Surrogatpaar; einzelnes Surrogat bleibt sichtbar',
      () {
        expect(parseArchiveJson(r'"🏃 ä\n\"\\\/"'), '\u{1F3C3} ä\n"\\/');
        final lone = parseArchiveJson(r'"\ud800"')! as String;
        expect(isValidArchiveText(lone), isFalse);
        expect(isValidArchiveText('\u{1F3C3}'), isTrue);
      },
    );

    for (final bad in [
      '',
      '{',
      '{"a":1,}',
      '[1,]',
      '{"a" 1}',
      "{'a':1}",
      '01',
      '1.',
      '.5',
      '+1',
      '--1',
      '1e',
      'NaN',
      'Infinity',
      'tru',
      '"a',
      '"\t"',
      r'"\x"',
      r'"\u12"',
      '{"a":1} x',
      '{"a":1}{"b":2}',
      '[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]',
      '﻿{}',
    ]) {
      test('lehnt ab: ${bad.replaceAll('\n', r'\n')}', () {
        expect(() => parseArchiveJson(bad), throwsFormatException);
      });
    }
  });
}
