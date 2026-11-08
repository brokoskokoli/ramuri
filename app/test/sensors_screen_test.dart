import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

Future<void> openSensors(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('overview_sensors')));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('App-Start und Öffnen der Verwaltung fragen nichts ab', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    expect(d.sensorPermissionRequests, 0);
    await openSensors(tester);
    expect(find.text('Pulssensoren'), findsWidgets);
    expect(find.text('Noch kein Gerät gespeichert.'), findsOneWidget);
    expect(d.sensorPermissionRequests, 0);
    expect(d.sensorFake.connectedIds, isEmpty);
    await d.stop(tester);
  });

  testWidgets('suchen, verbinden, Puls, Batterie nur wenn gemeldet, trennen', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openSensors(tester);
    await tapKey(tester, 'sensors_scan');
    expect(d.sensorPermissionRequests, 1);
    d.sensorFake.discover(const HeartRateDevice(id: 'h1', name: 'Gurt Eins'));
    await tester.pumpAndSettle();
    expect(find.text('Gurt Eins'), findsOneWidget);

    await tapKey(tester, 'sensor_connect_h1');
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.byKey(const Key('sensor_bpm_h1')), findsOneWidget);
    expect(find.text('Noch kein Wert'), findsOneWidget);
    d.sensorFake.emitReading('h1', d.clock.now(), 143);
    await tester.pump();
    await tester.pump();
    expect(find.text('143 bpm'), findsOneWidget);
    // Keine Batterie gemeldet: keine Anzeige, kein erfundener Wert.
    expect(find.byKey(const Key('sensor_battery_h1')), findsNothing);
    expect(find.textContaining('Batterie'), findsNothing);
    d.sensorFake.emitBattery('h1', 55);
    await tester.pump();
    await tester.pump();
    expect(find.text('Batterie: 55 %'), findsOneWidget);

    await tapKey(tester, 'sensor_disconnect_h1');
    expect(find.text('Nicht verbunden'), findsOneWidget);
    expect(find.text('143 bpm'), findsNothing);
    expect(find.textContaining('Batterie'), findsNothing);
    expect(d.sensorFake.connectedIds, isEmpty);
    await d.stop(tester);
  });

  testWidgets('bekannte Geräte und Bevorzugung bleiben nach Neustart', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openSensors(tester);
    await tapKey(tester, 'sensors_scan');
    d.sensorFake
      ..discover(const HeartRateDevice(id: 'h1', name: 'Gurt Eins'))
      ..discover(const HeartRateDevice(id: 'h2', name: 'Gurt Zwei'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'sensor_connect_h1');
    await tapKey(tester, 'sensor_connect_h2');
    await tapKey(tester, 'sensor_prefer_h2');
    expect(find.text('Bevorzugt'), findsOneWidget);
    await d.stop(tester);

    // Neuer App-Start auf demselben Speicher.
    await d.start(tester, const Locale('de'));
    await openSensors(tester);
    expect(find.text('Gurt Eins'), findsOneWidget);
    expect(find.text('Gurt Zwei'), findsOneWidget);
    expect(find.text('Bevorzugt'), findsOneWidget);
    expect(find.text('Nicht verbunden'), findsNWidgets(2));
    expect(d.sensorPermissionRequests, 1, reason: 'nur die erste Einrichtung');
    expect(d.sensorFake.connectedIds, isEmpty);
    await d.stop(tester);
  });

  testWidgets('Rechte verweigert: klarer Hinweis, kein Absturz', (
    tester,
  ) async {
    final d = Device()..sensorPermissionError = StateError('denied');
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openSensors(tester);
    await tapKey(tester, 'sensors_scan');
    expect(find.byKey(const Key('sensors_problem')), findsOneWidget);
    expect(find.textContaining('Bluetooth-Berechtigung'), findsOneWidget);
    expect(find.text('Geräte suchen'), findsOneWidget, reason: 'Suche aus');
    expect(tester.takeException(), isNull);
    await d.stop(tester);
  });

  testWidgets('englische Texte', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    await openSensors(tester);
    expect(find.text('Heart rate sensors'), findsWidgets);
    expect(find.text('Search for devices'), findsOneWidget);
    expect(find.text('No device saved yet.'), findsOneWidget);
    await d.stop(tester);
  });
}
