import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/readiness/readiness_today.dart';

import 'app_harness.dart';

// Verdrahtung der Auslöser „veränderter Erholungszustand“ in der App
// (FR-0157, FR-0158, Teil „3 (Erholung)“): Import neuer Gesundheitsdaten,
// Morgenmessung von „Heute“ und Wochenprüfung beim Öffnen von „Heute“ lockern
// bei „adaptiv“ und niedrigem Wert die harte Einheit von heute. Ziel, Plan
// und Gesundheitsreihen sind ausgedacht.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, Anlage des Plans (UTC, Versatz 0).
final _d0 = DateTime.utc(2026, 11, 11);
DateTime _day(int n) => _d0.add(Duration(days: n));

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

PlanRepository _plans(StorageSession s) => (s as PlanStorage).plans;

DateTime _at(DateTime day, int days, int h) =>
    day.add(Duration(days: days, hours: h));

/// HRV (03:00), Ruhepuls (07:00) und Schlaf (22:00 bis 06:00) für die 28
/// Tage vor [today] und heute; heute HRV niedrig, Ruhepuls hoch, kurze
/// Nacht. [first] und [last] begrenzen die Tage (relativ zu [today]).
List<HealthRecord> _records(DateTime today, {int first = -28, int last = 0}) =>
    [
      for (var day = first; day <= last; day++) ...[
        HealthRecord(
          kind: HealthDataKind.sleep,
          id: 'sleep-${day + 28}',
          origin: 'test.app',
          start: _at(today, day - 1, day == 0 ? 3 : 22),
          end: _at(today, day, 6),
        ),
        HealthRecord(
          kind: HealthDataKind.hrvRmssd,
          id: 'hrv-${day + 28}',
          origin: 'test.app',
          start: _at(today, day, 3),
          end: _at(today, day, 3),
          value: day == 0 ? 30.0 : 46.0 + ((day + 28) % 5) * 2,
          unit: 'ms',
        ),
        HealthRecord(
          kind: HealthDataKind.restingHeartRate,
          id: 'rhr-${day + 28}',
          origin: 'test.app',
          start: _at(today, day, 7),
          end: _at(today, day, 7),
          value: day == 0 ? 66.0 : 54.0 + ((day + 28) % 4),
          unit: 'bpm',
        ),
      ],
    ];

Future<void> _store(StorageSession s, List<HealthRecord> records) async {
  final h = (s as HealthStorage).health;
  await h.upsertSleep([
    for (final r in records)
      if (r.kind == HealthDataKind.sleep) r,
  ]);
  await h.upsertValues([
    for (final r in records)
      if (r.kind != HealthDataKind.sleep) r,
  ]);
}

Future<void> _consent(StorageSession s, Clock c, Set<HealthDataKind> kinds) =>
    Future.wait([
      for (final k in kinds)
        ConsentService(s.consents, c).grant(healthSourceKey(k)),
    ]);

/// Speicher vor dem Start: Einrichtung erledigt, Ziel und Plan vom Mittwoch
/// [_d0], Modus „adaptiv“; die Uhr steht um 09:00 am Tag der ersten harten
/// Einheit ab [from]. Mit [checked] ist die Wochenprüfung heute erledigt.
Future<(StorageSession, DateTime)> _preopen(
  Device d, {
  int from = 1,
  bool checked = true,
}) async {
  d.clock.set(_day(0).add(const Duration(hours: 8)));
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: d.clock.now());
  await (s as GoalStorage).goals.save(_goal(), today: _day(0));
  await recalculatePlan(
    plans: _plans(s),
    settings: s.settings,
    trigger: PlanTrigger.create,
    today: _day(0),
    now: d.clock.now(),
    inputs: PlanInputs.forNewGoal(
      _goal(),
      _day(0),
    ).copyWith(startWeeklyMinutes: 180),
    warning: (s as WarningStorage).warning,
  );
  DateTime? hard;
  for (var n = from; n < from + 28 && hard == null; n++) {
    final u = await _plans(s).unitOn(_day(n));
    if (u != null && u.isHard && recoveryEasable(u)) hard = _day(n);
  }
  d.clock.set(hard!.add(const Duration(hours: 9)));
  if (checked) {
    await s.settings.set(planLastCheckDayKey, isoDay(hard), at: d.clock.now());
  }
  await SettingsPlanAdaptationStore(s.settings)
      .set(PlanAdaptationMode.adaptive, at: d.clock.now());
  return (s, hard);
}

/// Health Connect mit Einwilligung für alles; liefert für jede Art die
/// Sätze aus [records].
class _Port implements HealthConnectPort {
  _Port(this.records);
  final List<HealthRecord> records;

  @override
  Future<HealthSdkStatus> sdkStatus() async => HealthSdkStatus.available;

  @override
  Future<Set<HealthDataKind>> grantedKinds() async =>
      HealthDataKind.values.toSet();

  @override
  Future<Set<HealthDataKind>> requestPermissions(
    Set<HealthDataKind> kinds,
  ) async => kinds;

  @override
  Future<bool> openInstall() async => true;

  @override
  Future<HealthPage> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async => HealthPage([
    for (final r in records)
      if (r.kind == kind) r,
  ], null);
}

const _allKinds = {
  HealthDataKind.hrvRmssd,
  HealthDataKind.restingHeartRate,
  HealthDataKind.sleep,
};

/// Lässt die echten Futures (Speicher, Import) laufen und baut neu.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }
}

Future<PlanUnit> _unit(WidgetTester tester, StorageSession s, DateTime day) =>
    tester.runAsync(() => _plans(s).unitOn(day)).then((u) => u!);

Future<List<PlanVersionRecord>> _history(
  WidgetTester tester,
  StorageSession s,
) => tester.runAsync(() => _plans(s).history()).then((h) => h!);

/// Kamera-Morgenmessung um 07:00 am Tag [day] (Entwicklermodus).
MorningMeasurement _cam(
  Clock clock,
  DateTime day, {
  required double bpm,
  required double rmssd,
  SleepBand? band,
  int minutes = 0,
  String model = 'M1',
}) {
  final at = day.add(Duration(hours: 7, minutes: minutes));
  return MorningMeasurement(
    measuredAt: at,
    utcOffset: clock.utcOffsetAt(at),
    posture: RestingPosture.lying,
    deviceManufacturer: 'H',
    deviceModel: model,
    method: 'ppg',
    methodVersion: 1,
    quality: PpgQuality.good,
    restingHrBpm: bpm,
    rmssdMs: rmssd,
    timingNoiseMs: 10,
    cameraIntervalsMs: const [],
    beforeValidation: false,
    outsideWindow: false,
    sleepBand: band,
  );
}

/// Morgenmessungen der Kamera an den 28 Tagen vor [today] und heute, ohne
/// Health Connect. Ohne Schlafangabe hat heute keinen Wert; mit „unter 5 h“
/// fällt er auf „erhöhte Belastung“, mit „über 8 h“ bleibt er „normal“.
/// Liefert die Kennung der heutigen Messung.
Future<int> _seedCamera(
  StorageSession s,
  Clock clock,
  DateTime today, {
  SleepBand? band,
}) async {
  final m = (s as MorningStorage).morning;
  for (var n = -28; n < 0; n++) {
    await m.add(
      _cam(
        clock,
        today.add(Duration(days: n)),
        bpm: 54.0 + ((n + 28) % 4),
        rmssd: 46.0 + ((n + 28) % 5) * 2,
      ),
    );
  }
  await SettingsDeveloperModeStore(s.settings, clock).set(true);
  return m.add(_cam(clock, today, bpm: 55, rmssd: 46, band: band));
}

/// Startet die App (Health Connect ohne neue Sätze: kein Import-Auslöser)
/// und öffnet die Detailseite der Erholung von „Heute“.
Future<void> _openDetail(WidgetTester tester, Device d) async {
  d.healthConnect = _Port(const []);
  await d.start(tester, const Locale('de'));
  await _settle(tester);
  await _tapKey(tester, 'readiness_where_from');
  expect(find.byKey(const Key('readiness_detail')), findsOneWidget);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await _settle(tester);
}

/// Wählt auf der Detailseite über „Schlaf angeben“ bzw. „ändern“ die Stufe
/// [band] und schließt das Blatt.
Future<void> _enterSleep(
  WidgetTester tester,
  SleepBand band, {
  String button = 'readiness_detail_enter_sleep',
}) async {
  await _tapKey(tester, button);
  expect(find.byKey(const Key('readiness_sleep_sheet')), findsOneWidget);
  await _tapKey(tester, 'readiness_sleep_${band.code}');
  await _tapKey(tester, 'readiness_sleep_done');
}

Future<SleepBand?> _band(WidgetTester tester, StorageSession s, int id) =>
    tester
        .runAsync((s as MorningStorage).morning.list)
        .then((l) => l!.singleWhere((e) => e.id == id).value.sleepBand);

void main() {
  test('die Reihen ergeben heute einen niedrigen Wert', () async {
    final d = Device();
    final (s, today) = await _preopen(d);
    await _store(s, _records(today));
    await _consent(s, d.clock, _allKinds);
    final snap = await loadReadinessToday(
      session: s,
      clock: d.clock,
      recalculation: RecalculationService(
        session: s,
        clock: d.clock,
        calculation: ValueCalculationService(session: s, clock: d.clock),
      ),
    );
    expect(snap?.today, today);
    expect(snap?.result.band, ReadinessBand.elevatedLoad);
  });

  group('Import neuer Gesundheitsdaten (ReadyRoot)', () {
    testWidgets('„adaptiv“, Import bringt einen niedrigen Wert: die harte '
        'Einheit von heute wird locker (feedback, Grund readiness)', (
      tester,
    ) async {
      final d = Device();
      final (s, today) = (await tester.runAsync(() async {
        final r = await _preopen(d);
        await _consent(r.$1, d.clock, _allKinds);
        return r;
      }))!;
      final hard = await _unit(tester, s, today);
      final versions = (await _history(tester, s)).length;
      d.healthConnect = _Port(_records(today));
      await d.start(tester, const Locale('de'));
      await _settle(tester);
      final history = await _history(tester, s);
      expect(history.length, greaterThan(versions));
      expect(history.last.trigger, PlanTrigger.feedback);
      expect(history.last.reason, planReasonReadiness);
      final now = await _unit(tester, s, today);
      expect(now.kind, PlanUnitKind.easy);
      expect(now.minutes, hard.minutes);
      await d.stop(tester);
    });

    testWidgets('„adaptiv“, Import ohne neue Sätze: die Einheit bleibt hart', (
      tester,
    ) async {
      final d = Device();
      final (s, today) = (await tester.runAsync(() async {
        final r = await _preopen(d);
        await _consent(r.$1, d.clock, _allKinds);
        return r;
      }))!;
      final versions = (await _history(tester, s)).length;
      d.healthConnect = _Port(const []);
      await d.start(tester, const Locale('de'));
      await _settle(tester);
      expect((await _history(tester, s)).length, versions);
      expect((await _unit(tester, s, today)).isHard, isTrue);
      await d.stop(tester);
    });
  });

  testWidgets('Morgenmessung über „Erholung“ auf „Heute“: nach dem Schließen '
      'wird die harte Einheit von heute locker', (tester) async {
    final d = Device();
    // Heute fehlen noch alle Werte; die Detailseite bietet dafür die
    // Morgenmessung an (Kamera im Entwicklermodus).
    final (s, today) = (await tester.runAsync(() async {
      final r = await _preopen(d);
      await _store(r.$1, _records(r.$2, last: -1));
      await _consent(r.$1, d.clock, _allKinds);
      await SettingsDeveloperModeStore(r.$1.settings, d.clock).set(true);
      return r;
    }))!;
    d.ppgCamera = FakePpgCamera();
    // Health Connect erreichbar, aber ohne neue Sätze: kein Auslöser.
    d.healthConnect = _Port(const []);
    await d.start(tester, const Locale('de'));
    await _settle(tester);
    // Ohne Auslöser bleibt die Einheit hart.
    expect((await _unit(tester, s, today)).isHard, isTrue);
    await tester.ensureVisible(find.byKey(const Key('readiness_where_from')));
    await tester.tap(find.byKey(const Key('readiness_where_from')));
    await _settle(tester);
    final start = find.byKey(const Key('readiness_detail_start_morning_hrv'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await _settle(tester);
    expect(
      find.byKey(const Key('readiness_detail')).hitTestable(),
      findsNothing,
    );
    expect((await _unit(tester, s, today)).isHard, isTrue);
    // Während die Messseite offen ist, kommen die Werte von heute dazu (der
    // Wert fällt); die Messseite schließen, ohne zu messen.
    await tester.runAsync(() => _store(s, _records(today, first: 0)));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _settle(tester);
    final history = await _history(tester, s);
    expect(history.last.trigger, PlanTrigger.feedback);
    expect(history.last.reason, planReasonReadiness);
    expect((await _unit(tester, s, today)).kind, PlanUnitKind.easy);
    await d.stop(tester);
  });

  testWidgets('Wochenprüfung beim Öffnen von „Heute“ (FR-0158): bei '
      '„adaptiv“ und niedrigem Wert wird die harte Einheit von heute locker', (
    tester,
  ) async {
    final d = Device();
    final (s, today) = (await tester.runAsync(() async {
      final r = await _preopen(d, checked: false);
      await _store(r.$1, _records(r.$2));
      await _consent(r.$1, d.clock, _allKinds);
      expect(
        weeklyCheckDue(await r.$1.settings.get(planLastCheckDayKey), r.$2),
        isTrue,
      );
      return r;
    }))!;
    await d.start(tester, const Locale('de'));
    await _settle(tester);
    final history = await _history(tester, s);
    expect(history.last.trigger, PlanTrigger.feedback);
    expect(history.last.reason, planReasonReadiness);
    expect((await _unit(tester, s, today)).kind, PlanUnitKind.easy);
    expect(
      await tester.runAsync(() => s.settings.get(planLastCheckDayKey)),
      isoDay(today),
    );
    await d.stop(tester);
  });
  group('Schlafangabe über „Erholung“ auf „Heute“ (PAR-164K)', () {
    testWidgets('„adaptiv“, die Stufe senkt den Wert auf „erhöhte '
        'Belastung“: die harte Einheit von heute wird locker', (tester) async {
      final d = Device();
      final (s, today, id) = (await tester.runAsync(() async {
        final r = await _preopen(d);
        final id = await _seedCamera(r.$1, d.clock, r.$2);
        return (r.$1, r.$2, id);
      }))!;
      final hard = await _unit(tester, s, today);
      final versions = (await _history(tester, s)).length;
      await _openDetail(tester, d);
      // Ohne Schlafangabe kein Wert, keine Lockerung.
      expect((await _unit(tester, s, today)).isHard, isTrue);
      expect((await _history(tester, s)).length, versions);
      await _enterSleep(tester, SleepBand.under5);
      expect(await _band(tester, s, id), SleepBand.under5);
      final history = await _history(tester, s);
      expect(history.length, versions + 1);
      expect(history.last.trigger, PlanTrigger.feedback);
      expect(history.last.reason, planReasonReadiness);
      final now = await _unit(tester, s, today);
      expect(now.kind, PlanUnitKind.easy);
      expect(now.minutes, hard.minutes);
      // Die Detailseite bleibt offen und lädt wie bisher neu.
      expect(find.byKey(const Key('readiness_detail')), findsOneWidget);
      await d.stop(tester);
    });

    testWidgets('„fix“, gleiche Stufe: der Plan bleibt unverändert', (
      tester,
    ) async {
      final d = Device();
      final (s, today, id) = (await tester.runAsync(() async {
        final r = await _preopen(d);
        await SettingsPlanAdaptationStore(r.$1.settings)
            .set(PlanAdaptationMode.fixed, at: d.clock.now());
        final id = await _seedCamera(r.$1, d.clock, r.$2);
        return (r.$1, r.$2, id);
      }))!;
      final versions = (await _history(tester, s)).length;
      await _openDetail(tester, d);
      await _enterSleep(tester, SleepBand.under5);
      expect(await _band(tester, s, id), SleepBand.under5);
      expect((await _history(tester, s)).length, versions);
      expect((await _unit(tester, s, today)).isHard, isTrue);
      await d.stop(tester);
    });

    testWidgets('„adaptiv“, die Stufe hält den Wert „normal“: die Einheit '
        'bleibt hart; danach geändert auf „unter 5 h“: locker', (tester) async {
      final d = Device();
      final (s, today, id) = (await tester.runAsync(() async {
        final r = await _preopen(d);
        final id = await _seedCamera(r.$1, d.clock, r.$2);
        return (r.$1, r.$2, id);
      }))!;
      final versions = (await _history(tester, s)).length;
      await _openDetail(tester, d);
      await _enterSleep(tester, SleepBand.over8);
      expect(await _band(tester, s, id), SleepBand.over8);
      expect((await _history(tester, s)).length, versions);
      expect((await _unit(tester, s, today)).isHard, isTrue);
      // Angabe ändern: dieselbe Prüfung läuft nach dem Ändern.
      await _enterSleep(
        tester,
        SleepBand.under5,
        button: 'readiness_detail_change_sleep',
      );
      expect(await _band(tester, s, id), SleepBand.under5);
      final history = await _history(tester, s);
      expect(history.length, versions + 1);
      expect(history.last.reason, planReasonReadiness);
      expect((await _unit(tester, s, today)).kind, PlanUnitKind.easy);
      await d.stop(tester);
    });

    testWidgets('Speichern scheitert: keine Prüfung, das Blatt meldet den '
        'Fehler wie bisher', (tester) async {
      final d = Device();
      // Heute zwei Messungen: die erste (ohne Angabe) trägt „Schlaf
      // angeben“, eine zweite von einem anderen Gerät hat schon „unter 5 h“.
      // Der Wert ist darum niedrig, aber seit dem Start lief keine Prüfung:
      // jede Prüfung würde die Einheit lockern, auch nach dem Fehler unten.
      final (s, today, id) = (await tester.runAsync(() async {
        final r = await _preopen(d);
        final id = await _seedCamera(r.$1, d.clock, r.$2);
        await (r.$1 as MorningStorage).morning.add(
          _cam(
            d.clock,
            r.$2,
            bpm: 55,
            rmssd: 46,
            band: SleepBand.under5,
            minutes: 10,
            model: 'M2',
          ),
        );
        return (r.$1, r.$2, id);
      }))!;
      final versions = (await _history(tester, s)).length;
      await _openDetail(tester, d);
      expect((await _unit(tester, s, today)).isHard, isTrue);
      await _tapKey(tester, 'readiness_detail_change_sleep');
      // Die Messung verschwindet aus dem Speicher: Speichern scheitert.
      final kept = d.storage.data.morning.remove(id)!;
      await _tapKey(tester, 'readiness_sleep_${SleepBand.over8.code}');
      expect(find.byKey(const Key('readiness_sleep_failed')), findsOneWidget);
      expect((await _history(tester, s)).length, versions);
      expect((await _unit(tester, s, today)).isHard, isTrue);
      // Gegenprobe im selben Blatt: mit der Messung zurück speichert die
      // nächste Auswahl, und die Prüfung läuft genau einmal (neue Fassung).
      d.storage.data.morning[id] = kept;
      await _tapKey(tester, 'readiness_sleep_${SleepBand.from5to6.code}');
      expect(find.byKey(const Key('readiness_sleep_failed')), findsNothing);
      await _tapKey(tester, 'readiness_sleep_done');
      expect(find.byKey(const Key('readiness_detail')), findsOneWidget);
      expect(await _band(tester, s, id), SleepBand.from5to6);
      expect((await _history(tester, s)).length, versions + 1);
      expect((await _unit(tester, s, today)).kind, PlanUnitKind.easy);
      await d.stop(tester);
    });
  });
}
