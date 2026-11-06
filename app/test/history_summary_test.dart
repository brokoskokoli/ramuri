import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

Finder key(String k) => find.byKey(Key(k));
String text(String k) => (key(k).evaluate().single.widget as Text).data!;

const double _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

/// Beendeter Lauf: [minutes] mit [speed] m/s, Puls [bpm] (oder keiner).
Future<int> seedRun(
  StorageSession s,
  DateTime start, {
  int minutes = 10,
  double speed = 3.0,
  int? bpm = 150,
}) async {
  final run = await s.runs.create(startedAt: start);
  final seconds = minutes * 60;
  await s.rawData.append(
    run.id,
    RawBatch(
      positions: [
        for (var i = 0; i <= seconds; i++)
          RawPosition(
            time: start.add(Duration(seconds: i)),
            source: 'gps',
            latitude: 10 + i * speed / _metersPerDegree,
            longitude: 20,
            accuracyMeters: 5,
          ),
      ],
      heartRates: [
        if (bpm != null)
          for (var i = 0; i <= seconds; i++)
            RawHeartRate(
              time: start.add(Duration(seconds: i)),
              source: 'strap',
              bpm: bpm,
              contact: SensorContact.good,
            ),
      ],
    ),
  );
  await s.runs.setState(
    run.id,
    RunState.finished,
    endedAt: start.add(Duration(seconds: seconds)),
    endedUtcOffset: Duration.zero,
  );
  return run.id;
}

/// Ein Punkt je Sekunde geradeaus nach Norden mit rund 3 m/s, dazu Puls 150.
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
    d.heartRate.emitReading('hr1', d.clock.now(), 150);
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Startet einen Lauf, geht [seconds] und beendet ihn.
Future<void> runAndFinish(Device d, WidgetTester tester, int seconds) async {
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
  await walk(d, tester, seconds);
  await tester.tap(key('run_finish'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_finish_confirm'));
  await tester.pumpAndSettle();
}

/// Sitzung, deren Rohdaten sich nicht lesen lassen (Zusammenfassung fällt
/// zurück).
class _ReadFailSession implements StorageSession {
  _ReadFailSession(this.s);
  final StorageSession s;
  late final _FailingRead raw = _FailingRead(s.rawData);
  @override
  RawDataStore get rawData => raw;
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
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _FailingRead implements RawDataStore {
  _FailingRead(this.inner);
  final RawDataStore inner;
  bool fail = false;
  @override
  Future<void> append(int runId, RawBatch batch) => inner.append(runId, batch);
  @override
  Future<StoredRawData> read(int runId) => fail
      ? Future.error(const StorageException(StorageFailure.failed))
      : inner.read(runId);
}

class _ReadFailStorage implements Storage {
  _ReadFailStorage(this.inner);
  final Storage inner;
  late _ReadFailSession session;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      session = _ReadFailSession(await inner.open(key));
}

Future<void> openHistory(Device d, WidgetTester tester) async {
  await tester.tap(key('home_history'));
  await tester.pumpAndSettle();
}

Future<Device> started(WidgetTester tester, {String locale = 'de'}) async {
  final d = Device();
  await d.start(tester, Locale(locale));
  await d.skipSetup(tester);
  return d;
}

void main() {
  group('Historie (FR-0040, ACC-04)', () {
    testWidgets('leer: Hinweis statt Liste', (tester) async {
      final d = await started(tester);
      await openHistory(d, tester);
      expect(key('history_empty'), findsOneWidget);
      expect(find.text('Noch keine Läufe aufgezeichnet.'), findsOneWidget);
    });

    testWidgets('jeder Lauf mit Strecke, Dauer, Pace; ohne Puls kein 0', (
      tester,
    ) async {
      final d = await started(tester);
      final a = await seedRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        minutes: 10,
      );
      final b = await seedRun(
        d.session,
        DateTime.utc(2030, 1, 3, 8),
        minutes: 20,
        speed: 2.5,
        bpm: null,
      );
      await openHistory(d, tester);
      // 10 min mit 3 m/s: 1,80 km in 10:00, Pace 5:33 min/km.
      expect(text('history_distance_$a'), '1,80 km');
      expect(text('history_time_$a'), 'Dauer 10:00');
      expect(text('history_pace_$a'), 'Ø Pace: 5:33 min/km');
      expect(text('history_hr_$a'), 'Ø Puls 150 bpm');
      // 20 min mit 2,5 m/s: 3,00 km, Pace 6:40, kein Puls.
      expect(text('history_distance_$b'), '3,00 km');
      expect(text('history_pace_$b'), 'Ø Pace: 6:40 min/km');
      expect(text('history_hr_$b'), 'Puls: nicht verfügbar');
      expect(find.textContaining(RegExp(r'(^|\s)0 bpm')), findsNothing);
      // Neuester Start oben.
      expect(
        tester.getTopLeft(key('history_run_$b')).dy,
        lessThan(tester.getTopLeft(key('history_run_$a')).dy),
      );
    });

    testWidgets('Meilen über den gemeinsamen Formatierer', (tester) async {
      final d = await started(tester, locale: 'en');
      final a = await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await d.session.settings.set(
        SettingKeys.distanceUnit,
        'mi',
        at: d.clock.now(),
      );
      await tester.tap(key('home_settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miles'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openHistory(d, tester);
      expect(text('history_distance_$a'), '1.12 mi');
      expect(text('history_pace_$a'), matches(RegExp(r'min/mi$')));
    });

    testWidgets('viele Läufe: alle erscheinen (Liste wird gebaut)', (
      tester,
    ) async {
      final d = await started(tester);
      for (var i = 0; i < 30; i++) {
        await seedRun(d.session, DateTime.utc(2030, 1, 1 + i, 8), minutes: 2);
      }
      await openHistory(d, tester);
      final list = tester.widget<ListView>(key('history_list'));
      expect(list.semanticChildCount ?? 30, 30);
      // Alle Einträge sind nach der gebündelten Abfrage mit Strecke gefüllt.
      expect(text('history_distance_30'), '0,36 km');
    });

    testWidgets('Löschen am Eintrag: Abbrechen behält, Bestätigen löscht', (
      tester,
    ) async {
      final d = await started(tester);
      final a = await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
      final b = await seedRun(d.session, DateTime.utc(2030, 1, 2, 8));
      await openHistory(d, tester);
      await tester.tap(key('history_delete_$a'));
      await tester.pumpAndSettle();
      expect(find.text('Lauf löschen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(key('history_run_$a'), findsOneWidget);
      expect(await d.session.runs.get(a), isNotNull);

      await tester.tap(key('history_delete_$a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lauf löschen').last);
      await tester.pumpAndSettle();
      expect(key('history_run_$a'), findsNothing);
      expect(key('history_run_$b'), findsOneWidget);
      expect(await d.session.runs.get(a), isNull);
      expect(await d.session.runs.get(b), isNotNull);
    });
  });

  group('Zusammenfassung nach dem Lauf (FR-0037)', () {
    testWidgets(
      'alle Punkte; Einordnung mit Vorläufen; Fehlendes nicht als 0',
      (tester) async {
        final d = await started(tester);
        // Zwei langsamere Vorläufe (6:40 min/km).
        for (var i = 0; i < 2; i++) {
          await seedRun(
            d.session,
            DateTime.utc(2026, 5, 1 + i, 8),
            minutes: 10,
            speed: 2.5,
          );
        }
        await runAndFinish(d, tester, 400);
        expect(key('sum_loading'), findsNothing);
        expect(text('run_done_status'), 'Der Lauf ist gespeichert.');
        expect(text('run_distance'), matches(RegExp(r'^1,[12]\d km$')));
        expect(text('run_moving_time'), '6:40');
        expect(text('run_avg_pace'), matches(RegExp(r'^5:\d\d min/km$')));
        // Bestpace: schnellster zusammenhängender Kilometer.
        expect(text('sum_best_pace'), matches(RegExp(r'^5:\d\d min/km$')));
        expect(text('sum_avg_hr'), '150 bpm');
        expect(text('sum_max_hr'), '150 bpm');
        // Ohne Profil: keine Zonen, keine Belastung, mit Grund statt 0.
        expect(text('sum_zones_unavailable'), contains('nicht verfügbar'));
        expect(text('sum_trimp'), contains('nicht verfügbar'));
        // Einordnung mit Anzahl der Vorläufe (Pace, schneller).
        expect(text('sum_class'), contains('schneller'));
        expect(text('sum_class'), contains('letzten 2 Läufe'));
        // VO₂max: kein Wert, nie 0; falls einer da wäre, als Schätzung.
        expect(text('sum_vo2max'), 'nicht verfügbar');
        expect(find.text('VO₂max (Schätzung)'), findsOneWidget);
        // Route und Höhenprofil: Platzhalter (WP10 B2).
        expect(key('sum_route_later'), findsOneWidget);
        expect(key('sum_elevation_later'), findsOneWidget);
      },
    );

    testWidgets('erster Lauf, kürzer als der Bestpace-Kilometer', (
      tester,
    ) async {
      final d = await started(tester);
      await runAndFinish(d, tester, 60);
      expect(text('sum_best_pace'), contains('nicht verfügbar'));
      expect(text('sum_class'), contains('nicht verfügbar'));
      expect(text('sum_class'), contains('früheren Lauf'));
      expect(find.textContaining(RegExp(r'(^|\s)0 (bpm|km)')), findsNothing);
    });

    testWidgets('Lesefehler: Hinweis und Werte der Aufzeichnung', (
      tester,
    ) async {
      final d = Device();
      final storage = _ReadFailStorage(d.storage);
      d.storageOverride = storage;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      storage.session.raw.fail = true;
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      await walk(d, tester, 30);
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(key('sum_fallback'), findsOneWidget);
      expect(text('run_time'), '0:30');
    });
  });
}
