import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ui.dart';

/// Lädt die gebündelten Schnitte unter einem eigenen Familiennamen, damit der
/// Test nicht von der Fontliste der Testumgebung abhängt.
Future<void> loadFamily(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File('assets/fonts/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

double widthOf(
  String family,
  FontWeight weight, [
  String text = 'Laufen 0123456789 mmm',
]) {
  final p = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: family, fontSize: 40, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return p.width;
}

void main() {
  testWidgets(
    'Manrope 400 und 800 laufen verschieden breit, Reihenfolge stimmt',
    (tester) async {
      await loadFamily('ManropeT', [
        'Manrope-Regular.ttf',
        'Manrope-Medium.ttf',
        'Manrope-SemiBold.ttf',
        'Manrope-Bold.ttf',
        'Manrope-ExtraBold.ttf',
      ]);
      final w = {
        for (final weight in [
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800,
        ])
          weight: widthOf('ManropeT', weight),
      };
      final values = w.values.toList();
      for (var i = 1; i < values.length; i++) {
        expect(
          values[i],
          greaterThan(values[i - 1]),
          reason: 'Breiten steigen mit dem Gewicht: $w',
        );
      }
    },
  );

  testWidgets('Sora 500, 600, 700 laufen verschieden breit', (tester) async {
    await loadFamily('SoraT', [
      'Sora-Medium.ttf',
      'Sora-SemiBold.ttf',
      'Sora-Bold.ttf',
    ]);
    final a = widthOf('SoraT', FontWeight.w500);
    final b = widthOf('SoraT', FontWeight.w600);
    final c = widthOf('SoraT', FontWeight.w700);
    expect(b, greaterThan(a));
    expect(c, greaterThan(b));
  });

  test('pubspec bindet jede Schriftdatei mit Gewicht ein', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final (file, weight) in [
      ('Sora-Medium', 500),
      ('Sora-SemiBold', 600),
      ('Sora-Bold', 700),
      ('Manrope-Regular', 400),
      ('Manrope-Medium', 500),
      ('Manrope-SemiBold', 600),
      ('Manrope-Bold', 700),
      ('Manrope-ExtraBold', 800),
    ]) {
      expect(
        RegExp('asset: assets/fonts/$file.ttf\\s+weight: $weight')
            .hasMatch(pubspec),
        isTrue,
        reason: file,
      );
      expect(File('assets/fonts/$file.ttf').existsSync(), isTrue, reason: file);
    }
    expect(pubspec, isNot(contains('google_fonts')));
  });

  test('Theme nutzt Sora für Zahlen und Manrope für Text', () {
    final t = RamuriTheme.light;
    expect(t.textTheme.displayMedium!.fontFamily, 'Sora');
    expect(t.textTheme.bodyMedium!.fontFamily, 'Manrope');
    expect(t.extension<RamuriType>()!.valueSmall.fontFeatures, isNotEmpty);
  });

  group('Lizenzen', () {
    test('beide OFL-Texte stehen in der LicenseRegistry', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerFontLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      for (final name in ['Sora', 'Manrope']) {
        final own = entries.where((e) => e.packages.contains(name)).toList();
        expect(own, hasLength(1), reason: name);
        final text = own.single.paragraphs.map((p) => p.text).join('\n');
        expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
        expect(text, contains('The $name Project Authors'));
        expect(text, contains('Copyright 2019'));
      }
    });
  });
}
