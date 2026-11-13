// Gemeinsame Hilfen der Lauf-Integrationstests (Emulator, Test-Sensor).
// Der Test-Sensor (DebugTestSensor) ersetzt nur den Pulsgurt; Rechte, Speicher
// und Aufzeichnung sind echt. Das GPS liefert tool/ci_e2e.sh (adb emu geo fix).
// Ausgabe: Zeilen "E2E_<zeit> ...", nur Marken und Zaehler, keine Messwerte.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/features/storage/storage_start.dart';
import 'package:running_app/system_clock.dart';

/// Kanarienwert (0x1357): nur vom Test gesendetes RR-Paket, so ist belegt, dass
/// genau dieses Paket gespeichert wurde.
const canaryRr = 4951;

void log(String s) {
  // ignore: avoid_print
  print('E2E_${DateTime.now().toIso8601String().substring(11, 23)} $s');
}

class World {
  World(this.deps, this.sensor);
  final AppDependencies deps;
  final DebugTestSensor sensor;
}

World buildWorld() {
  final sensor = DebugTestSensor(const SystemClock());
  return World(AppDependencies.create(heartRateSensor: sensor), sensor);
}

/// Pumpt in echter Zeit (Sensor, GPS und Speicher laufen ausserhalb der
/// Testuhr).
Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Wartet bis [cond] gilt und scheitert sonst mit [what] (kein stilles Weiter).
Future<void> waitFor(
  WidgetTester t,
  bool Function() cond,
  String what, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      fail('nach ${timeout.inSeconds} s nicht erreicht: $what');
    }
    await pumpFor(t, const Duration(milliseconds: 200));
  }
}

bool has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

String txt(String key) {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) return '<fehlt>';
  final w = f.evaluate().first.widget;
  return w is Text ? (w.data ?? '<rich>') : w.runtimeType.toString();
}

/// Taste in einem Dialog: kein ensureVisible (es scrollt sonst die Seite dahinter).
Future<void> tapDialog(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await pumpFor(t, const Duration(milliseconds: 300));
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  expect(f, findsWidgets, reason: 'Taste $key fehlt');
  await t.ensureVisible(f);
  await t.tap(f);
  await pumpFor(t, const Duration(milliseconds: 300));
}

Future<void> startApp(WidgetTester t, World w) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(RunningApp(dependencies: w.deps));
  await pumpFor(t, const Duration(seconds: 3));
}

/// Offene Speichersitzung der App (wartet, bis der Speicher bereit ist).
Future<StorageSession> session(WidgetTester t, World w) async {
  await waitFor(
    t,
    () => w.deps.storageStart.state is StorageReady,
    'Speicher bereit',
  );
  return (w.deps.storageStart.state as StorageReady).session;
}

/// Ersteinrichtung ueberspringen, falls sie erscheint.
Future<void> setupIfShown(WidgetTester t) async {
  await waitFor(
    t,
    () => has('welcome_start') || has('setup_skip') || has('home_start_run'),
    'Willkommen, Einrichtung oder Heute',
  );
  if (has('welcome_start')) {
    await tapKey(t, 'welcome_start');
  }
  await waitFor(
    t,
    () => has('setup_skip') || has('home_start_run'),
    'Einrichtung oder Heute',
  );
  if (has('setup_skip')) {
    await tapKey(t, 'setup_skip');
  }
  await waitFor(t, () => has('home_start_run'), 'Heute');
}

Future<void> back(WidgetTester t) async {
  await t.tap(find.byType(BackButton).last);
  await pumpFor(t, const Duration(seconds: 1));
}

/// Verbindet Fake-Geraete ueber die Sensorseite.
Future<void> connect(WidgetTester t, List<String> ids, String prefer) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_sensors');
  await tapKey(t, 'sensors_scan');
  await waitFor(t, () => has('sensor_${ids.first}'), 'Fake-Geraet gefunden');
  for (final id in ids) {
    await tapKey(t, 'sensor_connect_$id');
    await waitFor(t, () => has('sensor_bpm_$id'), 'Pulswert von $id');
  }
  if (ids.length > 1) await tapKey(t, 'sensor_prefer_$prefer');
  await back(t);
  await back(t);
}

Future<void> startRun(WidgetTester t) async {
  await tapKey(t, 'home_start_run');
  await waitFor(t, () => has('run_start_ready'), 'Start-Seite bereit');
  await waitFor(t, () => has('start_gps_good'), 'GPS gut (Emulator-Fix)');
  await tapKey(t, 'run_start_ready');
  await waitFor(t, () => has('run_time'), 'Laufseite');
}

Future<void> _noConsent(WidgetTester t) async {
  if (has('map_consent_dialog')) {
    await tapDialog(t, 'map_consent_not_now');
  }
}

Future<void> finishRun(WidgetTester t) async {
  await _noConsent(t);
  await tapKey(t, 'run_pause');
  await _noConsent(t);
  await tapKey(t, 'run_finish');
  await _noConsent(t);
  await tapDialog(t, 'run_finish_confirm');
  await waitFor(t, () => has('run_done_status'), 'Laufende angezeigt');
}

/// Zaehler eines gespeicherten Laufs (keine Werte).
class RunCounts {
  RunCounts(
    this.state,
    this.positions,
    this.heartRates,
    this.rrPackets,
    this.canary,
  );
  final RunState state;
  final int positions;
  final int heartRates;
  final int rrPackets;
  final int canary;
}

/// Zaehler aller Laeufe, neueste zuerst nach Id.
Future<List<RunCounts>> countRuns(WidgetTester t, World w) async {
  final s = await session(t, w);
  return (await t.runAsync(() async {
    final out = <RunCounts>[];
    final runs = [...await s.runs.list()]..sort((a, b) => b.id.compareTo(a.id));
    for (final r in runs) {
      final raw = await s.rawData.read(r.id);
      var canary = 0;
      for (final p in raw.rrPackets) {
        canary += p.value.intervals.where((v) => v == canaryRr).length;
      }
      out.add(
        RunCounts(
          r.state,
          raw.positions.length,
          raw.heartRates.length,
          raw.rrPackets.length,
          canary,
        ),
      );
    }
    return out;
  }))!;
}
