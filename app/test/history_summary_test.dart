import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

Finder key(String k) => find.byKey(Key(k));

/// Text eines Werts der Lauf-Seite; Zahl und Einheit stehen in Teilen, der
/// Wortverbinder (U+2060) ist unsichtbar.
String text(String k) {
  final w = key(k).evaluate().single.widget as Text;
  return (w.data ?? w.textSpan!.toPlainText())
      .replaceAll('\u2060', '')
      .replaceAll('\u00A0', ' ');
}

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
Future<void> walk(
  Device d,
  WidgetTester tester,
  int seconds, {
  bool heartRate = true,
}) async {
  for (var i = 0; i < seconds; i++) {
    d.clock.advance(const Duration(seconds: 1));
    d.location.emit(
      LocationSample(
        time: d.clock.now(),
        latitude: 50 + i * 0.000027,
        longitude: 8,
        accuracyMeters: 5,
        altitudeMeters: 100,
        verticalAccuracyMeters: 3,
      ),
    );
    if (heartRate) d.heartRate.emitReading('hr1', d.clock.now(), 150);
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Startet einen Lauf, geht [seconds] und beendet ihn.
Future<void> runAndFinish(
  Device d,
  WidgetTester tester,
  int seconds, {
  bool heartRate = true,
}) async {
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
  await walk(d, tester, seconds, heartRate: heartRate);
  await tester.tap(key('run_pause'));
  await tester.pump();
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

/// Hält das Schreiben des Merkers „Werte nach dem Lauf noch berechnen“ fest,
/// bis [release] kommt: die Berechnung nach dem Lauf steht dann mittendrin.
class _HoldSession extends _ReadFailSession {
  _HoldSession(super.s);
  final reached = Completer<void>();
  final release = Completer<void>();
  @override
  SettingsStore get settings => _HoldSettings(s.settings, this);
}

class _HoldSettings implements SettingsStore {
  _HoldSettings(this.inner, this.owner);
  final SettingsStore inner;
  final _HoldSession owner;
  @override
  Future<String?> get(String key) => inner.get(key);
  @override
  Future<Map<String, String>> all() => inner.all();
  @override
  Future<void> set(String key, String value, {required DateTime at}) async {
    if (key == ValueCalculationService.calculationPendingKey &&
        !owner.reached.isCompleted) {
      owner.reached.complete();
      await owner.release.future;
    }
    await inner.set(key, value, at: at);
  }
}

class _HoldStorage implements Storage {
  _HoldStorage(this.inner);
  final Storage inner;
  late _HoldSession session;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      session = _HoldSession(await inner.open(key));
}

/// Läuft [seconds] und tippt „Beenden“; die Berechnung danach hält an
/// ([session.reached]) und läuft erst mit [session.release] weiter.
Future<void> _runAndFinishHeld(
  Device d,
  WidgetTester tester,
  _HoldSession session,
  int seconds,
) async {
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
  await walk(d, tester, seconds);
  await tester.tap(key('run_pause'));
  await tester.pump();
  await tester.tap(key('run_finish'));
  await tester.pump();
  await tester.tap(key('run_finish_confirm'));
  await session.reached.future;
}

/// Wählt im Verlauf „Alle“ (letzter Abschnitt): Die Testläufe liegen im Jahr
/// 2030, die Uhr des Geräts steht 2026; ohne Läufe gibt es keinen Umschalter.
Future<void> showAllRuns(WidgetTester tester) async {
  final range = key('history_range');
  if (range.evaluate().isEmpty) return;
  await tester.tap(
    find.descendant(of: range, matching: find.byType(InkWell)).last,
  );
  await tester.pumpAndSettle();
}

Future<void> openHistory(Device d, WidgetTester tester) async {
  await tester.tap(key('home_history'));
  await tester.pumpAndSettle();
  await showAllRuns(tester);
}

Future<Device> started(WidgetTester tester, {String locale = 'de'}) async {
  final d = Device();
  await d.start(tester, Locale(locale));
  await d.skipSetup(tester);
  return d;
}

final historyList = find.byWidgetPredicate(
  (w) =>
      w is ListView &&
      w.key is PageStorageKey<(StorageSession, String)> &&
      (w.key! as PageStorageKey<(StorageSession, String)>).value.$2.startsWith(
        'history_list',
      ),
);

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
      expect(text('history_time_$a'), '10:00');
      expect(text('history_pace_$a'), '5:33 min/km');
      expect(text('history_hr_$a'), 'Ø Puls 150 bpm');
      // 20 min mit 2,5 m/s: 3,00 km, Pace 6:40, kein Puls.
      expect(text('history_distance_$b'), '3,00 km');
      expect(text('history_pace_$b'), '6:40 min/km');
      expect(text('history_hr_$b'), 'Puls: nicht verfügbar');
      expect(find.textContaining(RegExp(r'(^|\s)0 bpm')), findsNothing);
      // Neuester Start oben.
      expect(
        tester.getTopLeft(key('history_run_$b')).dy,
        lessThan(tester.getTopLeft(key('history_run_$a')).dy),
      );
    });

    testWidgets('Lauf ohne Dauer: nicht verfügbar statt Strich', (
      tester,
    ) async {
      final d = await started(tester);
      final a = await seedRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        minutes: 0,
        bpm: null,
      );
      await openHistory(d, tester);
      expect(text('history_time_$a'), 'nicht verfügbar');
      expect(find.text('–'), findsNothing);
    });

    testWidgets('Lesefehler eines Laufs: Historie bleibt, Lauf mit Hinweis', (
      tester,
    ) async {
      final d = Device();
      final storage = _ReadFailStorage(d.storage);
      d.storageOverride = storage;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      final a = await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
      final b = await seedRun(d.session, DateTime.utc(2030, 1, 2, 8));
      storage.session.raw.fail = true;
      await openHistory(d, tester);
      expect(key('history_error'), findsNothing);
      expect(key('history_run_$a'), findsOneWidget);
      expect(key('history_run_$b'), findsOneWidget);
      expect(
        find.text('Die Daten dieses Laufs konnten nicht gelesen werden.'),
        findsNWidgets(2),
      );
    });

    testWidgets('große Schrift (2,0): keine Überläufe', (tester) async {
      final d = await started(tester);
      await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await seedRun(d.session, DateTime.utc(2030, 1, 2, 8), bpm: null);
      tester.view.physicalSize = const Size(411, 914);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHistory(d, tester);
      expect(historyList, findsOneWidget);
      expect(find.textContaining(RegExp(r'min.*km')), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Meilen über den gemeinsamen Formatierer', (tester) async {
      final d = await started(tester, locale: 'en');
      final a = await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
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
      // Titel, Umschalter, Summen und Wochenköpfe stehen mit in der Liste.
      final list = tester.widget<ListView>(historyList);
      expect(list.semanticChildCount ?? 30, greaterThanOrEqualTo(30));
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
    testWidgets('Hinweis „gespeichert“ hat Abstand wie zwischen den Blöcken', (
      tester,
    ) async {
      final d = await started(tester);
      await runAndFinish(d, tester, 400);
      Rect card(String id) => tester.getRect(
        find.ancestor(of: key(id), matching: find.byType(RamuriCard)).first,
      );
      final banner = tester.getRect(
        find
            .descendant(
              of: find.ancestor(
                of: key('run_done_status'),
                matching: find.byType(Card),
              ),
              matching: find.byType(Material),
            )
            .first,
      );
      final hero = card('run_distance');
      final firstTile = card('run_avg_pace');
      final between = firstTile.top - hero.bottom;
      expect(between, 16, reason: 'Abstand zwischen den Blöcken');
      expect(hero.top - banner.bottom, between, reason: 'Hinweis und Kopf');
    });

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
        expect(text('run_avg_pace'), matches(RegExp(r'^5:\d\d$')));
        // Bestpace: schnellster zusammenhängender Kilometer.
        expect(text('sum_best_pace'), matches(RegExp(r'^5:\d\d$')));
        expect(text('sum_avg_hr'), '150');
        expect(text('sum_max_hr'), '150');
        // Ohne Profil: keine Zonen, keine Belastung, mit Grund statt 0.
        // Mit Puls, aber ohne Werte im Profil: der Grund ist das Profil (FR-0057).
        expect(
          text('sum_zones_unavailable'),
          'nicht verfügbar – Pulswerte im Profil prüfen',
        );
        expect(
          text('sum_trimp'),
          'nicht verfügbar\nPulswerte im Profil prüfen',
        );
        // Einordnung mit Anzahl der Vorläufe (Pace, schneller).
        expect(text('sum_class'), contains('schneller'));
        expect(text('sum_class'), contains('letzten 2 Läufe'));
        // VO₂max: kein Wert, nie 0; falls einer da wäre, als Schätzung.
        expect(text('sum_vo2max'), 'nicht verfügbar');
        expect(find.text('VO₂max (Schätzung)'), findsOneWidget);
        // Route und Diagramme sind gezeichnet (WP10 B2).
        expect(
          key('sum_altitude').evaluate().length +
              key('sum_altitude_none').evaluate().length,
          1,
        );
        expect(key('route_paint'), findsOneWidget);
      },
    );

    testWidgets('ohne Pulssensor: Puls, Zonen, Belastung nicht verfügbar', (
      tester,
    ) async {
      final d = await started(tester);
      await runAndFinish(d, tester, 120, heartRate: false);
      expect(text('sum_avg_hr'), 'nicht verfügbar\n(kein Puls)');
      expect(text('sum_max_hr'), 'nicht verfügbar\n(kein Puls)');
      // Ohne Puls ist der Puls der Grund, nicht das Profil (FR-0057).
      expect(text('sum_zones_unavailable'), 'nicht verfügbar (kein Puls)');
      expect(text('sum_trimp'), 'nicht verfügbar\n(kein Puls)');
      expect(find.textContaining(RegExp(r'(^|\s)0 bpm')), findsNothing);
      expect(text('run_distance'), isNot(contains('nicht')));
    });

    testWidgets('Fertig ändert keine Daten; Details öffnet die Detailansicht', (
      tester,
    ) async {
      final d = await started(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await runAndFinish(d, tester, 120);
      // Beide Knöpfe sind erreichbar und mindestens 48 dp hoch.
      for (final k in ['run_done_close', 'run_done_details']) {
        expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48));
      }
      expect(find.text('Fertig'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);

      // Details: Detailansicht desselben Laufs, Zurück zur Zusammenfassung.
      await tester.tap(key('run_done_details'));
      await tester.pumpAndSettle();
      expect(key('detail_compare'), findsOneWidget);
      // Deutsch: pageBack sucht den englischen Tooltip.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(key('run_done_close'), findsOneWidget);

      // Fertig: Speicher davor und danach gleich.
      final before = await _storeSnapshot(d);
      await tester.tap(key('run_done_close'));
      await tester.pumpAndSettle();
      expect(key('home_start_run'), findsOneWidget);
      expect(await _storeSnapshot(d), before);
      expect(before, isNot(contains('runs=0')));
    });

    testWidgets('große Schrift (2,0): Zusammenfassung ohne Überlauf', (
      tester,
    ) async {
      final d = await started(tester);
      tester.view.physicalSize = const Size(411, 914);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await runAndFinish(d, tester, 120);
      expect(key('sum_avg_hr'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zusammenfassung erst nach der Berechnung: Laden, dann VO2max', (
      tester,
    ) async {
      final d = Device();
      final storage = _HoldStorage(d.storage);
      d.storageOverride = storage;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      await d.session.profile.save(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
      );
      await _runAndFinishHeld(d, tester, storage.session, 1800);
      // Während der Berechnung: Ladeanzeige, noch keine Zusammenfassung.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(key('sum_loading'), findsOneWidget);
      expect(key('sum_avg_hr'), findsNothing);
      storage.session.release.complete();
      await tester.pumpAndSettle();
      expect(key('sum_loading'), findsNothing);
      // Der Laufwert liegt vor und steht als Schätzung in der Zusammenfassung.
      expect(
        text('sum_vo2max'),
        matches(RegExp(r'^\d+,\d ml/kg/min \(Schätzung\)$')),
      );
      expect(text('sum_avg_hr'), '150');
    });

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
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 30);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(key('sum_fallback'), findsOneWidget);
      expect(text('run_time'), '0:30');
    });
  });
}

/// Läufe, Rohdaten, Runden und gespeicherte Werte als Text zum Vergleichen.
Future<String> _storeSnapshot(Device d) async {
  final s = d.session;
  final runs = await s.runs.list();
  final out = StringBuffer('runs=${runs.length}')
    ..write(
      ' settings=${(await s.settings.all()).entries.map((e) => '${e.key}=${e.value}').toList()..sort()}',
    );
  for (final r in runs) {
    final raw = await s.rawData.read(r.id);
    final values = await s.values.read(ValueOwner.run(r.id));
    out
      ..write(' [${r.id} ${r.state} ${r.startedAt} ${r.endedAt}')
      ..write(' pos=${raw.positions.length} hr=${raw.heartRates.length}')
      ..write(' laps=${(await s.markers.laps(r.id)).length}')
      ..write(
        ' values=${[for (final v in values) '${v.original.key}=${v.current.value}']}]',
      );
  }
  return out.toString();
}
