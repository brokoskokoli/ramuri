import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

void main() {
  testWidgets('Startbildschirm auf Deutsch', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    expect(find.byKey(const Key('home_screen')), findsOneWidget);
  });

  testWidgets('Startbildschirm auf Englisch', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    expect(find.text('Free run'), findsOneWidget);
    expect(find.text('Frei laufen'), findsNothing);
  });

  // NFR-0006, OQ-0067: jede andere Gerätesprache zeigt Englisch.
  for (final locale in const [
    Locale('fr'),
    Locale('es', 'ES'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ]) {
    testWidgets('Gerätesprache $locale zeigt Englisch', (tester) async {
      final d = Device();
      await d.start(tester, locale);
      // Ersteinrichtung auf Englisch
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Überspringen'), findsNothing);
      await d.skipSetup(tester);
      expect(find.text('Free run'), findsOneWidget);
      expect(find.text('Frei laufen'), findsNothing);
    });
  }

  testWidgets('Deutsch mit Region bleibt Deutsch', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('de', 'AT'));
    await d.skipSetup(tester);
    expect(find.byKey(const Key('home_screen')), findsOneWidget);
  });
}
