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
}
