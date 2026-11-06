import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/run/run_ports.dart';
import 'package:running_app/features/sensors/run_heart_rate.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';
import 'package:running_app/features/storage/storage_start.dart';

/// "Gerät" für App-Tests: Speicher und Schlüsselablage bleiben über mehrere
/// App-Starts erhalten, wie auf dem Telefon.
class Device {
  final FakeStorage storage = FakeStorage();
  final FakeKeyStore keyStore = FakeKeyStore();
  final FakeClock clock = FakeClock(DateTime.utc(2026, 6, 1));
  final FakePermissionStatus permissions = FakePermissionStatus();
  final FakeLocationAccess locationAccess = FakeLocationAccess();
  final FakeLocationSource location = FakeLocationSource();
  final FakeHeartRateSensor heartRate = FakeHeartRateSensor();

  /// Pulssensor der Sensorverwaltung (getrennt von [heartRate] des Laufs).
  final FakeHeartRateSensor sensorFake = FakeHeartRateSensor();

  /// Wie oft die Bluetooth-Rechte angefragt wurden; [sensorPermissionError]
  /// simuliert eine Ablehnung.
  int sensorPermissionRequests = 0;
  Object? sensorPermissionError;
  Duration reconnectDelay = const Duration(seconds: 5);
  late SensorManager sensors;

  /// Läufe beziehen den Puls aus der Sensorverwaltung ([sensors]) statt aus
  /// [heartRate]; [lastRun] ist die Pulsquelle des jüngsten Laufs.
  bool runViaSensors = false;
  RunHeartRate? lastRun;

  /// Ersatz für [locationAccess] (etwa mit Fehlern); sonst [locationAccess].
  LocationAccessPort? locationAccessOverride;
  late StorageStartController controller;

  /// Ersatz für [storage] (etwa ein Speicher mit Lesefehlern); sonst [storage].
  Storage? storageOverride;

  StorageSession get session => (controller.state as StorageReady).session;

  /// Startet die App mit der Gerätesprache [locale] (neuer Prozess auf
  /// demselben Speicher).
  Future<void> start(WidgetTester tester, Locale locale) async {
    // Hoher Bildschirm, damit das ganze Formular ohne Scrollen sichtbar ist.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    controller = StorageStartController(
      keyStore: keyStore,
      generateKey: () => Uint8List.fromList(List.filled(32, 7)),
      wire: () async => StorageWiring(
        storage: storageOverride ?? storage,
        files: FakeDatabaseFiles(),
      ),
    );
    sensors = SensorManager(
      sensor: sensorFake,
      clock: clock,
      reconnectDelay: reconnectDelay,
      requestPermissions: () async {
        sensorPermissionRequests++;
        if (sensorPermissionError != null) throw sensorPermissionError!;
      },
    );
    await tester.pumpWidget(
      RunningApp(
        dependencies: AppDependencies(
          storageStart: controller,
          sensors: sensors,
          clock: clock,
          permissions: permissions,
          runPorts: RunPorts(
            access: locationAccessOverride ?? locationAccess,
            location: location,
            heartRate: runViaSensors
                ? null
                : () => heartRate
                      .connect('hr1')
                      .where((e) => e is HeartRateReading)
                      .cast<HeartRateReading>(),
            heartRateRun: runViaSensors
                ? () => lastRun = sensors.beginRun()
                : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Beendet die App (Sitzung zu), damit ein zweiter Start möglich ist.
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Der Prozess endet: Verbindungen der Sensorverwaltung fallen mit.
    sensors.dispose();
    await session.close();
  }

  /// Überspringt die Ersteinrichtung.
  Future<void> skipSetup(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('setup_skip')));
    await tester.pumpAndSettle();
  }
}
