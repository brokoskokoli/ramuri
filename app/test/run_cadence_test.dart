import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_controller.dart';

import 'app_harness.dart';

Finder key(String k) => find.byKey(Key(k));
String text(String k) => (key(k).evaluate().single.widget as Text).data!;

String cadenceText(WidgetTester tester) => text('run_cadence');

Future<void> openRun(Device d, WidgetTester tester) async {
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await tester.tap(key('home_start_run'));
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
          ..requestActivityRecognition = () async {
            asked++;
            throw StateError('abgelehnt');
          };
        await openRun(d, tester);
        expect(asked, 1);
        expect(key('run_pause'), findsOneWidget);
      },
    );
  });

  group('Controller', () {
    test('Schrittsensor wird nach dem Ende abbestellt', () async {
      final clock = FakeClock(DateTime.utc(2030, 3, 1, 10));
      final session = await FakeStorage().open(Uint8List(32));
      final cadence = _CountingCadence();
      final c = RunController(
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
  });

  test('Quelltext: Berechtigung im Manifest, Typ health fehlt', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    expect(manifest, contains('android.permission.ACTIVITY_RECOGNITION"'));
    expect(manifest, isNot(contains('health')));
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
