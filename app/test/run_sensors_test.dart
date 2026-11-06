import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

Finder key(String k) => find.byKey(Key(k));
String text(String k) => (key(k).evaluate().single.widget as Text).data!;

/// Öffnet den Lauf mit den Geräten [ids] schon verbunden (Verbindung aus der
/// Sensorverwaltung); der Puls kommt über den Dienst.
Future<void> openRun(
  Device d,
  WidgetTester tester, {
  List<String> ids = const [],
  String? preferred,
}) async {
  d.runViaSensors = true;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  for (final id in ids) {
    await d.sensors.connect(id, name: 'Gurt $id');
    await tester.pump();
  }
  if (preferred != null) {
    await d.sensors.setPreferred(preferred);
    await tester.pump();
  }
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
}

/// Ein Punkt je Sekunde, geradeaus; bei [bpm] zusätzlich ein Pulswert von [from].
Future<void> walk(
  Device d,
  WidgetTester tester,
  int seconds, {
  int from = 0,
  Map<String, int> bpm = const {},
}) async {
  for (var i = from; i < from + seconds; i++) {
    d.clock.advance(const Duration(seconds: 1));
    d.location.emit(
      LocationSample(
        time: d.clock.now(),
        latitude: 50 + i * 0.000027,
        longitude: 8,
        accuracyMeters: 5,
      ),
    );
    bpm.forEach((id, v) => d.sensorFake.emitReading(id, d.clock.now(), v));
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<StoredRawData> finishAndRead(Device d, WidgetTester tester) async {
  await tester.tap(key('run_finish'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_finish_confirm'));
  await tester.pumpAndSettle();
  final run = (await d.session.runs.list()).single;
  return d.session.rawData.read(run.id);
}

void main() {
  group('Puls im Lauf aus der Sensorverwaltung (WP07 Teil D)', () {
    testWidgets('Lauf ohne Sensor: unverändert, keine Rechteanfrage', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 5);
      expect(text('run_sensor_status'), contains('Kein Sensor verbunden'));
      expect(text('run_hr'), 'nicht verfügbar');
      expect(d.sensorPermissionRequests, 0);
      expect(d.sensorFake.connectedIds, isEmpty);
      final raw = await finishAndRead(d, tester);
      expect(raw.positions, isNotEmpty);
      expect(raw.heartRates, isEmpty);
      await d.stop(tester);
    });

    testWidgets('Puls kommt von der aktiven Quelle, andere werden verworfen', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester, ids: ['h1', 'h2']);
      await walk(d, tester, 3, bpm: {'h1': 150, 'h2': 99});
      expect(text('run_hr'), '150 bpm');
      expect(text('run_sensor_status'), 'Sensor verbunden');
      expect(text('run_sensor_source'), 'Quelle: Gurt h1');
      expect(key('run_sensor_select_h1'), findsNothing);
      final raw = await finishAndRead(d, tester);
      expect(raw.heartRates.map((r) => r.value.source).toSet(), {'h1'});
      expect(raw.heartRates.map((r) => r.value.bpm).toSet(), {150});
      await d.stop(tester);
    });

    testWidgets('Wechsel von Hand unterbricht die Aufzeichnung nicht', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester, ids: ['h1', 'h2']);
      await walk(d, tester, 5, bpm: {'h1': 150, 'h2': 99});
      await tester.tap(key('run_sensor_select_h2'));
      await tester.pump();
      expect(text('run_sensor_source'), 'Quelle: Gurt h2');
      await walk(d, tester, 5, from: 5, bpm: {'h1': 151, 'h2': 140});
      expect(text('run_hr'), '140 bpm');
      expect(text('run_time'), '0:10');
      expect(key('run_sensor_select_h1'), findsOneWidget);
      final raw = await finishAndRead(d, tester);
      expect(raw.positions.length, 10, reason: 'GPS ohne Lücke');
      final sections = heartRateSourceSections(
        raw.heartRates.map((r) => r.value),
      );
      expect(sections.map((s) => s.deviceId), ['h1', 'h2']);
      expect(sections.map((s) => s.count), [5, 5]);
      expect(heartRateSourceDevices(raw.heartRates.map((r) => r.value)), [
        'h1',
        'h2',
      ]);
      expect(d.lastRun!.switches.single.reason, SourceSwitchReason.manual);
      await d.stop(tester);
    });

    testWidgets('Lauf übernimmt die aktive Quelle des Dienstes', (
      tester,
    ) async {
      final d = Device();
      d.runViaSensors = true;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      await d.sensors.connect('h1', name: 'Gurt h1');
      await d.sensors.connect('h2', name: 'Gurt h2');
      await tester.pump();
      // Wahl vor dem Lauf (app-weiter Selector): h2 statt h1.
      expect(d.sensors.selector.select('h2', d.clock.now()), isTrue);
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(d.lastRun!.activeId, 'h2');
      await walk(d, tester, 2, bpm: {'h1': 90, 'h2': 140});
      expect(text('run_hr'), '140 bpm');
      await d.stop(tester);
    });

    testWidgets('Abbruch: Fallback aufs andere Gerät, kein Rückwechsel', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester, ids: ['h1', 'h2'], preferred: 'h1');
      await walk(d, tester, 5, bpm: {'h1': 150, 'h2': 99});
      await d.sensorFake.drop('h1');
      await tester.pump();
      expect(text('run_sensor_source'), 'Quelle: Gurt h2');
      expect(key('run_sensor_loss'), findsOneWidget);
      await walk(d, tester, 5, from: 5, bpm: {'h2': 140});
      // Das bevorzugte Gerät verbindet neu: bleibt bei h2.
      d.clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      expect(d.sensorFake.connectedIds, contains('h1'));
      expect(d.sensors.connectedIds, containsAll(['h1', 'h2']));
      await walk(d, tester, 3, from: 10, bpm: {'h1': 150, 'h2': 141});
      expect(text('run_sensor_source'), 'Quelle: Gurt h2');
      expect(text('run_hr'), '141 bpm');
      expect(key('run_sensor_select_h1'), findsOneWidget);
      final raw = await finishAndRead(d, tester);
      final sections = heartRateSourceSections(
        raw.heartRates.map((r) => r.value),
      );
      expect(sections.map((s) => s.deviceId), ['h1', 'h2']);
      expect(d.lastRun!.switches.single.reason, SourceSwitchReason.lost);
      await d.stop(tester);
    });

    testWidgets(
      'Abbruch ohne Ersatz: Status, keine Nullen, Neuverbinden ist kein Wechsel',
      (tester) async {
        final d = Device();
        await openRun(d, tester, ids: ['h1']);
        await walk(d, tester, 5, bpm: {'h1': 150});
        expect(text('run_hr'), '150 bpm');
        await d.sensorFake.drop('h1');
        await tester.pump();
        expect(
          text('run_sensor_status'),
          contains('Sensor abgebrochen, die App verbindet neu'),
        );
        expect(key('run_sensor_loss'), findsOneWidget);
        // Zeit ohne Quelle (länger als die Einzellücke von 10 s): GPS läuft
        // weiter, der Puls ist nicht verfügbar. Nach 5 s verbindet die App
        // dasselbe Gerät neu, es kommt aber noch kein Wert.
        await walk(d, tester, 12, from: 5);
        expect(d.sensors.connectedIds, {'h1'});
        expect(text('run_hr'), 'nicht verfügbar');
        expect(find.textContaining(RegExp(r'\b0 bpm')), findsNothing);
        await walk(d, tester, 3, from: 17, bpm: {'h1': 152});
        expect(text('run_sensor_status'), 'Sensor verbunden');
        expect(text('run_hr'), '152 bpm');
        final raw = await finishAndRead(d, tester);
        expect(
          raw.positions.length,
          20,
          reason: 'GPS vor, in und nach Abbruch',
        );
        final bpms = raw.heartRates.map((r) => r.value.bpm);
        expect(bpms.where((b) => b <= 0), isEmpty, reason: 'keine Nullwerte');
        expect(bpms.toSet(), {150, 152}, reason: 'Puls vor und nach Abbruch');
        expect(d.lastRun!.switches, isEmpty);
        expect(d.lastRun!.segments.map((s) => s.deviceId), ['h1', 'h1']);
        final sections = heartRateSourceSections(
          raw.heartRates.map((r) => r.value),
        );
        expect(
          sections,
          hasLength(1),
          reason: 'dasselbe Gerät, ein Quellgerät',
        );
        expect(sections.single.deviceId, 'h1');
        await d.stop(tester);
      },
    );

    testWidgets('Lauf-Ende schließt die Quelle, Dienst bleibt nutzbar', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester, ids: ['h1']);
      await walk(d, tester, 3, bpm: {'h1': 150});
      final run = d.lastRun!;
      await finishAndRead(d, tester);
      expect(run.activeId, isNull);
      expect(run.segments.single.end, isNotNull);
      // Nach dem Ende kommen keine Werte mehr in den Lauf.
      d.sensorFake.emitReading('h1', d.clock.now(), 77);
      final run0 = (await d.session.runs.list()).single;
      final raw = await d.session.rawData.read(run0.id);
      expect(raw.heartRates.map((r) => r.value.bpm), isNot(contains(77)));
      // Der app-weite Selector läuft weiter (Sensorverwaltung).
      expect(d.sensors.selector.activeId, 'h1');
      expect(d.sensors.connectedIds, {'h1'});
      await d.stop(tester);
    });

    testWidgets('Sensor im Lauf ohne Name und ohne Adresse in der Anzeige', (
      tester,
    ) async {
      final d = Device();
      d.runViaSensors = true;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      await d.sensors.connect('AA:BB:CC:DD:EE:FF');
      await tester.pump();
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(text('run_sensor_source'), 'Quelle: Pulssensor');
      expect(find.textContaining('AA:BB'), findsNothing);
      await d.stop(tester);
    });
  });
}
