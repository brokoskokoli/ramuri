import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/run/run_ports.dart';

import 'app_harness.dart';

/// Text eines Werts der Lauf-Seite; Zahl und Einheit stehen in Teilen, der
/// Wortverbinder (U+2060) ist unsichtbar.
String text(String k) {
  final w = key(k).evaluate().single.widget as Text;
  return (w.data ?? w.textSpan!.toPlainText()).replaceAll('\u2060', '');
}

String cadenceText(WidgetTester tester) => text('run_cadence');

Future<void> openRun(Device d, WidgetTester tester) async {
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
}

/// Ein Punkt je Sekunde, damit der Lauf Daten bekommt.
Future<void> walk(Device d, WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    d.clock.advance(const Duration(seconds: 1));
    d.location.emit(
      LocationSample(
        time: d.clock.now(),
        latitude: 50 + i * 0.000027,
        longitude: 8,
        accuracyMeters: 5,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  group('Schrittfrequenz in der Anzeige (FR-0202)', () {
    testWidgets('Fake-Sensor liefert Werte in die Anzeige', (tester) async {
      final cadence = FakeCadenceSensor();
      final d = Device()..cadence = cadence;
      await openRun(d, tester);
      // Verfügbar, aber noch kein Schritt: kein Wert, nicht „nicht verfügbar“.
      expect(cadenceText(tester), 'noch keine Daten');
      cadence.emit(d.clock.now(), 171.6);
      await tester.pump(); // Zustellung des Ereignisses
      await tester.pump(); // Bild mit dem neuen Wert
      expect(cadenceText(tester), '172 spm');
    });

    testWidgets('Stillstand: Wert verfällt nach dem Fenster', (tester) async {
      final cadence = FakeCadenceSensor();
      final d = Device()..cadence = cadence;
      await openRun(d, tester);
      cadence.emit(d.clock.now(), 160);
      await tester.pump();
      await tester.pump();
      expect(cadenceText(tester), '160 spm');
      await walk(d, tester, 12);
      expect(cadenceText(tester), 'noch keine Daten');
    });

    testWidgets('Uhr im Lauf zurückgestellt: Wert verfällt nach dem Fenster', (
      tester,
    ) async {
      final cadence = FakeCadenceSensor();
      final d = Device()..cadence = cadence;
      await openRun(d, tester);
      cadence.emit(d.clock.now(), 160);
      await tester.pump();
      await tester.pump();
      expect(cadenceText(tester), '160 spm');
      d.clock.set(d.clock.now().subtract(const Duration(hours: 1)));
      for (var i = 0; i < 12; i++) {
        d.clock.advance(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(cadenceText(tester), 'noch keine Daten');
    });

    testWidgets(
      'laufende Werte bleiben frisch (Verfall zählt ab dem letzten)',
      (tester) async {
        final cadence = FakeCadenceSensor();
        final d = Device()..cadence = cadence;
        await openRun(d, tester);
        for (var i = 0; i < 4; i++) {
          await walk(d, tester, 5);
          cadence.emit(d.clock.now(), 150.0 + i);
          await tester.pump();
          await tester.pump();
        }
        // 20 s seit dem ersten Wert, aber der letzte ist frisch.
        expect(cadenceText(tester), '153 spm');
      },
    );

    testWidgets('nach Fehler im Strom: spätere Werte kommen nicht mehr an', (
      tester,
    ) async {
      final cadence = FakeCadenceSensor();
      final d = Device()..cadence = cadence;
      await openRun(d, tester);
      cadence.emit(d.clock.now(), 160);
      await tester.pump();
      cadence.fail();
      await tester.pump();
      await tester.pump();
      expect(cadenceText(tester), 'nicht verfügbar');
      cadence.emit(d.clock.now(), 170);
      await tester.pump();
      await tester.pump();
      expect(cadenceText(tester), 'nicht verfügbar');
    });

    for (final ends in <String, Future<void> Function(FakeCadenceSensor)>{
      'Fehler': (c) async => c.fail(),
      'Ende': (c) => c.end(),
    }.entries) {
      testWidgets('Schrittstrom endet (${ends.key}): nicht verfügbar', (
        tester,
      ) async {
        final cadence = FakeCadenceSensor();
        final d = Device()..cadence = cadence;
        await openRun(d, tester);
        cadence.emit(d.clock.now(), 160);
        await tester.pump();
        await tester.pump();
        expect(cadenceText(tester), '160 spm');
        await ends.value(cadence);
        await tester.pump();
        await tester.pump();
        expect(cadenceText(tester), 'nicht verfügbar');
        expect(key('run_pause'), findsOneWidget);
      });
    }

    testWidgets('ohne Berechtigung: nicht verfügbar, Lauf normal', (
      tester,
    ) async {
      final cadence = FakeCadenceSensor(CadenceAvailability.permissionDenied);
      final d = Device()..cadence = cadence;
      await openRun(d, tester);
      expect(cadenceText(tester), 'nicht verfügbar');
      await walk(d, tester, 5);
      expect(cadenceText(tester), 'nicht verfügbar');
      expect(key('run_pause'), findsOneWidget);
      expect(text('run_distance'), isNot('noch keine Daten'));
    });

    testWidgets('ohne Sensor und ohne Anbindung: nicht verfügbar', (
      tester,
    ) async {
      final d = Device()
        ..cadence = FakeCadenceSensor(CadenceAvailability.noSensor);
      await openRun(d, tester);
      expect(cadenceText(tester), 'nicht verfügbar');
      await tester.pumpWidget(const SizedBox());
      final d2 = Device();
      await openRun(d2, tester);
      expect(cadenceText(tester), 'nicht verfügbar');
    });

    testWidgets(
      'Berechtigung wird vor dem Start gefragt, Fehler blockiert nicht',
      (tester) async {
        var asked = 0;
        final d = Device()
          ..requestActivityRecognition = (_) async {
            asked++;
            throw StateError('abgelehnt');
          };
        await openRun(d, tester);
        expect(asked, 1);
        expect(key('run_pause'), findsOneWidget);
      },
    );
  });

  group('Schritte gespeichert (FR-0202, raw_steps)', () {
    final t0 = DateTime.utc(2030, 3, 1, 10);
    Future<void> settle() => Future<void>.delayed(Duration.zero);
    List<(Duration, int)> rows(StoredRawData raw) => [
      for (final r in raw.steps) (r.value.time.difference(t0), r.value.count),
    ];
    LocationSample fix(FakeClock clock, int i) => LocationSample(
      time: clock.now(),
      latitude: 50 + i * 0.000027,
      longitude: 8,
      accuracyMeters: 5,
    );
    RunController controller(
      FakeClock clock,
      StorageSession session,
      FakeLocationSource location,
      FakeCadenceSensor cadence, {
      int? resume,
      RunMode mode = RunMode.gps,
    }) => RunController(
      algorithms: AlgorithmRegistry.standard(),
      clock: clock,
      storage: session,
      location: location,
      cadence: cadence,
      service: FakeRecordingServicePort(),
      mode: mode,
      startBeltSpeedMetersPerSecond: mode == RunMode.treadmill ? 3 : null,
      resumeRunId: resume,
      tickEvery: const Duration(hours: 1),
    );

    test('Lauf mit Fake-Schrittsensor: Zähler des Laufs gespeichert', () async {
      final clock = FakeClock(t0);
      final session = await FakeStorage().open(Uint8List(32));
      final location = FakeLocationSource();
      final cadence = FakeCadenceSensor();
      final c = controller(clock, session, location, cadence);
      addTearDown(c.dispose);
      await c.start();
      await settle();
      clock.advance(const Duration(seconds: 1));
      cadence.emit(clock.now(), 170, null, 3);
      location.emit(fix(clock, 1)); // schreibt den wartenden Zähler mit
      await settle();
      clock.advance(const Duration(seconds: 1));
      cadence.emit(clock.now(), 172, null, 2);
      await settle();
      await c.finish();
      final raw = await session.rawData.read(c.runId!);
      expect(rows(raw), [
        (const Duration(seconds: 1), 3),
        (const Duration(seconds: 2), 5),
      ]);
      expect(raw.steps.first.value.source, 'phone');
    });

    test('Laufband: Zähler wird ebenso gespeichert', () async {
      final clock = FakeClock(t0);
      final session = await FakeStorage().open(Uint8List(32));
      final cadence = FakeCadenceSensor();
      final c = controller(
        clock,
        session,
        FakeLocationSource(),
        cadence,
        mode: RunMode.treadmill,
      );
      addTearDown(c.dispose);
      await c.start();
      await settle();
      clock.advance(const Duration(seconds: 2));
      cadence.emit(clock.now(), 168, null, 4);
      await settle();
      await c.finish();
      final raw = await session.rawData.read(c.runId!);
      expect((await session.runs.get(c.runId!))!.mode, RunMode.treadmill);
      expect(rows(raw), [(const Duration(seconds: 2), 4)]);
    });

    test('Wiederanlauf (FR-0193): neuer Sensorstrom, Zähler läuft ohne '
        'Doppelzählung weiter', () async {
      final clock = FakeClock(t0);
      final session = await FakeStorage().open(Uint8List(32));
      final location = FakeLocationSource();
      final cadence = FakeCadenceSensor();
      final first = controller(clock, session, location, cadence);
      await first.start();
      await settle();
      clock.advance(const Duration(seconds: 1));
      cadence.emit(clock.now(), 170, null, 4);
      location.emit(fix(clock, 1));
      await settle();
      final id = first.runId!;
      first.dispose(); // Prozess weg, kein Ende
      await settle();
      expect((await session.runs.get(id))!.state, RunState.active);

      clock.advance(const Duration(minutes: 1));
      final again = controller(clock, session, location, cadence, resume: id);
      addTearDown(again.dispose);
      await again.start();
      await settle();
      expect(again.runId, id);
      clock.advance(const Duration(seconds: 1));
      cadence.emit(clock.now(), 171, null, 2); // neuer Strom zählt ab 0
      await settle();
      await again.finish();
      expect(rows(await session.rawData.read(id)), [
        (const Duration(seconds: 1), 4),
        (const Duration(seconds: 62), 6),
      ]);
    });
  });

  group('Controller', () {
    test('Schrittsensor wird nach dem Ende abbestellt', () async {
      final clock = FakeClock(DateTime.utc(2030, 3, 1, 10));
      final session = await FakeStorage().open(Uint8List(32));
      final cadence = _CountingCadence();
      final c = RunController(
        algorithms: AlgorithmRegistry.standard(),
        clock: clock,
        storage: session,
        location: FakeLocationSource(),
        cadence: cadence,
        tickEvery: const Duration(hours: 1),
      );
      await c.start();
      await Future<void>.delayed(Duration.zero);
      expect(cadence.listening, isTrue);
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(cadence.listening, isFalse);
    });

    test(
      'Fehler im Strom: Abo wird beendet, spätere Werte zählen nicht',
      () async {
        final clock = FakeClock(DateTime.utc(2030, 3, 1, 10));
        final session = await FakeStorage().open(Uint8List(32));
        final cadence = FakeCadenceSensor();
        final c = RunController(
          algorithms: AlgorithmRegistry.standard(),
          clock: clock,
          storage: session,
          location: FakeLocationSource(),
          cadence: cadence,
          tickEvery: const Duration(hours: 1),
        );
        addTearDown(c.dispose);
        await c.start();
        await Future<void>.delayed(Duration.zero);
        cadence.emit(clock.now(), 160);
        await Future<void>.delayed(Duration.zero);
        expect(c.cadenceStepsPerMinute, 160);
        cadence.fail();
        await Future<void>.delayed(Duration.zero);
        expect(c.cadenceAvailability, CadenceAvailability.noSensor);
        cadence.emit(clock.now(), 170);
        await Future<void>.delayed(Duration.zero);
        expect(c.cadenceStepsPerMinute, isNull);
      },
    );
  });

  test('Quelltext: Berechtigung im Manifest, Typ health nur mit FOREGROUND_SERVICE_HEALTH (ADR-0005 Nachtrag WP25)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    expect(manifest, contains('android.permission.ACTIVITY_RECOGNITION"'));
    // health kommt nur als Diensttyp des Aufzeichnungsdienstes und mit dem zugehörigen Recht vor (Laufbandmodus, K57).
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE_HEALTH"'));
    expect(manifest, contains('|health"'));
  });
}

class _CountingCadence implements CadenceSensor {
  bool listening = false;
  @override
  Future<CadenceAvailability> availability() async =>
      CadenceAvailability.available;
  @override
  Stream<CadenceReading> readings() => Stream<CadenceReading>.multi((c) {
    listening = true;
    c.onCancel = () => listening = false;
  });
}
