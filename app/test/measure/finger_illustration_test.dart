import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/resting_widgets.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

// Das Erklärbild zeichnet Finger und Handy über seine Fläche (350 x 178)
// hinaus (der Finger beginnt bei y = -40, das Handy endet bei y = 214); wie im
// Design (SVG) muss alles an der Bildfläche abgeschnitten werden. Ein Überlauf
// im Layout ist das nicht (die Fläche bleibt klein), deshalb fängt ihn kein
// RenderFlex-Test; geprüft wird hier, was tatsächlich gemalt wird.

const _bg = Color(0xFFFF00FF);

Future<void> _check(
  WidgetTester tester, {
  required Size physical,
  required double dpr,
  required double width,
  required bool dark,
}) async {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? RamuriTheme.dark : RamuriTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Kleine Schrift, damit die Beschriftungen in ihre Felder passen: Die
      // Testschrift (Ahem) ist breiter als die echte, „Kamera“ liefe über sein
      // Feld hinaus, und der Stack schnitte dann die ganze Zeichnung von selbst
      // ab (Überlauf der Kinder). Auf dem Gerät passt der Text, nichts schneidet.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(0.5)),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: _bg,
            child: Padding(
              padding: const EdgeInsets.all(70),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: const FingerIllustration(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final box = tester.getRect(find.byType(FingerIllustration));
  final origin = tester.getTopLeft(find.byKey(key));
  final area = tester.getRect(find.byKey(key));
  final rect = box.shift(-origin);
  final image = await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (img.width, img.height, data!);
  });
  final (w, h, data) = image!;
  expect(w, area.width.ceil());
  var outside = 0;
  var inside = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final isBg =
          data.getUint8(i) == 0xFF &&
          data.getUint8(i + 1) == 0 &&
          data.getUint8(i + 2) == 0xFF;
      final near =
          x >= rect.left - 1 &&
          x <= rect.right + 1 &&
          y >= rect.top - 1 &&
          y <= rect.bottom + 1;
      if (near) {
        if (!isBg) inside++;
      } else if (!isBg && x < w - 1 && y < h - 1) {
        outside++;
      }
    }
  }
  expect(inside, greaterThan(1000), reason: 'Zeichnung fehlt');
  expect(
    outside,
    0,
    reason: '$outside Bildpunkte der Zeichnung liegen außerhalb ihrer Fläche',
  );
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dunkel' : 'hell';
    testWidgets('Zeichnung bleibt in ihrer Fläche, 1080x2400 bei 2,75, $mode', (
      tester,
    ) async {
      // Karte auf dem Pixel-Gerät: gut 320 dp breit, Zeichnung wird verkleinert.
      await _check(
        tester,
        physical: const Size(1080, 2400),
        dpr: 2.75,
        width: 321,
        dark: dark,
      );
    });

    testWidgets('Zeichnung bleibt in ihrer Fläche, 390x844 bei 1,0, $mode', (
      tester,
    ) async {
      await _check(
        tester,
        physical: const Size(390, 844),
        dpr: 1,
        width: 294,
        dark: dark,
      );
    });

    testWidgets('Zeichnung bleibt in ihrer Fläche, volle Breite 350, $mode', (
      tester,
    ) async {
      await _check(
        tester,
        physical: const Size(800, 900),
        dpr: 1,
        width: 350,
        dark: dark,
      );
    });
  }
}
