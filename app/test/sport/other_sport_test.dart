// Andere Sportart mit Puls (FR-0221): Start ohne Standort, Sperre ohne
// Pulssensor mit Nachtrag, Live-Ansicht ohne Laufwerte, Zusammenfassung,
// Verlauf und Detail, Hinweise und Wiederanlauf. Nur synthetische Werte.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/manual_training_screen.dart';
import 'package:running_app/features/run/live_run_view.dart';
import 'package:running_app/features/run/other_sport.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/run/run_ports.dart';
import 'package:running_app/ui/format/unit_format.dart';
import 'package:running_app/features/summary/run_charts.dart';
import 'package:running_app/features/summary/subjective_section.dart';
import 'package:running_app/ui/ui.dart';

import '../app_harness.dart';
import '../history_summary_test.dart' show ReadFailStorage, openHistory, text;
import '../run_detail_page_test.dart' show pumpDetail;

bool goEnabled(WidgetTester tester) =>
    tester.widget<RamuriStartButton>(key('run_start_ready')).onPressed != null;

RunController liveController(WidgetTester tester) =>
    tester.widget<LiveRunView>(find.byType(LiveRunView)).controller;

bool chipSelected(WidgetTester tester, OtherSport s) =>
    tester.widget<ChoiceChip>(key('other_sport_${s.wire}')).selected;

/// App mit Dienst, Puls über die Sensorverwaltung; [sensor]: Gurt `h1`
/// verbunden.
Future<Device> launch(
  WidgetTester tester, {
  bool sensor = true,
  Device? device,
}) async {
  final d = device ?? (Device()..recordingService = FakeRecordingServicePort());
  d.runViaSensors = true;
  await d.start(tester, const Locale('de'));
  if (key('setup_skip').evaluate().isNotEmpty) await d.skipSetup(tester);
  if (sensor) {
    await d.sensors.connect('h1', name: 'Gurt h1');
    await tester.pump();
  }
  return d;
}

Future<void> openStart(WidgetTester tester) async {
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
}

Future<void> chooseSport(WidgetTester tester, [OtherSport? s]) async {
  await tester.tap(key('treadmill_mode_sport'));
  await tester.pumpAndSettle();
  if (s != null) {
    await tester.ensureVisible(key('other_sport_${s.wire}'));
    await tester.tap(key('other_sport_${s.wire}'));
    await tester.pumpAndSettle();
  }
}

Future<void> go(WidgetTester tester) async {
  await tester.ensureVisible(key('run_start_ready'));
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
}

/// [seconds] Sekunden mit einem Pulswert je Sekunde von `h1`.
Future<void> beat(
  Device d,
  WidgetTester tester,
  int seconds, {
  int bpm = 150,
}) async {
  for (var i = 0; i < seconds; i++) {
    d.clock.advance(const Duration(seconds: 1));
    d.sensorFake.emitReading('h1', d.clock.now(), bpm);
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> finish(WidgetTester tester) async {
  await tester.tap(key('run_pause'));
  await tester.pump();
  await tester.tap(key('run_finish'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_finish_confirm'));
  await tester.pumpAndSettle();
}

/// Beendete Einheit [sport] mit Puls, ohne Positionen.
Future<int> seedSport(
  StorageSession s,
  DateTime start,
  OtherSport sport, {
  int seconds = 600,
}) async {
  final run = await s.runs.create(
    startedAt: start,
    mode: RunMode.sport,
    sport: sport,
  );
  await s.rawData.append(
    run.id,
    RawBatch(
      heartRates: [
        for (var i = 0; i <= seconds; i++)
          RawHeartRate(
            time: start.add(Duration(seconds: i)),
            source: 'strap',
            bpm: 140 + i % 10,
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

const _mi = UnitFormatter(
  unit: DistanceUnit.miles,
  languageCode: 'de',
  distanceLabel: 'mi',
  paceLabel: 'min/mi',
  elevationLabel: 'ft',
);

/// Kein Laufwert der Live-Ansicht ist zu sehen.
void expectNoRunValues() {
  for (final k in [
    'run_pace',
    'run_avg_pace',
    'run_distance',
    'run_ascent',
    'run_cadence',
    'run_laps',
    'run_lap',
    'run_pages',
    'run_gps',
    'live_chip_gps',
  ]) {
    expect(key(k), findsNothing, reason: k);
  }
}

void main() {
  group('Start einer anderen Sportart (FR-0221)', () {
    testWidgets('ohne Standortrecht: Start mit Dienst sport, ohne Standort, '
        'Schrittzähler und Kadenzrecht', (tester) async {
      final asked = <bool>[];
      final service = FakeRecordingServicePort();
      final d = Device()
        ..recordingService = service
        ..requestActivityRecognition = (t) async => asked.add(t);
      d.locationAccess
        ..current = LocationAccess.denied
        ..gps = false;
      await launch(tester, device: d);
      await openStart(tester);
      expect(key('run_block_permissionDenied'), findsOneWidget);
      await chooseSport(tester, OtherSport.rowing);
      expect(key('run_block_permissionDenied'), findsNothing);
      // Bei der Sportart entfallen GPS, Kadenz, Autopause, Führung, Ansagen.
      for (final k in [
        'start_gps_searching',
        'start_gps_good',
        'start_gps_blocked',
        'start_cadence_source',
        'start_autopause',
        'guided_toggle',
        'guided_voice',
      ]) {
        expect(key(k), findsNothing, reason: k);
      }
      expect(text('other_sport_chest_hint'), contains('Brustgurt empfohlen'));
      expect(goEnabled(tester), isTrue);
      await go(tester);
      expect(find.byType(LiveRunView), findsOneWidget);
      expect(d.locationAccess.requestCount, 0);
      expect(d.location.hasListeners, isFalse);
      expect(asked, isEmpty);
      expect(service.startModes, [RecordingServiceMode.sport]);
      final c = liveController(tester);
      expect(c.snapshot.mode, RunMode.sport);
      expect(c.runSport, OtherSport.rowing);
      final run = (await d.session.runs.list()).single;
      expect(run.mode, RunMode.sport);
      expect(run.sport, OtherSport.rowing);
    });

    testWidgets('Art und Sportart bleiben nach Neustart der App gewählt', (
      tester,
    ) async {
      final d = await launch(tester);
      await openStart(tester);
      expect(key('other_sport_card'), findsNothing);
      await chooseSport(tester, OtherSport.cycling);
      await d.stop(tester);
      await launch(tester, device: d);
      await openStart(tester);
      expect(key('other_sport_card'), findsOneWidget);
      expect(chipSelected(tester, OtherSport.cycling), isTrue);
      expect(chipSelected(tester, OtherSport.rope), isFalse);
      expect(
        await d.session.settings.get(otherSportSettingKey),
        OtherSport.cycling.wire,
      );
    });

    testWidgets('ohne Pulssensor: Los gesperrt, Grund, Nachtrag mit Sonstiges; '
        'mit Sensor frei', (tester) async {
      final d = await launch(tester, sensor: false);
      await openStart(tester);
      await chooseSport(tester);
      expect(goEnabled(tester), isFalse);
      expect(text('other_sport_needs_sensor'), contains('Pulssensor'));
      expect(find.text('Nötig für diese Sportart'), findsOneWidget);
      await tester.ensureVisible(key('other_sport_manual_entry'));
      await tester.tap(key('other_sport_manual_entry'));
      await tester.pumpAndSettle();
      expect(find.byType(ManualTrainingScreen), findsOneWidget);
      expect(
        tester.widget<SubjectiveChoice>(key('manual_kind_other')).selected,
        isTrue,
      );
      expect(
        tester.widget<SubjectiveChoice>(key('manual_kind_run')).selected,
        isFalse,
      );
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      // Sensor verbindet: die Sperre fällt ohne Neuladen der Seite.
      await d.sensors.connect('h1', name: 'Gurt h1');
      await tester.pumpAndSettle();
      expect(key('other_sport_needs_sensor'), findsNothing);
      expect(goEnabled(tester), isTrue);
    });

    testWidgets('Lauf ohne Sensor bleibt frei startbar', (tester) async {
      await launch(tester, sensor: false);
      await openStart(tester);
      expect(goEnabled(tester), isTrue);
      expect(key('other_sport_needs_sensor'), findsNothing);
    });
  });

  group('Live-Ansicht der anderen Sportart (FR-0221, PAR-232)', () {
    testWidgets('Zeit, Bewegungszeit, Puls, Bereich; keine Laufwerte; Pause '
        'hält die Bewegungszeit an', (tester) async {
      final d = await launch(tester);
      await openStart(tester);
      await chooseSport(tester, OtherSport.rope);
      await go(tester);
      await beat(d, tester, 10);
      expectNoRunValues();
      expect(text('live_other_sport'), 'Seilspringen');
      expect(key('run_time'), findsOneWidget);
      expect(key('run_hr'), findsOneWidget);
      expect(key('run_pause'), findsOneWidget);
      final c = liveController(tester);
      final moving = c.snapshot.movingTime!;
      expect(moving, greaterThan(Duration.zero));
      await tester.tap(key('run_pause'));
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        d.clock.advance(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(c.snapshot.movingTime, moving);
      expect(c.snapshot.totalTime, greaterThan(moving));
      expect(key('run_finish'), findsOneWidget);
      expectNoRunValues();
    });

    testWidgets('Pulsverlust: Hinweis wie beim Lauf, Aufzeichnung läuft', (
      tester,
    ) async {
      final d = await launch(tester);
      await openStart(tester);
      await chooseSport(tester);
      await go(tester);
      await beat(d, tester, 5);
      await d.sensorFake.drop('h1');
      await tester.pump();
      expect(key('run_sensor_loss'), findsOneWidget);
      expect(
        text('run_sensor_status'),
        contains('Sensor abgebrochen, die App verbindet neu'),
      );
      for (var i = 0; i < 4; i++) {
        d.clock.advance(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      final c = liveController(tester);
      expect(c.phase, RecordingPhase.running);
      expect(c.snapshot.totalTime, greaterThanOrEqualTo(Duration(seconds: 9)));
      await d.stop(tester);
    });
  });

  group('Nach dem Beenden (FR-0221, FR-0092)', () {
    testWidgets('RPE gefragt; Zusammenfassung mit Dauer, Bewegungszeit, Puls, '
        'Zonen und TRIMP, ohne Laufwerte; Hinweis Wade bei der 1.', (
      tester,
    ) async {
      final d = await launch(tester);
      await d.session.profile.save(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
      );
      await openStart(tester);
      await chooseSport(tester, OtherSport.rope);
      expect(key('other_sport_rope_hint'), findsOneWidget);
      await go(tester);
      await beat(d, tester, 300);
      await finish(tester);
      expect(key('subjective_rpe_label'), findsOneWidget);
      expect(key('sum_other_sport'), findsOneWidget);
      expect(text('sum_other_sport_name'), 'Seilspringen');
      expect(text('run_time'), isNot(contains('nicht')));
      expect(text('run_moving_time'), isNot(contains('nicht')));
      expect(text('sum_avg_hr'), '150');
      expect(text('sum_max_hr'), '150');
      expect(key('sum_zones'), findsOneWidget);
      expect(text('sum_trimp'), matches(RegExp(r'^\d+$')));
      for (final k in [
        'run_distance',
        'run_avg_pace',
        'sum_best_pace',
        'run_ascent',
        'run_descent',
        'sum_class',
        'sum_vo2max',
        'run_laps',
        'route_paint',
        'sum_altitude',
        'sum_altitude_none',
        'sum_other_sport_underestimated',
        'detail_route_none',
      ]) {
        expect(key(k), findsNothing, reason: k);
      }
      expect(find.byType(RunRouteSection), findsNothing);
      expect(key('sum_other_sport_rope_hint'), findsOneWidget);
    });

    testWidgets('Wiederanlauf setzt mit gleicher Sportart fort (FR-0193)', (
      tester,
    ) async {
      final d = await launch(tester, sensor: false);
      await d.session.runs.create(
        startedAt: d.clock.now(),
        mode: RunMode.sport,
        sport: OtherSport.rowing,
      );
      await d.stop(tester);
      final service = FakeRecordingServicePort();
      d.recordingService = service;
      await launch(tester, device: d, sensor: false);
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveRunView), findsOneWidget);
      final c = liveController(tester);
      expect(c.runMode, RunMode.sport);
      expect(c.runSport, OtherSport.rowing);
      expect(text('live_other_sport'), 'Rudern/Ergometer');
      expect(service.startModes, [RecordingServiceMode.sport]);
      expectNoRunValues();
    });

    testWidgets('Rad: Zusammenfassung mit Hinweis Unterschätzung, ohne Wade', (
      tester,
    ) async {
      final d = await launch(tester);
      await openStart(tester);
      await chooseSport(tester, OtherSport.cycling);
      await go(tester);
      await beat(d, tester, 60);
      await finish(tester);
      expect(text('sum_other_sport_name'), 'Radfahren');
      expect(key('sum_other_sport_underestimated'), findsOneWidget);
      expect(key('sum_other_sport_rope_hint'), findsNothing);
      expectNoRunValues();
    });

    testWidgets('Lesefehler: Werte der Aufzeichnung ohne Laufwerte', (
      tester,
    ) async {
      final d = Device()..recordingService = FakeRecordingServicePort();
      final storage = ReadFailStorage(d.storage);
      d.storageOverride = storage;
      await launch(tester, device: d);
      storage.session.raw.fail = true;
      await openStart(tester);
      await chooseSport(tester);
      await go(tester);
      await beat(d, tester, 30);
      await finish(tester);
      expect(key('sum_fallback'), findsOneWidget);
      expect(text('run_time'), '0:30');
      expect(key('run_moving_time'), findsOneWidget);
      expectNoRunValues();
    });
  });

  group('Hinweis Wade/Achillessehne (FR-0221)', () {
    testWidgets('Start: bei 0 bis 2 beendeten Einheiten ja, ab 3 nein; nur '
        'beim Seilspringen', (tester) async {
      final d = await launch(tester);
      for (var n = 0; n < 4; n++) {
        if (n > 0) {
          await seedSport(
            d.session,
            DateTime.utc(2026, 5, n, 8),
            OtherSport.rope,
          );
        }
        await openStart(tester);
        await chooseSport(tester, OtherSport.rope);
        expect(
          key('other_sport_rope_hint'),
          n < 3 ? findsOneWidget : findsNothing,
          reason: '$n gespeichert',
        );
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Start: andere Sportarten zählen nicht, kein Hinweis außer '
        'beim Seilspringen', (tester) async {
      final d = await launch(tester);
      for (var n = 1; n <= 3; n++) {
        await seedSport(
          d.session,
          DateTime.utc(2026, 5, n, 8),
          OtherSport.cycling,
        );
      }
      await openStart(tester);
      await chooseSport(tester, OtherSport.cycling);
      expect(key('other_sport_rope_hint'), findsNothing);
      await tester.tap(key('other_sport_rope'));
      await tester.pumpAndSettle();
      expect(key('other_sport_rope_hint'), findsOneWidget);
    });

    test(
      'Zusammenfassung: Rang 1 bis 3 ja, 4 nein; Lesefehler zeigt',
      () async {
        final storage = FakeStorage();
        final s = await storage.open(Uint8List.fromList(List.filled(32, 1)));
        final ids = <int>[];
        // Reihenfolge nach Beginn, nicht nach Nummer.
        for (final day in [4, 1, 3, 2]) {
          ids.add(
            await seedSport(s, DateTime.utc(2026, 5, day, 8), OtherSport.rope),
          );
        }
        await seedSport(s, DateTime.utc(2026, 4, 1, 8), OtherSport.rowing);
        expect(await ropeHintForRun(s.runs, ids[1]), isTrue); // 1. Mai
        expect(await ropeHintForRun(s.runs, ids[3]), isTrue); // 2. Mai
        expect(await ropeHintForRun(s.runs, ids[2]), isTrue); // 3. Mai
        expect(await ropeHintForRun(s.runs, ids[0]), isFalse); // 4. Mai
        expect(await ropeHintBeforeStart(s.runs), isFalse);
        expect(await ropeHintForRun(_FailingRuns(), 1), isTrue);
        expect(await ropeHintBeforeStart(_FailingRuns()), isTrue);
      },
    );
  });

  group('Verlauf und Detail (FR-0221)', () {
    testWidgets('Verlauf: Symbol und Name statt Strecke und Pace, keine '
        'Miniatur', (tester) async {
      final d = await launch(tester);
      final id = await seedSport(
        d.session,
        DateTime.utc(2026, 5, 20, 8),
        OtherSport.cycling,
      );
      await openHistory(d, tester);
      expect(key('history_sport_$id'), findsOneWidget);
      expect(
        find.descendant(
          of: key('history_sport_$id'),
          matching: find.text('Radfahren'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('history_sport_$id'),
          matching: find.byIcon(Icons.directions_bike),
        ),
        findsOneWidget,
      );
      expect(key('history_distance_$id'), findsNothing);
      expect(key('history_pace_$id'), findsNothing);
      expect(key('history_miniature_$id'), findsNothing);
      expect(key('history_time_$id'), findsOneWidget);
    });

    for (final sport in OtherSport.values) {
      for (final miles in [false, true]) {
        testWidgets('Detail ${sport.wire}${miles ? ' (Meilen)' : ''}: ohne '
            'Karte, Splits, VO₂max, Pace; Unterschätzung nur Rad und '
            'Rudern', (tester) async {
          final d = await launch(tester, sensor: false);
          final id = await seedSport(
            d.session,
            DateTime.utc(2026, 5, 20, 8),
            sport,
          );
          if (miles) {
            await pumpDetail(tester, d, id, formatter: _mi);
          } else {
            await pumpDetail(tester, d, id);
          }
          expect(key('sum_other_sport'), findsOneWidget);
          for (final k in [
            'route_paint',
            'run_distance',
            'detail_km_none',
            'detail_km_index_1',
            'detail_altitude',
            'detail_altitude_none',
            'detail_compare',
            'detail_pace',
            'detail_pace_none',
            'sum_vo2max',
            'sum_class',
            'run_avg_pace',
            'sum_best_pace',
            'run_laps',
            // Wade/Achillessehne nur bei Start und Zusammenfassung.
            'sum_other_sport_rope_hint',
          ]) {
            expect(key(k), findsNothing, reason: k);
          }
          expect(key('detail_hr'), findsOneWidget);
          expect(key('sum_trimp'), findsOneWidget);
          expect(
            key('sum_other_sport_underestimated'),
            sport == OtherSport.cycling || sport == OtherSport.rowing
                ? findsOneWidget
                : findsNothing,
          );
          expect(find.textContaining(RegExp(r'\bmi\b')), findsNothing);
          expect(find.textContaining('min/'), findsNothing);
        });
      }
    }
  });
}

class _FailingRuns implements RunStore {
  @override
  Future<List<StoredRun>> list() async => throw StateError('lesen');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
