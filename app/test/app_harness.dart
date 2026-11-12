import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/archive/archive_wiring.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/run/run_ports.dart';
import 'package:running_app/features/sensors/run_heart_rate.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';
import 'package:running_app/features/storage/storage_start.dart';

export 'helpers/widget_helpers.dart';

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

  /// Bluetooth-Schalter für [SensorManager.bluetoothAvailable]; `null`: unbekannt.
  bool? bluetoothOn;
  Duration reconnectDelay = const Duration(seconds: 5);
  late SensorManager sensors;

  /// Dienst der Aufzeichnung (WP08); `null` wie ohne Dienst.
  FakeRecordingServicePort? recordingService;

  /// Abfrage von POST_NOTIFICATIONS vor dem Laufstart (WP08); `null` wie ohne Plattform.
  Future<void> Function()? requestNotifications;

  /// Schrittsensor des Telefons (WP08 C, FR-0202); `null` wie ohne Anbindung.
  CadenceSensor? cadence;

  /// Abfrage von ACTIVITY_RECOGNITION vor dem Laufstart; `null` wie ohne Plattform.
  Future<void> Function(bool treadmill)? requestActivityRecognition;

  /// Wo die Wiedergabe rechnet. Ein Isolate läuft nicht in der Test-Uhr
  /// (pumpAndSettle), darum standardmäßig inline; Tests setzen einen Fake.
  Offload offload = inlineOffload;

  /// Teilen und Speichern von Exportdateien (WP11).
  final FakeFileHandoff fileHandoff = FakeFileHandoff();

  /// Archiv-Export (WP12); `null`: nicht verdrahtet.
  ArchiveExportFactory? archiveExport;

  /// Archiv-Import (WP12); `null`: nicht verdrahtet.
  ArchiveRestoreFactory? archiveRestore;

  /// Kartenanbieter (WP13); `null`: nicht verdrahtet.
  MapServices? map;

  /// Erinnerungen (FR-0174); `null`: nicht verdrahtet.
  ReminderScheduler? reminders;

  /// Läufe beziehen den Puls aus der Sensorverwaltung ([sensors]) statt aus
  /// [heartRate] (Gerät 'hr1', ohne Verwaltung); [lastRun] ist die Pulsquelle
  /// des jüngsten Laufs.
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
  ///
  /// Steht der Willkommensbildschirm (FR-0207) davor, bestätigt [start] ihn,
  /// außer mit `welcome: true`; so beginnen die übrigen Tests bei der
  /// Einrichtung.
  Future<void> start(
    WidgetTester tester,
    Locale locale, {
    bool welcome = false,
    bool settle = true,
  }) async {
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
      bluetoothGranted: () async =>
          permissions.states[AppPermission.bluetooth] ==
          PermissionState.granted,
      bluetoothAvailable: bluetoothOn == null ? null : () async => bluetoothOn!,
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
          offload: offload,
          fileHandoff: fileHandoff,
          archiveExport: archiveExport,
          archiveRestore: archiveRestore,
          map: map,
          reminders: reminders,
          permissions: permissions,
          runPorts: RunPorts(
            access: locationAccessOverride ?? locationAccess,
            location: location,
            heartRateRun: () {
              final run = sensors.beginRun();
              if (!runViaSensors) {
                // Einfacher Puls ohne Sensorverwaltung: das Gerät 'hr1' des
                // Fakes speist die Pulsquelle dieses Laufs direkt; verbunden
                // gilt es erst mit dem ersten Wert.
                var connected = false;
                final sub = heartRate.connect('hr1').listen((e) {
                  if (e is! HeartRateReading) return;
                  if (!connected) run.handle(HeartRateConnected(e.deviceId));
                  connected = true;
                  run.handle(e);
                });
                addTearDown(sub.cancel);
              }
              return lastRun = run;
            },
            connectSensors: sensors.connectKnown,
            recordingService: recordingService,
            requestNotifications: requestNotifications,
            cadence: cadence,
            requestActivityRecognition: requestActivityRecognition,
          ),
        ),
      ),
    );
    if (!settle) return;
    await tester.pumpAndSettle();
    if (!welcome) await confirmWelcome(tester);
  }

  /// „Los geht's“ auf dem Willkommensbildschirm, falls er steht.
  Future<void> confirmWelcome(WidgetTester tester) async {
    final button = find.byKey(const Key('welcome_start'));
    if (button.evaluate().isEmpty) return;
    await tester.tap(button);
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

/// Öffnet die Übersicht über das Profil-Symbol auf Heute. Steht sie schon
/// oben (die Einträge sind sichtbar), tut sie nichts.
Future<void> openOverview(WidgetTester tester) async {
  final icon = find.byKey(const Key('home_overview'));
  if (icon.evaluate().isEmpty) return;
  await tester.tap(icon);
  await tester.pumpAndSettle();
}

/// Lädt die echte Zahlenschrift (Sora), sonst misst der Test mit der breiten
/// Testschrift.
Future<void> loadSora(WidgetTester tester) => tester.runAsync(() async {
  final loader = FontLoader('Sora');
  for (final f in ['Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Sora-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
});

/// Lädt die echte Schrift (Manrope), damit Tests Umbrüche so messen wie auf
/// dem Gerät; die Testschrift ist deutlich breiter.
Future<void> loadManrope(WidgetTester tester) => tester.runAsync(() async {
  final loader = FontLoader('Manrope');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Manrope-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
});
