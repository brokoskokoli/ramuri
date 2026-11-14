import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:running_app/features/run/live_run_view.dart';

import 'app_harness.dart';

/// Zugriff, dessen Anfrage nie beantwortet wird (Antwort nach Neuerzeugung der
/// Activity verloren) oder mit `busy` scheitert.
class _OddAccess extends FakeLocationAccess {
  _OddAccess({this.never = false, this.busy = false});
  final bool never;
  bool busy;

  @override
  Future<LocationAccess> request() {
    requestCount++;
    if (never) return Completer<LocationAccess>().future;
    if (busy) throw PlatformException(code: 'busy');
    return super.request();
  }
}

/// Speicher, dessen Rohdaten sich nicht schreiben lassen.
class _RawFailStorage implements Storage {
  _RawFailStorage(this.inner);
  final Storage inner;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      _RawFailSession(await inner.open(key));
}

class _RawFailSession implements StorageSession {
  _RawFailSession(this.s);
  final StorageSession s;
  @override
  RawDataStore get rawData => _FailingRaw(s.rawData);
  @override
  SettingsStore get settings => s.settings;
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
  RunSubjectiveStore get subjective => s.subjective;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _FailingRaw implements RawDataStore {
  _FailingRaw(this.inner);
  final RawDataStore inner;
  @override
  Future<void> append(int runId, RawBatch batch) =>
      Future.error(const StorageException(StorageFailure.failed));
  @override
  Future<StoredRawData> read(int runId) => inner.read(runId);
}

/// Text eines Werts der Lauf-Seite; Zahl und Einheit stehen in Teilen, der
/// Wortverbinder (U+2060) ist unsichtbar.
String text(String k) {
  final w = key(k).evaluate().single.widget as Text;
  return (w.data ?? w.textSpan!.toPlainText()).replaceAll('\u2060', '');
}

Future<void> openRun(
  Device d,
  WidgetTester tester, {
  String? locale,
  Future<void> Function()? before,
}) async {
  await d.start(tester, Locale(locale ?? 'de'));
  await d.skipSetup(tester);
  await before?.call();
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
}

/// Ein Punkt je Sekunde, geradeaus nach Norden mit rund 3 m/s.
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

void main() {
  test(
    'Durchschnittspace: Zeit in GPS-Lücken zählt nicht (Review 1, Soll 3)',
    () {
      final clock = FakeClock(DateTime.utc(2030, 1, 1, 12));
      final session = RecordingSession(clock: clock)..start();
      for (var i = 1; i <= 30; i++) {
        clock.advance(const Duration(seconds: 1));
        session.addPosition(
          LocationSample(
            time: clock.now(),
            latitude: 50 + i * 0.000027,
            longitude: 8,
            accuracyMeters: 5,
          ),
        );
      }
      clock.advance(const Duration(seconds: 30)); // keine Punkte mehr
      final s = session.snapshot();
      expect(s.movingTime, const Duration(seconds: 60), reason: 'läuft weiter');
      // 30 s Lücke und 1 s vom Start bis zum ersten Punkt (ohne Strecke).
      expect(s.positionLossMovingTime, const Duration(seconds: 31));
      final km = s.distanceMeters! / 1000;
      // Nur die 29 s mit Strecke gelten, nicht die 60 s Bewegungszeit.
      expect(averagePaceSecondsPerKm(s)!, closeTo(29 / km, 0.001));
    },
  );

  test('Durchschnittspace: Lücke im erkannten Stillstand wird nicht '
      'abgezogen (Review 2, Soll 2)', () {
    final clock = FakeClock(DateTime.utc(2030, 1, 1, 12));
    final session = RecordingSession(clock: clock, autoPause: true)..start();
    void gps(int from, int n, {required bool move}) {
      for (var i = from; i < from + n; i++) {
        clock.advance(const Duration(seconds: 1));
        session.addPosition(
          LocationSample(
            time: clock.now(),
            latitude: 50 + (move ? i : from) * 0.000027,
            longitude: 8,
            accuracyMeters: 5,
          ),
        );
      }
    }

    gps(1, 30, move: true);
    gps(30, 20, move: false); // Stand, erkannte Pause
    expect(session.phase, RecordingPhase.autoPaused);
    final before = session.snapshot();
    clock.advance(const Duration(seconds: 40)); // Lücke im Stand
    final s = session.snapshot();
    expect(s.positionLost, isTrue);
    // Nur die 1 s vom Start bis zum ersten Punkt; die Lücke im Stand nicht.
    expect(s.positionLossMovingTime, const Duration(seconds: 1));
    expect(s.movingTime, before.movingTime);
    final km = s.distanceMeters! / 1000;
    expect(
      averagePaceSecondsPerKm(s)!,
      closeTo((s.movingTime!.inMicroseconds / 1e6 - 1) / km, 0.001),
    );
  });

  group('Startprüfung (FR-0195)', () {
    testWidgets(
      'Berechtigung fehlt: Grund sichtbar, kein Lauf; Anfrage startet',
      (tester) async {
        final d = Device()
          ..locationAccess.current = LocationAccess.denied
          ..locationAccess.onRequest = LocationAccess.precise;
        await openRun(d, tester);
        expect(key('run_block_permissionDenied'), findsOneWidget);
        expect(find.textContaining('genauen Standort'), findsOneWidget);
        expect(await d.session.runs.list(), isEmpty);
        expect(key('run_pause'), findsNothing);

        await tester.tap(key('run_block_ask'));
        await tester.pumpAndSettle();
        expect(d.locationAccess.requestCount, 1);
        // Nach der Blockade startet nichts von selbst (Review 1, Soll 5).
        expect(key('run_start_ready'), findsOneWidget);
        expect(key('run_pause'), findsNothing);
        expect(await d.session.runs.list(), isEmpty);
        await tester.tap(key('run_start_ready'));
        await tester.pumpAndSettle();
        expect(key('run_pause'), findsOneWidget);
        expect(await d.session.runs.list(), hasLength(1));
      },
    );

    testWidgets('Einstellungen öffnen bei verweigerter Berechtigung', (
      tester,
    ) async {
      final d = Device()..locationAccess.current = LocationAccess.denied;
      await openRun(d, tester);
      await tester.tap(key('run_block_settings'));
      await tester.pump();
      expect(d.permissions.openSettingsCount, 1);
    });

    testWidgets('Nur ungefährer Standort: kein Start, eigener Grund', (
      tester,
    ) async {
      final d = Device()
        ..locationAccess.current = LocationAccess.approximateOnly;
      await openRun(d, tester);
      expect(key('run_block_approximateOnly'), findsOneWidget);
      expect(find.textContaining('ungefähre Standort'), findsOneWidget);
      expect(await d.session.runs.list(), isEmpty);
      expect(key('run_pause'), findsNothing);
      // Nach Erteilung des genauen Standorts startet er (Anfrage).
      d.locationAccess.onRequest = LocationAccess.precise;
      await tester.tap(key('run_block_ask'));
      await tester.pumpAndSettle();
      // Nach der Blockade startet nichts von selbst (Review 1, Soll 5).
      expect(key('run_start_ready'), findsOneWidget);
      expect(key('run_pause'), findsNothing);
      expect(await d.session.runs.list(), isEmpty);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
    });

    testWidgets('GPS aus: Grund, kein Start; Erneut prüfen startet', (
      tester,
    ) async {
      final d = Device()..locationAccess.gps = false;
      await openRun(d, tester);
      expect(key('run_block_gpsOff'), findsOneWidget);
      expect(key('run_block_ask'), findsNothing);
      expect(await d.session.runs.list(), isEmpty);
      d.locationAccess.gps = true;
      await tester.tap(key('run_block_recheck'));
      await tester.pumpAndSettle();
      // Nach der Blockade startet nichts von selbst (Review 1, Soll 5).
      expect(key('run_start_ready'), findsOneWidget);
      expect(key('run_pause'), findsNothing);
      expect(await d.session.runs.list(), isEmpty);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
    });

    testWidgets('Stand nicht lesbar: unbekannter Grund, kein Start', (
      tester,
    ) async {
      final d = Device()..locationAccess.fail = true;
      await openRun(d, tester);
      expect(key('run_block_unknown'), findsOneWidget);
      expect(await d.session.runs.list(), isEmpty);
      d.locationAccess.fail = false;
      await tester.tap(key('run_block_recheck'));
      await tester.pumpAndSettle();
      // Nach der Blockade startet nichts von selbst (Review 1, Soll 5).
      expect(key('run_start_ready'), findsOneWidget);
      expect(key('run_pause'), findsNothing);
      expect(await d.session.runs.list(), isEmpty);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
    });

    testWidgets('Anfrage mit busy: Hinweis statt Absturz, erneut prüfen geht', (
      tester,
    ) async {
      final access = _OddAccess(busy: true)..current = LocationAccess.denied;
      final d = Device()..locationAccessOverride = access;
      await openRun(d, tester);
      await tester.tap(key('run_block_ask'));
      await tester.pumpAndSettle();
      expect(key('run_block_unknown'), findsOneWidget);
      // Die frühere Anfrage ist inzwischen beantwortet.
      access.current = LocationAccess.precise;
      await tester.tap(key('run_block_recheck'));
      await tester.pumpAndSettle();
      // Nach der Blockade startet nichts von selbst (Review 1, Soll 5).
      expect(key('run_start_ready'), findsOneWidget);
      expect(key('run_pause'), findsNothing);
      expect(await d.session.runs.list(), isEmpty);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
    });

    testWidgets(
      'Verlorene Antwort nach Neuerzeugung: Rückkehr liest den Stand',
      (tester) async {
        final access = _OddAccess(never: true)..current = LocationAccess.denied;
        final d = Device()..locationAccessOverride = access;
        await openRun(d, tester);
        await tester.tap(key('run_block_ask'));
        await tester.pump();
        expect(key('run_checking'), findsOneWidget);
        // Der Nutzer erteilt im Dialog; die Antwort kommt nie an.
        access.current = LocationAccess.precise;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        // Nach der Blockade startet nichts von selbst (Review 1, Soll 5).
        expect(key('run_start_ready'), findsOneWidget);
        expect(key('run_pause'), findsNothing);
        expect(await d.session.runs.list(), isEmpty);
        await tester.tap(key('run_start_ready'));
        await tester.pumpAndSettle();
        expect(key('run_pause'), findsOneWidget);
      },
    );
  });

  group('Live-Anzeige (FR-0026, FR-0027)', () {
    testWidgets('ohne Daten: nicht verfügbar statt 0, keine Zone, keine Zahl', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      expect(text('run_hr'), 'nicht verfügbar');
      // Ohne Puls steht „nicht verfügbar“ nur am Pulswert, keine zweite Zonenzeile.
      expect(key('run_zone'), findsNothing);
      expect(text('run_cadence'), 'nicht verfügbar');
      expect(text('run_ascent'), 'nicht verfügbar');
      expect(text('run_distance'), 'noch keine Daten');
      expect(text('run_pace'), 'noch keine Daten');
      expect(text('run_avg_pace'), 'noch keine Daten');
      expect(text('run_gps'), contains('Suche'));
      expect(text('run_sensor_status'), contains('Kein Sensor verbunden'));
      expect(find.textContaining(RegExp(r'\b0 bpm')), findsNothing);
      expect(find.text('Noch keine Runde markiert'), findsOneWidget);
      expect(text('run_time'), '0:00');
    });

    testWidgets('mit Daten: Zeit, Strecke, Pace, Puls, Zone, Höhe', (
      tester,
    ) async {
      final d = Device();
      await openRun(
        d,
        tester,
        before: () => d.session.profile.save(
          const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
        ),
      );
      await walk(d, tester, 60, altitude: true);
      d.heartRate.emitReading('hr1', d.clock.now(), 150);
      await tester.pump(const Duration(seconds: 1));
      d.clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(text('run_time'), '1:01');
      expect(text('run_distance'), matches(RegExp(r'^0,1\d km$')));
      expect(text('run_pace'), matches(RegExp(r'^5:\d\d$')));
      expect(text('run_avg_pace'), matches(RegExp(r'^5:\d\d$')));
      expect(text('run_hr'), '150 bpm');
      expect(text('run_zone'), 'Zone 2');
      expect(text('run_sensor_status'), 'Sensor verbunden');
      // Gutes GPS steht nur im Chip, die lange Meldung gibt es nur bei Problemen.
      expect(text('live_chip_gps'), 'GPS gut');
      expect(key('run_gps'), findsNothing);
      expect(text('run_ascent'), matches(RegExp(r'^\d+ m$')));
      expect(text('run_cadence'), 'nicht verfügbar');
    });

    testWidgets('Zone ohne Basiswerte ist nicht verfügbar (OQ-0012)', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 3);
      d.heartRate.emitReading('hr1', d.clock.now(), 150);
      await tester.pump(const Duration(seconds: 1));
      expect(text('run_hr'), '150 bpm');
      expect(text('run_zone'), contains('nicht verfügbar'));
      expect(text('run_zone'), contains('Profil'));
    });

    testWidgets('Meilen mit echter Strecke (NFR-0006)', (tester) async {
      final d = Device();
      await d.start(tester, const Locale('en'));
      await d.skipSetup(tester);
      await d.session.settings.set(
        SettingKeys.distanceUnit,
        'mi',
        at: d.clock.now(),
      );
      // Einstellung wirkt über die Oberfläche.
      await openOverview(tester);
      await tester.tap(key('home_settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miles'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 120);
      // 119 Schritte zu je rund 3,0 m: rund 357 m = 0.22 mi (0.36 km).
      expect(text('run_distance'), '0.22 mi');
      expect(text('run_pace'), matches(RegExp(r'^\d+:\d\d$')));
      // Die Einheit steht in der Beschriftung (die Sprachausgabe nennt sie).
      final semantics = tester.ensureSemantics();
      final label = tester.getSemantics(key('run_pace')).label;
      expect(label, contains('min/mi'));
      expect(label, isNot(contains('min/km')));
      semantics.dispose();
    });

    testWidgets('Meilenmodus: Höhenmeter in Fuß', (tester) async {
      final d = Device();
      await d.start(tester, const Locale('en'));
      await d.skipSetup(tester);
      await d.session.settings.set(
        SettingKeys.distanceUnit,
        'mi',
        at: d.clock.now(),
      );
      await openOverview(tester);
      await tester.tap(key('home_settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miles'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 61, altitude: true);
      // 60 Schritte zu je 0,5 m Anstieg: höchstens 30 m = 98 ft.
      expect(text('run_ascent'), matches(RegExp(r'^\d+ ft$')));
      final ft = int.parse(text('run_ascent').split(' ').first);
      expect(ft, inInclusiveRange(60, 100));
    });

    testWidgets('Stand: Pace als Strich (OQ-0037)', (tester) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 20);
      for (var i = 0; i < 30; i++) {
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
      expect(text('run_pace'), '–');
    });

    testWidgets('GPS-Lücke: markiert, Strecke unverändert, Zeit läuft', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 20);
      final before = text('run_distance');
      for (var i = 0; i < 15; i++) {
        d.clock.advance(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(text('run_gps'), contains('verloren'));
      expect(text('run_distance'), before);
      expect(text('run_time'), '0:35');
      // Rückkehr schließt die Lücke, sie bleibt als Zähler sichtbar.
      await walk(d, tester, 2, from: 40);
      expect(key('run_gps'), findsNothing);
      expect(text('live_chip_gps'), 'GPS gut');
      expect(text('run_gaps'), 'GPS-Lücken: 1');
    });

    testWidgets('Speicherfehler ist sichtbar, Anzeige läuft weiter', (
      tester,
    ) async {
      final d = Device();
      d.storageOverride = _RawFailStorage(d.storage);
      await openRun(d, tester);
      expect(key('run_banner_storage'), findsNothing);
      await walk(d, tester, 3);
      expect(key('run_banner_storage'), findsOneWidget);
      expect(find.textContaining('Speichern fehlgeschlagen'), findsOneWidget);
      expect(text('run_time'), '0:03');
    });

    testWidgets('Standortquelle meldet Fehler: sichtbar', (tester) async {
      final d = Device();
      await openRun(d, tester);
      expect(d.location.hasListeners, isTrue);
      d.location.fail(const LocationSourceFailure(LocationFailureReason.other));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(text('run_gps'), contains('Fehler'));
    });
  });

  group('Steuerung (FR-0028, FR-0029, FR-0030)', () {
    testWidgets('Pause, Runde gesperrt, Fortsetzen, Runde mit Zeit', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 10);
      await tester.tap(key('run_pause'));
      await tester.pump();
      expect(key('run_banner_paused'), findsOneWidget);
      expect(key('run_resume'), findsOneWidget);
      // In der Pause ist die Runde gesperrt und der Knopf entfällt (Design).
      expect(key('run_lap'), findsNothing);
      await tester.tap(key('run_resume'));
      await tester.pump();
      expect(key('run_banner_paused'), findsNothing);
      await walk(d, tester, 5, from: 10);
      await tester.tap(key('run_lap'));
      await tester.pump();
      expect(find.text('Runde 1: 0:15'), findsOneWidget);
    });

    testWidgets('Beenden mit Bestätigung: Abbrechen lässt den Lauf pausiert', (
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
      await tester.tap(key('run_finish_cancel'));
      await tester.pumpAndSettle();
      expect(key('run_resume'), findsOneWidget);
      expect(key('run_banner_paused'), findsOneWidget);
      expect((await d.session.runs.list()).single.state, RunState.paused);
      // Ohne Bestätigung endet nichts, auch nicht nach Zurück aus der Rückfrage.
      expect(find.text('Lauf beendet'), findsNothing);
    });

    testWidgets('Beenden gibt es nur pausiert (FR-0028)', (tester) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 5);
      expect(key('run_finish'), findsNothing);
      // Zurück im laufenden Lauf fragt nach der Pause (OQ-0076), nie nach dem
      // Beenden; „Weiterlaufen“ lässt alles, wie es ist.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Lauf beenden?'), findsNothing);
      expect(find.text('Lauf pausieren?'), findsOneWidget);
      await tester.tap(key('run_pause_ask_stay'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
      await tester.tap(key('run_pause'));
      await tester.pump();
      expect(key('run_finish'), findsOneWidget);
      expect(key('run_pause'), findsNothing);
      await tester.tap(key('run_resume'));
      await tester.pump();
      expect(key('run_finish'), findsNothing);
    });

    testWidgets('Beenden: Abschlussansicht, Lauf gespeichert, Fertig', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 30);
      await tester.tap(key('run_lap'));
      await tester.pump();
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Lauf beendet'), findsOneWidget);
      expect(text('run_done_status'), 'Der Lauf ist gespeichert.');
      expect(text('run_time'), '0:30');
      expect(key('run_pause'), findsNothing);
      expect(find.text('Runde 1: 0:30'), findsOneWidget);
      final run = (await d.session.runs.list()).single;
      expect(run.state, RunState.finished);
      expect((await d.session.rawData.read(run.id)).positions, isNotEmpty);

      await tester.tap(key('run_done_close'));
      await tester.pumpAndSettle();
      expect(key('home_start_run'), findsOneWidget);
    });

    // WP18 Review 1, Befund 7: Die Angaben zum Lauf sind in der Abschlussansicht
    // verdrahtet und speichern in den Speicher des Laufs.
    testWidgets('Beenden: Angaben zum Lauf in der Abschlussansicht', (
      tester,
    ) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 30);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('subjective_section'));
      expect(key('subjective_section'), findsOneWidget);
      final id = (await d.session.runs.list()).single.id;
      expect(await d.session.subjective.read(id), isNull);
      await tester.ensureVisible(key('subjective_rpe_5'));
      await tester.tap(key('subjective_rpe_5'));
      await tester.pumpAndSettle();
      expect((await d.session.subjective.read(id))!.subjective.rpe, 5);
    });

    testWidgets('Abschluss bei Speicherfehler meldet ihn', (tester) async {
      final d = Device();
      d.storageOverride = _RawFailStorage(d.storage);
      await openRun(d, tester);
      await walk(d, tester, 3);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(text('run_done_status'), contains('Fehler'));
    });

    testWidgets('Autopause an: Stillstand pausiert, aus: nicht', (
      tester,
    ) async {
      for (final on in [false, true]) {
        final d = Device();
        await openRun(
          d,
          tester,
          before: () async {
            if (on) {
              await d.session.settings.set(
                SettingKeys.autoPause,
                '1',
                at: d.clock.now(),
              );
            }
          },
        );
        await walk(d, tester, 20);
        for (var i = 0; i < 30; i++) {
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
        expect(
          key('run_banner_autopaused'),
          on ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('Layout', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('411x914 ohne Überlauf, Textskalierung $scale', (
        tester,
      ) async {
        final d = Device();
        d.storageOverride = _RawFailStorage(d.storage);
        await d.start(tester, const Locale('de'));
        await d.skipSetup(tester);
        tester.view.physicalSize = const Size(411, 914);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.tap(key('home_start_run'));
        await tester.pumpAndSettle();
        await tester.tap(key('run_start_ready'));
        await tester.pumpAndSettle();
        await walk(d, tester, 40, altitude: true);
        d.heartRate.emitReading('hr1', d.clock.now(), 150);
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(key('run_pause'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Steuerung bleibt erreichbar.
        expect(
          tester.getRect(key('run_finish')).bottom,
          lessThanOrEqualTo(914),
        );
        await tester.tap(key('run_finish'));
        await tester.pumpAndSettle();
        await tester.tap(key('run_finish_confirm'));
        await tester.pumpAndSettle();
        expect(find.text('Lauf beendet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Ablehnung bei 411x914, Skalierung $scale', (tester) async {
        final d = Device()
          ..locationAccess.current = LocationAccess.approximateOnly;
        await d.start(tester, const Locale('de'));
        await d.skipSetup(tester);
        tester.view.physicalSize = const Size(411, 914);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.tap(key('home_start_run'));
        await tester.pumpAndSettle();
        expect(key('run_block_approximateOnly'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
