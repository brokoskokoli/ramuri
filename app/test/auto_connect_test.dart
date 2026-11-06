import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

Finder key(String k) => find.byKey(Key(k));

/// Zwei bekannte Geräte (h2 bevorzugt), beide getrennt; Neustart wie ein
/// frischer Prozess auf demselben Speicher.
Future<Device> knownAndDisconnected(
  WidgetTester tester, {
  bool bluetoothGranted = true,
}) async {
  final d = Device();
  d.runViaSensors = true;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await d.sensors.connect('h1', name: 'Gurt h1');
  await d.sensors.connect('h2', name: 'Gurt h2');
  await d.sensors.setPreferred('h2');
  await tester.pump();
  d.sensors.disconnect('h1');
  d.sensors.disconnect('h2');
  await tester.pump();
  expect(d.sensorFake.connectedIds, isEmpty);
  await d.stop(tester);
  d.permissions.states[AppPermission.bluetooth] = bluetoothGranted
      ? PermissionState.granted
      : PermissionState.denied;
  await d.start(tester, const Locale('de'));
  return d;
}

void main() {
  group('Pulssensoren verbinden beim Öffnen des Lauf-Bildschirms (Teil E)', () {
    testWidgets('App-Start verbindet nichts, auch mit Rechten', (tester) async {
      final d = await knownAndDisconnected(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(d.sensorFake.connectedIds, isEmpty);
      expect(d.sensors.connectedIds, isEmpty);
      await d.stop(tester);
    });

    testWidgets('mit Rechten: bekannte Geräte verbunden, bevorzugtes Quelle', (
      tester,
    ) async {
      // Lauf wartet (Standort fehlt): kein Laufstart, der Selector bleibt offen.
      final d = await knownAndDisconnected(tester);
      d.locationAccess.current = LocationAccess.denied;
      final asked = d.sensorPermissionRequests;
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(d.sensorFake.connectedIds, {'h1', 'h2'});
      // h1 verband zuerst, das bevorzugte h2 übernimmt trotzdem.
      expect(d.sensors.selector.activeId, 'h2');
      expect(d.sensorPermissionRequests, asked, reason: 'keine Rechteabfrage');
      expect(find.byType(AlertDialog), findsNothing);
      await d.stop(tester);
    });

    testWidgets('Laufstart danach: Lauf übernimmt das bevorzugte Gerät', (
      tester,
    ) async {
      final d = await knownAndDisconnected(tester);
      d.locationAccess.current = LocationAccess.denied;
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      d.locationAccess
        ..current = LocationAccess.denied
        ..onRequest = LocationAccess.precise;
      await tester.tap(key('run_block_ask'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(d.lastRun!.activeId, 'h2');
      await d.stop(tester);
    });

    testWidgets('ab Laufstart kein Rückwechsel zum bevorzugten Gerät', (
      tester,
    ) async {
      final d = await knownAndDisconnected(tester);
      // Der Lauf startet sofort; h1 verbindet zuerst, h2 (bevorzugt) danach.
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(d.sensorFake.connectedIds, {'h1', 'h2'});
      expect(d.lastRun!.activeId, 'h1');
      await d.stop(tester);
    });

    testWidgets('ohne Rechte: kein connect, keine Rechteabfrage, kein Dialog', (
      tester,
    ) async {
      final d = await knownAndDisconnected(tester, bluetoothGranted: false);
      final asked = d.sensorPermissionRequests;
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(d.sensorFake.connectedIds, isEmpty);
      expect(d.sensorPermissionRequests, asked);
      expect(find.byType(AlertDialog), findsNothing);
      expect(d.sensors.problem, isNull);
      expect(find.textContaining('Kein Sensor verbunden'), findsOneWidget);
      await d.stop(tester);
    });

    testWidgets('Bluetooth aus: kein Absturz, kein Hinweis, kein connect', (
      tester,
    ) async {
      final d = Device()..bluetoothOn = false;
      d.runViaSensors = true;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      d.bluetoothOn = true;
      await d.sensors.connect('h1', name: 'Gurt h1');
      d.sensors.disconnect('h1');
      await tester.pump();
      d.permissions.states[AppPermission.bluetooth] = PermissionState.granted;
      d.bluetoothOn = false;
      final asked = d.sensorPermissionRequests;
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(d.sensorFake.connectedIds, isEmpty);
      expect(d.sensorPermissionRequests, asked);
      expect(d.sensors.problem, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      await d.stop(tester);
    });
  });
}
