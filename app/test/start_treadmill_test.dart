import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/live_run_view.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/run/run_ports.dart';
import 'package:running_app/features/run/treadmill_units.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

Future<void> openStart(Device d, WidgetTester tester) async {
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
}

Future<void> chooseBelt(WidgetTester tester) async {
  await tester.tap(key('treadmill_mode_belt'));
  await tester.pumpAndSettle();
}

Future<void> enterSpeed(WidgetTester tester, String v) async {
  await tester.enterText(key('treadmill_start_speed'), v);
  await tester.pumpAndSettle();
}

bool goEnabled(WidgetTester tester) =>
    tester.widget<RamuriStartButton>(key('run_start_ready')).onPressed != null;

String text(String k) => (key(k).evaluate().single.widget as Text).data!;

RunController liveController(WidgetTester tester) =>
    tester.widget<LiveRunView>(find.byType(LiveRunView)).controller;

void main() {
  group('Lauf vorbereiten im Laufbandmodus (FR-0196, K57)', () {
    testWidgets('die Bandwahl wird gemerkt, GPS und Autopause entfallen', (
      tester,
    ) async {
      final d = Device();
      await openStart(d, tester);
      expect(key('start_autopause'), findsOneWidget);
      expect(key('treadmill_start_speed'), findsNothing);
      await chooseBelt(tester);
      expect(key('treadmill_start_speed'), findsOneWidget);
      expect(key('start_autopause'), findsNothing);
      expect(key('start_gps_searching'), findsNothing);
      expect(key('start_gps_good'), findsNothing);
      // Zurück und neu öffnen: die Wahl gilt wieder.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(key('treadmill_start_speed'), findsOneWidget);
      expect(key('start_autopause'), findsNothing);
    });

    testWidgets('Los ist ohne gültige Startgeschwindigkeit gesperrt', (
      tester,
    ) async {
      final d = Device();
      await openStart(d, tester);
      await chooseBelt(tester);
      expect(goEnabled(tester), isFalse);
      for (final bad in ['0,9', '25,1', 'abc', '0']) {
        await enterSpeed(tester, bad);
        expect(goEnabled(tester), isFalse, reason: bad);
      }
      expect(find.textContaining('Gib eine Geschwindigkeit'), findsOneWidget);
      // Steigung außerhalb oder nicht im 0,5-Schritt sperrt ebenfalls.
      await enterSpeed(tester, '10');
      expect(goEnabled(tester), isTrue);
      for (final bad in ['15,5', '1,3', '-1']) {
        await tester.enterText(key('treadmill_start_incline'), bad);
        await tester.pumpAndSettle();
        expect(goEnabled(tester), isFalse, reason: bad);
      }
      await tester.enterText(key('treadmill_start_incline'), '');
      await tester.pumpAndSettle();
      expect(goEnabled(tester), isTrue);
      // Grenzen gelten.
      for (final ok in ['1', '25', '12,3']) {
        await enterSpeed(tester, ok);
        expect(goEnabled(tester), isTrue, reason: ok);
      }
    });

    testWidgets('kein Standortdialog und keine Standortsperre im Bandmodus', (
      tester,
    ) async {
      final d = Device()
        ..recordingService = FakeRecordingServicePort()
        ..requestActivityRecognition = () async {};
      d.locationAccess
        ..current = LocationAccess.denied
        ..gps = false;
      await openStart(d, tester);
      expect(key('run_block_permissionDenied'), findsOneWidget);
      await chooseBelt(tester);
      expect(key('run_block_permissionDenied'), findsNothing);
      await enterSpeed(tester, '10,5');
      await tester.enterText(key('treadmill_start_incline'), '1,5');
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveRunView), findsOneWidget);
      expect(d.locationAccess.requestCount, 0);
      expect(d.location.hasListeners, isFalse);
      final snap = liveController(tester).snapshot;
      expect(snap.mode, RunMode.treadmill);
      expect(snap.beltSpeedMetersPerSecond, closeTo(10.5 / 3.6, 1e-9));
      expect(snap.inclinePercent, 1.5);
      expect(d.recordingService!.startModes, [RecordingServiceMode.treadmill]);
    });

    testWidgets(
      'fehlt ACTIVITY_RECOGNITION: Grund, kein Lauf; Erneut startet',
      (tester) async {
        final service = FakeRecordingServicePort()
          ..activityRecognitionGranted = false;
        final d = Device()..recordingService = service;
        await openStart(d, tester);
        await chooseBelt(tester);
        await enterSpeed(tester, '9');
        await tester.tap(key('run_start_ready'));
        await tester.pumpAndSettle();
        expect(key('treadmill_denied'), findsOneWidget);
        expect(find.byType(LiveRunView), findsNothing);
        expect(await d.session.runs.unfinished(), isEmpty);
        service.activityRecognitionGranted = true;
        await tester.tap(key('treadmill_denied_retry'));
        await tester.pumpAndSettle();
        expect(find.byType(LiveRunView), findsOneWidget);
      },
    );

    testWidgets('Knöpfe ändern Geschwindigkeit und Steigung, keine Karte', (
      tester,
    ) async {
      final d = Device();
      await openStart(d, tester);
      await chooseBelt(tester);
      await enterSpeed(tester, '10');
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(key('run_pages'), findsNothing);
      expect(key('run_tab_1'), findsNothing);
      expect(key('live_chip_gps'), findsNothing);
      expect(text('treadmill_speed'), '10,0 km/h');
      expect(text('treadmill_incline'), '–');
      final c = liveController(tester);

      await tester.tap(key('treadmill_speed_up'));
      await tester.pumpAndSettle();
      expect(text('treadmill_speed'), '10,1 km/h');
      expect(c.snapshot.beltSpeedMetersPerSecond, closeTo(10.1 / 3.6, 1e-9));
      await tester.tap(key('treadmill_speed_down'));
      await tester.tap(key('treadmill_speed_down'));
      await tester.pumpAndSettle();
      expect(text('treadmill_speed'), '9,9 km/h');

      await tester.tap(key('treadmill_incline_up'));
      await tester.pumpAndSettle();
      expect(c.snapshot.inclinePercent, 0);
      await tester.tap(key('treadmill_incline_up'));
      await tester.pumpAndSettle();
      expect(text('treadmill_incline'), '0,5 %');
      expect(c.snapshot.inclinePercent, 0.5);

      // Stillstand: 0 km/h ist erlaubt; von 0 geht es auf 1 km/h.
      await tester.tap(key('treadmill_stop_belt'));
      await tester.pumpAndSettle();
      expect(c.snapshot.beltSpeedMetersPerSecond, 0);
      expect(text('treadmill_speed'), '0,0 km/h');
      await tester.tap(key('treadmill_speed_up'));
      await tester.pumpAndSettle();
      expect(text('treadmill_speed'), '1,0 km/h');
    });

    testWidgets('GPS-Weg unverändert: Standortsperre, Karte, Autopause', (
      tester,
    ) async {
      final d = Device();
      await openStart(d, tester);
      expect(key('start_autopause'), findsOneWidget);
      expect(key('treadmill_start_speed'), findsNothing);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveRunView), findsOneWidget);
      expect(key('run_pages'), findsOneWidget);
      expect(key('treadmill_speed'), findsNothing);
      expect(d.location.hasListeners, isTrue);
    });
  });

  group('TreadmillUnits (PAR-209, PAR-210)', () {
    test('Meilen werden umgerechnet, Grenzen und Schritte', () {
      const mi = DistanceUnit.miles;
      expect(TreadmillUnits.minTenths(mi), 7); // 0,6 mph wären unter 1 km/h
      expect(TreadmillUnits.maxTenths(mi), 155);
      expect(
        TreadmillUnits.parseSpeed(mi, '6,2'),
        closeTo(6.2 * 1609.344 / 3600, 1e-9),
      );
      expect(TreadmillUnits.parseSpeed(mi, '0.6'), isNull);
      expect(TreadmillUnits.parseSpeed(mi, '15.6'), isNull);
      expect(
        TreadmillUnits.stepSpeed(mi, null, 1),
        closeTo(0.7 * 1609.344 / 3600, 1e-9),
      );
      expect(
        TreadmillUnits.stepSpeed(
          mi,
          TreadmillUnits.mpsFromDisplay(mi, 0.7),
          -1,
        ),
        0,
      );
    });

    test('Steigung: unbekannt, Schritte, Grenzen', () {
      expect(TreadmillUnits.stepIncline(null, -1), isNull);
      expect(TreadmillUnits.stepIncline(null, 1), 0);
      expect(TreadmillUnits.stepIncline(0, -1), 0);
      expect(TreadmillUnits.stepIncline(15, 1), 15);
      expect(TreadmillUnits.parseIncline('7,5'), (true, 7.5));
      expect(TreadmillUnits.parseIncline(''), (true, null));
      expect(TreadmillUnits.parseIncline('7,3').$1, isFalse);
    });
  });
}
