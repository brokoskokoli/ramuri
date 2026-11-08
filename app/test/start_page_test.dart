import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/live_run_view.dart';
import 'package:running_app/features/sensors/sensors_screen.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

Finder key(String k) => find.byKey(Key(k));

/// Speicher, dessen Einstellung der Autopause sich nicht lesen und/oder nicht
/// schreiben lässt; alle anderen Einstellungen laufen normal.
class _AutoPauseFailStorage implements Storage {
  _AutoPauseFailStorage(
    this.inner, {
    this.failGet = false,
    this.failSet = false,
  });
  final Storage inner;
  final bool failGet;
  final bool failSet;
  @override
  Future<StorageSession> open(Uint8List k) async =>
      _Session(await inner.open(k), this);
}

class _Session implements StorageSession {
  _Session(this.s, this.f);
  final StorageSession s;
  final _AutoPauseFailStorage f;
  @override
  SettingsStore get settings => _Settings(s.settings, f);
  @override
  RawDataStore get rawData => s.rawData;
  @override
  ProfileStore get profile => s.profile;
  @override
  RunStore get runs => s.runs;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _Settings implements SettingsStore {
  _Settings(this.s, this.f);
  final SettingsStore s;
  final _AutoPauseFailStorage f;
  @override
  Future<String?> get(String k) => f.failGet && k == SettingKeys.autoPause
      ? Future.error(const StorageException(StorageFailure.failed))
      : s.get(k);
  @override
  Future<Map<String, String>> all() => s.all();
  @override
  Future<void> set(String k, String v, {required DateTime at}) =>
      f.failSet && k == SettingKeys.autoPause
      ? Future.error(const StorageException(StorageFailure.failed))
      : s.set(k, v, at: at);
}

Future<void> openStart(Device d, WidgetTester tester) async {
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
}

bool switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(key('start_autopause')).value;

/// Die Autopause des gestarteten Laufs, am Controller der Live-Seite.
bool runAutoPause(WidgetTester tester) =>
    tester.widget<LiveRunView>(find.byType(LiveRunView)).controller.autoPause;

Future<void> go(WidgetTester tester) async {
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
}

void main() {
  group('Lauf vorbereiten (FR-0210)', () {
    testWidgets('zeigt GPS, Pulssensor, Schrittfrequenz, Autopause und Los', (
      tester,
    ) async {
      final d = Device()..cadence = FakeCadenceSensor();
      await openStart(d, tester);
      expect(find.text('Bereit?'), findsOneWidget);
      expect(key('start_gps_ready'), findsOneWidget);
      expect(find.text('Pulssensor'), findsOneWidget);
      expect(key('start_sensor_pair'), findsOneWidget);
      expect(find.text('Handy-Sensor'), findsOneWidget);
      expect(key('start_autopause'), findsOneWidget);
      expect(find.text('Los'), findsOneWidget);
      expect(
        find.text('Aufzeichnung läuft auch bei ausgeschaltetem Bildschirm'),
        findsOneWidget,
      );
      // Die Seite startet nicht von selbst.
      expect(find.byType(LiveRunView), findsNothing);
    });

    testWidgets('Schrittfrequenz ohne Sensor: nicht verfügbar', (tester) async {
      final d = Device();
      await openStart(d, tester);
      expect(text(tester, 'start_cadence_source'), 'nicht verfügbar');
    });

    testWidgets('Koppeln führt zur Sensorsuche und zurück auf die Seite', (
      tester,
    ) async {
      final d = Device();
      await openStart(d, tester);
      await tester.tap(key('start_sensor_pair'));
      await tester.pumpAndSettle();
      expect(find.byType(SensorsScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SensorsScreen), findsNothing);
      expect(find.text('Bereit?'), findsOneWidget);
      expect(key('run_start_ready'), findsOneWidget);
      // Die Auswahl der Seite bleibt, der Lauf startet danach normal.
      await go(tester);
      expect(find.byType(LiveRunView), findsOneWidget);
    });

    for (final access in [
      LocationAccess.denied,
      LocationAccess.approximateOnly,
    ]) {
      testWidgets('ohne genauen Standort ($access): Grund, kein Start', (
        tester,
      ) async {
        final d = Device()..locationAccess.current = access;
        await openStart(d, tester);
        expect(key('start_gps_blocked'), findsOneWidget);
        expect(
          key(
            access == LocationAccess.denied
                ? 'run_block_permissionDenied'
                : 'run_block_approximateOnly',
          ),
          findsOneWidget,
        );
        await tester.tap(key('run_start_ready'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(LiveRunView), findsNothing);
        expect(d.location.hasListeners, false);
      });
    }
  });

  group('Autopause (FR-0029, FR-0210)', () {
    testWidgets(
      'erster Lauf: aus, kein Wert gespeichert, Lauf ohne Autopause',
      (tester) async {
        final d = Device();
        await openStart(d, tester);
        expect(switchValue(tester), false);
        expect(await d.session.settings.get(SettingKeys.autoPause), isNull);
        await go(tester);
        expect(runAutoPause(tester), false);
      },
    );

    testWidgets('Wahl an: gespeichert und gilt für den gestarteten Lauf', (
      tester,
    ) async {
      final d = Device();
      await openStart(d, tester);
      await tester.tap(key('start_autopause'));
      await tester.pump();
      expect(switchValue(tester), true);
      expect(await d.session.settings.get(SettingKeys.autoPause), '1');
      await go(tester);
      expect(runAutoPause(tester), true);
    });

    testWidgets('zweiter Start: wie zuletzt gewählt, auch wieder aus', (
      tester,
    ) async {
      final d = Device();
      await openStart(d, tester);
      await tester.tap(key('start_autopause'));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(switchValue(tester), true);
      await go(tester);
      expect(runAutoPause(tester), true);
    });

    testWidgets('zuletzt aus gewählt: der nächste Lauf ohne Autopause', (
      tester,
    ) async {
      final d = Device();
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      await d.session.settings.set(
        SettingKeys.autoPause,
        '0',
        at: d.clock.now(),
      );
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(switchValue(tester), false);
      await go(tester);
      expect(runAutoPause(tester), false);
    });

    testWidgets('Lesefehler: aus', (tester) async {
      final d = Device();
      d.storageOverride = _AutoPauseFailStorage(d.storage, failGet: true);
      await openStart(d, tester);
      expect(switchValue(tester), false);
      await go(tester);
      expect(runAutoPause(tester), false);
    });

    testWidgets('Schreibfehler: die Wahl gilt trotzdem für den Lauf', (
      tester,
    ) async {
      final d = Device();
      d.storageOverride = _AutoPauseFailStorage(d.storage, failSet: true);
      await openStart(d, tester);
      await tester.tap(key('start_autopause'));
      await tester.pump();
      expect(switchValue(tester), true);
      await go(tester);
      expect(runAutoPause(tester), true);
    });

    testWidgets('die Live-Seite hat keinen Schalter mehr', (tester) async {
      final d = Device();
      await openStart(d, tester);
      await go(tester);
      expect(key('run_autopause'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
    });
  });

  group('Darstellung', () {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          '${dark ? 'dunkel' : 'hell'}, Schrift $scale: kein Überlauf, 48 dp',
          (tester) async {
            final d = Device()..cadence = FakeCadenceSensor();
            await d.start(tester, const Locale('de'));
            await d.skipSetup(tester);
            tester.view.physicalSize = const Size(360, 640);
            tester.platformDispatcher.platformBrightnessTestValue = dark
                ? Brightness.dark
                : Brightness.light;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(() {
              tester.platformDispatcher.clearPlatformBrightnessTestValue();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
            });
            await tester.tap(key('home_start_run'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              RamuriColors.of(tester.element(find.byType(Scaffold).last)),
              dark ? RamuriColors.night : RamuriColors.light,
            );
            await tester.dragUntilVisible(
              key('start_autopause'),
              find.byType(ListView),
              const Offset(0, -100),
            );
            for (final k in [
              'run_start_ready',
              'start_sensor_pair',
              'start_autopause',
            ]) {
              final size = tester.getSize(key(k));
              expect(size.height, greaterThanOrEqualTo(48), reason: k);
              expect(size.width, greaterThanOrEqualTo(48), reason: k);
            }
            expect(tester.getSize(key('run_start_ready')).width, 132 + 24);
            // Los bleibt im Bild, auch bei kleiner Höhe.
            expect(
              tester.getRect(key('run_start_ready')).bottom,
              lessThanOrEqualTo(640),
            );
          },
        );
      }
    }
  });
}

String text(WidgetTester tester, String k) =>
    (key(k).evaluate().single.widget as Text).data!;
