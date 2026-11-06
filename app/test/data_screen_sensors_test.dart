import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

void main() {
  testWidgets('Daten: "Alles löschen" trennt die Pulssensoren', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await d.sensors.connect('h1', name: 'Gurt h1');
    await tester.pump();
    expect(d.sensorFake.connectedIds, {'h1'});

    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alles löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Alles löschen'));
    await tester.pumpAndSettle();

    expect(d.sensorFake.connectedIds, isEmpty);
    expect(d.sensors.knownEntries, isEmpty);
    await d.stop(tester);
  });
}
