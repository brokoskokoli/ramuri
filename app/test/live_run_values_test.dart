import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/live_run_values.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

// Werte-Seite des Laufs nach Live.dc.html (WP16 B): Pflichtanzeigen laufend und
// pausiert, Beenden nur pausiert, Einheiten, Überlauf.

Finder key(String k) => find.byKey(Key(k));

String text(String k) {
  final w = key(k).evaluate().single.widget as Text;
  return (w.data ?? w.textSpan!.toPlainText())
      .replaceAll('⁠', '')
      .replaceAll('\u00A0', ' ');
}

Future<void> openRun(
  Device d,
  WidgetTester tester, {
  bool viaSensors = false,
  List<String> ids = const [],
  bool profile = true,
  Future<void> Function()? before,
}) async {
  d.runViaSensors = viaSensors;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await before?.call();
  if (profile) {
    await d.session.profile.save(
      const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    );
  }
  for (final id in ids) {
    await d.sensors.connect(id, name: 'Gurt $id');
    await tester.pump();
  }
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
}

Future<void> walk(
  Device d,
  WidgetTester tester,
  int seconds, {
  int from = 0,
  bool altitude = false,
}) async {
  for (var i = from; i < from + seconds; i++) {
    d.clock.advance(const Duration(seconds: 1));
    d.location.emit(
      LocationSample(
        time: d.clock.now(),
        latitude: 50 + i * 0.000027,
        longitude: 8,
        accuracyMeters: 5,
        altitudeMeters: altitude ? 100 + i * 0.5 : null,
        verticalAccuracyMeters: altitude ? 3 : null,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Alle Pflichtanzeigen der Werte-Seite (FR-0026, FR-0027, FR-0202, FR-0030,
/// FR-0194) sind da.
/// Ohne Puls steht die Zone nur als graue Zonenanzeige da („nicht verfügbar“
/// steht schon am Pulswert); mit Puls gehört der Zonentext dazu.
void expectRequired() {
  final zoneText = text('run_hr') != 'nicht verfügbar';
  for (final k in [
    'run_time',
    'run_distance',
    'run_pace',
    'run_avg_pace',
    'run_moving_time',
    'run_hr',
    if (zoneText) 'run_zone',
    'run_ascent',
    'run_cadence',
    'run_laps',
    'live_chip_gps',
    'live_chip_hr',
  ]) {
    expect(key(k), findsOneWidget, reason: k);
  }
  expect(find.byType(ZoneMeter), findsOneWidget);
}

void main() {
  group('Pflichtanzeigen im Lauf', () {
    testWidgets('laufend mit Puls, Schrittfrequenz, Höhe und Runde', (
      tester,
    ) async {
      final cadence = FakeCadenceSensor();
      final d = Device()..cadence = cadence;
      await openRun(d, tester);
      await walk(d, tester, 60, altitude: true);
      d.heartRate.emitReading('hr1', d.clock.now(), 150);
      cadence.emit(d.clock.now(), 171.6);
      await tester.pump(const Duration(seconds: 1));
      d.clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(key('run_lap'));
      await tester.pump();

      expectRequired();
      expect(text('run_time'), '1:01');
      expect(text('run_distance'), matches(RegExp(r'^0,1\d km$')));
      expect(text('run_pace'), matches(RegExp(r'^5:\d\d min/km$')));
      expect(text('run_avg_pace'), matches(RegExp(r'^5:\d\d min/km$')));
      expect(text('run_moving_time'), '1:01');
      expect(text('run_hr'), '150 bpm');
      expect(text('run_zone'), 'Zone 2');
      expect(
        tester.widget<ZoneMeter>(find.byType(ZoneMeter)).zone,
        2,
        reason: 'Zonenanzeige zeigt Zone 2',
      );
      expect(
        tester.widget<ZoneMeter>(find.byType(ZoneMeter)).semanticLabel,
        isEmpty,
        reason: 'der Text sagt „Zone 2“ schon; der Balken nicht noch einmal',
      );
      expect(text('run_ascent'), matches(RegExp(r'^\d+ m$')));
      expect(text('run_cadence'), '172 spm');
      expect(find.text('Runde 1: 1:01'), findsOneWidget);
      expect(text('live_chip_gps'), 'GPS gut');
      expect(text('live_chip_hr'), 'Puls verbunden');
      // Läuft: Runde und Pause, kein Beenden, kein Weiter.
      expect(text('live_state'), 'Läuft');
      expect(key('run_pause'), findsOneWidget);
      expect(key('run_lap'), findsOneWidget);
      expect(key('run_finish'), findsNothing);
      expect(key('run_resume'), findsNothing);
    });

    testWidgets(
      'pausiert: alle Werte bleiben, Weiter und Beenden nebeneinander',
      (tester) async {
        final d = Device()..cadence = FakeCadenceSensor();
        await openRun(d, tester);
        await walk(d, tester, 30);
        d.heartRate.emitReading('hr1', d.clock.now(), 150);
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(key('run_pause'));
        await tester.pump();

        expectRequired();
        expect(text('run_banner_paused'), 'Pausiert');
        expect(key('live_state'), findsNothing);
        expect(key('run_pause'), findsNothing);
        expect(
          key('run_lap'),
          findsNothing,
          reason: 'Runde ist pausiert gesperrt',
        );
        final resume = tester.getRect(key('run_resume'));
        final finish = tester.getRect(key('run_finish'));
        expect(resume.center.dy, closeTo(finish.center.dy, 0.5));
        expect(resume.right, lessThan(finish.left));
        expect(find.text('Weiter'), findsOneWidget);
        expect(find.text('Beenden'), findsOneWidget);
      },
    );

    testWidgets('ohne Puls: nicht verfügbar statt 0, Zonenanzeige grau', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 5);
      expectRequired();
      expect(text('run_hr'), 'nicht verfügbar');
      expect(key('run_zone'), findsNothing);
      expect(tester.widget<ZoneMeter>(find.byType(ZoneMeter)).zone, isNull);
      expect(text('live_chip_hr'), 'Kein Puls');
      expect(find.textContaining('0 bpm'), findsNothing);
    });

    testWidgets(
      'ohne Recht für die Schrittfrequenz: nicht verfügbar (FR-0202)',
      (tester) async {
        final d = Device()
          ..cadence = FakeCadenceSensor(CadenceAvailability.permissionDenied);
        await openRun(d, tester);
        await walk(d, tester, 5);
        expectRequired();
        expect(text('run_cadence'), 'nicht verfügbar');
      },
    );

    testWidgets('GPS-Verlust: Chip, Meldung und Lücke (FR-0194)', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 20);
      expect(key('run_gps'), findsNothing);
      for (var i = 0; i < 15; i++) {
        d.clock.advance(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(text('live_chip_gps'), 'GPS verloren');
      expect(text('run_gps'), contains('Signal verloren'));
      await walk(d, tester, 3, from: 40);
      expect(key('run_gps'), findsNothing);
      expect(text('run_gaps'), 'GPS-Lücken: 1');
    });

    testWidgets('Sensorwechsel und Quelle bleiben erreichbar', (tester) async {
      final d = Device();
      await openRun(d, tester, viaSensors: true, ids: ['h1', 'h2']);
      d.sensorFake.emitReading('h1', d.clock.now(), 150);
      await tester.pump();
      expectRequired();
      expect(text('run_sensor_source'), 'Quelle: Gurt h1');
      expect(text('live_chip_hr'), 'Puls verbunden');
      await tester.ensureVisible(key('run_sensor_select_h2'));
      await tester.tap(key('run_sensor_select_h2'));
      await tester.pump();
      expect(text('run_sensor_source'), 'Quelle: Gurt h2');
      expect(key('run_sensor_select_h1'), findsOneWidget);
    });
  });

  group('Autopause und Bedienung (FR-0028, FR-0029)', () {
    Future<void> standStill(Device d, WidgetTester tester, int seconds) async {
      for (var i = 0; i < seconds; i++) {
        d.clock.advance(const Duration(seconds: 1));
        d.location.emit(
          LocationSample(
            time: d.clock.now(),
            latitude: 50 + 20 * 0.000027,
            longitude: 8,
            accuracyMeters: 5,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
      }
    }

    Future<Device> autoPaused(WidgetTester tester) async {
      final d = Device();
      await openRun(
        d,
        tester,
        before: () => d.session.settings.set(
          SettingKeys.autoPause,
          '1',
          at: d.clock.now(),
        ),
      );
      await walk(d, tester, 20);
      await standStill(d, tester, 30);
      return d;
    }

    testWidgets('Autopause: Kopfzeile sagt Autopause, nicht „Läuft“', (
      tester,
    ) async {
      await autoPaused(tester);
      expect(key('run_banner_autopaused'), findsOneWidget);
      expect(text('live_state'), 'Autopause');
      expect(find.text('Läuft'), findsNothing);
    });

    testWidgets('Autopause: Pause und Runde, kein Weiter/Beenden; Pause '
        'führt zu Beenden', (tester) async {
      await autoPaused(tester);
      expect(key('run_pause'), findsOneWidget);
      expect(key('run_lap'), findsOneWidget);
      expect(key('run_resume'), findsNothing);
      expect(key('run_finish'), findsNothing);
      await tester.tap(key('run_pause'));
      await tester.pump();
      expect(text('run_banner_paused'), 'Pausiert');
      expect(key('run_resume'), findsOneWidget);
      expect(key('run_finish'), findsOneWidget);
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Lauf beendet'), findsOneWidget);
    });

    testWidgets('Pause, Runde und Beenden haben die Tipp-Aktion', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 5);
      bool canTap(String k) => tester
          .getSemantics(key(k))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap);
      expect(canTap('run_pause'), isTrue);
      expect(canTap('run_lap'), isTrue);
      // Wie ein Screenreader: die Aktion selbst auslösen, nicht den Zeiger.
      expect(key('run_finish'), findsNothing);
      final node = tester.getSemantics(key('run_pause'));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(key('run_finish'), findsOneWidget);
      expect(canTap('run_finish'), isTrue);
      expect(canTap('run_resume'), isTrue);
      handle.dispose();
    });

    testWidgets('Sprachausgabe: Einheit ohne Wortverbinder', (tester) async {
      final handle = tester.ensureSemantics();
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 30);
      final label = tester.getSemantics(key('run_avg_pace')).label;
      expect(label, contains('min/km'));
      expect(label, isNot(contains('\u2060')));
      handle.dispose();
    });
  });

  group('Beenden (FR-0028)', () {
    testWidgets('ohne Bestätigung beendet nichts, Pause bleibt', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 5);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      expect(find.text('Lauf beenden?'), findsOneWidget);
      // Zurück aus der Rückfrage (Systemgeste) ist kein Bestätigen.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Lauf beenden?'), findsNothing);
      expect(find.text('Lauf beendet'), findsNothing);
      expect(key('run_resume'), findsOneWidget);
      expect((await d.session.runs.list()).single.state, RunState.paused);
    });

    testWidgets('Zurück beendet nur nach Bestätigung, laufend fragt nach der '
        'Pause und beendet nie', (tester) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 5);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Lauf beenden?'), findsNothing);
      expect(find.text('Lauf pausieren?'), findsOneWidget); // OQ-0076
      await tester.tap(key('run_pause_ask_stay'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Lauf beenden?'), findsOneWidget);
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Lauf beendet'), findsOneWidget);
    });

    testWidgets('Pausenzeit zählt zur Gesamtzeit, nicht zur Bewegungszeit '
        '(FR-0052)', (tester) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 10);
      await tester.tap(key('run_pause'));
      await tester.pump();
      d.clock.advance(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      expect(text('run_time'), '0:30');
      expect(text('run_moving_time'), '0:10');
      await tester.tap(key('run_resume'));
      await tester.pump();
      await walk(d, tester, 5, from: 10);
      expect(text('run_time'), '0:35');
      expect(text('run_moving_time'), '0:15');
    });
  });

  group('Einheiten', () {
    for (final unit in ['min/km', 'min/mi']) {
      testWidgets('$unit bricht bei keiner Breite am „/“ um', (tester) async {
        // Schmaler als die Einheit selbst geht es nicht ohne Zeichenbruch.
        final unitWidth = (TextPainter(
          text: TextSpan(text: unit, style: const TextStyle(fontSize: 14)),
          textDirection: TextDirection.ltr,
        )..layout()).width;
        for (var w = unitWidth.ceilToDouble(); w <= 260; w += 1) {
          await tester.pumpWidget(
            MaterialApp(
              home: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: w,
                  child: LiveValueText(
                    id: 'u',
                    value: '5:38',
                    unit: unit,
                    valueStyle: const TextStyle(fontSize: 34),
                    unitStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
          );
          final p = tester.renderObject<RenderParagraph>(
            find.descendant(of: key('u'), matching: find.byType(RichText)),
          );
          final plain = p.text.toPlainText();
          final start = plain.indexOf('min');
          final boxes = p.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: plain.length),
          );
          expect(
            boxes.map((b) => b.top).toSet().length,
            1,
            reason: 'Einheit in einem Stück bei Breite $w',
          );
        }
      });
    }
  });

  group('Layout 411x914, Faktor 1,0 (Gerätebefund E2E 36)', () {
    // Alle laufenden Werte stehen ohne Anschnitt und ohne Scrollen über dem
    // Bedienfeld, auch ohne Puls und ohne Schrittfrequenz.
    for (final cadenceAvailable in [false, true]) {
      testWidgets(
        'echte Schrift, ${cadenceAvailable ? 'mit' : 'ohne'} Sensoren: '
        'alle Werte sichtbar, Abstand zum Bedienfeld',
        (tester) async {
          await loadManrope(tester);
          final cadence = FakeCadenceSensor(
            cadenceAvailable
                ? CadenceAvailability.available
                : CadenceAvailability.permissionDenied,
          );
          final d = Device()..cadence = cadence;
          await d.start(tester, const Locale('de'));
          await d.skipSetup(tester);
          tester.view.physicalSize = const Size(411, 914);
          tester.view.devicePixelRatio = 1;
          // Statusleiste und Navigationsleiste des Geräts.
          tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
          addTearDown(tester.view.reset);
          await d.session.profile.save(
            const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
          );
          await tester.tap(key('home_start_run'));
          await tester.pumpAndSettle();
          await tester.tap(key('run_start_ready'));
          await tester.pumpAndSettle();
          await walk(d, tester, 5);
          if (cadenceAvailable) {
            d.heartRate.emitReading('hr1', d.clock.now(), 150);
            cadence.emit(d.clock.now(), 172);
            await tester.pump(const Duration(seconds: 1));
          }
          expect(tester.takeException(), isNull);
          final viewport = tester.getRect(find.byType(ListView).first);
          final controlsTop = tester.getRect(key('run_pause')).top;
          for (final k in [
            'run_time',
            'run_distance',
            'run_pace',
            'run_avg_pace',
            'run_hr',
            if (key('run_zone').evaluate().isNotEmpty) 'run_zone',
            'run_moving_time',
            'run_ascent',
            'run_cadence',
          ]) {
            final r = tester.getRect(key(k));
            expect(r.bottom, lessThanOrEqualTo(viewport.bottom), reason: k);
            expect(r.bottom, lessThan(controlsTop), reason: k);
          }
          // Die Karte der Schrittfrequenz endet samt Rand im sichtbaren Bereich.
          final card = find.ancestor(
            of: key('run_cadence'),
            matching: find.byType(RamuriCard),
          );
          expect(
            tester.getRect(card.first).bottom,
            lessThanOrEqualTo(viewport.bottom - 8),
            reason: 'Karte Schrittfrequenz nicht angeschnitten',
          );
        },
      );
    }

    testWidgets('ohne Puls: „nicht verfügbar“ nur einmal, keine Zonenzeile', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 5);
      expect(text('run_hr'), 'nicht verfügbar');
      expect(key('run_zone'), findsNothing);
      expect(find.textContaining('Zone nicht verfügbar'), findsNothing);
      expect(find.text('nicht verfügbar'), findsWidgets);
      // Die Pulskarte sagt es für die Sprachausgabe genau einmal.
      final label = tester
          .getSemantics(find.bySemanticsLabel(RegExp('nicht verfügbar')).first)
          .label;
      expect('nicht verfügbar'.allMatches(label), hasLength(1), reason: label);
      semantics.dispose();
    });
  });

  group('Layout 360x640, Schriftfaktor 1,3', () {
    for (final dark in [false, true]) {
      for (final paused in [false, true]) {
        testWidgets(
          '${dark ? 'dunkel' : 'hell'}, ${paused ? 'pausiert' : 'laufend'}: '
          'kein Überlauf, Ziele ab 48 dp',
          (tester) async {
            final cadence = FakeCadenceSensor();
            final d = Device()..cadence = cadence;
            await d.start(tester, const Locale('de'));
            await d.skipSetup(tester);
            tester.view.physicalSize = const Size(360, 640);
            tester.platformDispatcher.textScaleFactorTestValue = 1.3;
            tester.platformDispatcher.platformBrightnessTestValue = dark
                ? Brightness.dark
                : Brightness.light;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            addTearDown(
              tester.platformDispatcher.clearPlatformBrightnessTestValue,
            );
            await d.session.profile.save(
              const ProfileRecord(
                maxHeartRateBpm: 190,
                restingHeartRateBpm: 60,
              ),
            );
            await tester.tap(key('home_start_run'));
            await tester.pumpAndSettle();
            await tester.tap(key('run_start_ready'));
            await tester.pumpAndSettle();
            // Über eine Stunde: lange Zeit, drei- bis vierstellige Werte.
            for (var i = 0; i < 40; i++) {
              d.clock.advance(const Duration(seconds: 100));
              d.location.emit(
                LocationSample(
                  time: d.clock.now(),
                  latitude: 50 + i * 0.0003,
                  longitude: 8,
                  accuracyMeters: 5,
                  altitudeMeters: 100 + i * 5.0,
                  verticalAccuracyMeters: 3,
                ),
              );
              await tester.pump(const Duration(seconds: 1));
            }
            d.heartRate.emitReading('hr1', d.clock.now(), 187);
            cadence.emit(d.clock.now(), 178);
            await tester.pump(const Duration(seconds: 1));
            await tester.tap(key('run_lap'));
            await tester.pump();
            if (paused) {
              await tester.tap(key('run_pause'));
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
            expectRequired();
            final buttons = paused
                ? ['run_resume', 'run_finish']
                : ['run_lap', 'run_pause'];
            for (final k in [...buttons, 'run_tab_0', 'run_tab_1']) {
              final r = tester.getRect(key(k));
              expect(r.width, greaterThanOrEqualTo(48), reason: k);
              expect(r.height, greaterThanOrEqualTo(48), reason: k);
              expect(r.bottom, lessThanOrEqualTo(640), reason: k);
              expect(r.left, greaterThanOrEqualTo(0), reason: k);
              expect(r.right, lessThanOrEqualTo(360), reason: k);
            }
            // Die Zahlen passen in die Breite (Zeit verkleinert sich, nichts läuft über).
            expect(
              tester.getRect(key('run_time')).right,
              lessThanOrEqualTo(360),
            );
            expect(
              tester.getRect(key('run_pace')).right,
              lessThanOrEqualTo(360),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
