import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_goals.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:test/test.dart';

PlanUnit _unit(DateTime day, PlanUnitKind kind, {int? runId}) => PlanUnit(
  day: day,
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: kind == PlanUnitKind.rest ? 0 : 45,
  segments: const [],
  runId: runId,
);

DateTime _d(int m, int d) => DateTime.utc(2026, m, d);

const _on = ReminderSettings(enabled: true);

/// Nur [unitsBetween] wird gebraucht.
class _Plans implements PlanRepository {
  _Plans(this.units);
  final List<PlanUnit> units;
  final asked = <(DateTime, DateTime)>[];

  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) async {
    asked.add((from, to));
    return [
      for (final u in units)
        if (!u.day.isBefore(from) && !u.day.isAfter(to)) u,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Texts implements ReminderTexts {
  @override
  String get channelName => 'Erinnerungen';
  @override
  String title(TrainingReminder r) => 'Geplantes Training';
  @override
  String body(TrainingReminder r) => '${r.kind.name} ${r.trainingAt.hour}';
}

TrainingGoal _goal(DateTime? target) => TrainingGoal(
  type: target == null ? GoalType.open : GoalType.distance,
  distance: target == null ? null : GoalDistance.tenKilometers,
  targetDate: target,
  runDays: const {1, 3, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

void main() {
  // Ortszeit: Montag, 9. November 2026, 08:00.
  final now = DateTime(2026, 11, 9, 8);

  group('planTrainingReminders (FR-0174)', () {
    test('Tag der Einheit zur Trainingszeit minus Vorlauf, sortiert', () {
      final r = planTrainingReminders(
        units: [
          _unit(_d(11, 12), PlanUnitKind.long),
          _unit(_d(11, 10), PlanUnitKind.easy),
        ],
        settings: const ReminderSettings(
          enabled: true,
          minuteOfDay: 18 * 60 + 15,
          leadMinutes: 60,
        ),
        now: now,
      );
      expect(
        [for (final x in r) x.at],
        [DateTime(2026, 11, 10, 17, 15), DateTime(2026, 11, 12, 17, 15)],
      );
      expect(
        [for (final x in r) x.trainingAt],
        [DateTime(2026, 11, 10, 18, 15), DateTime(2026, 11, 12, 18, 15)],
      );
      expect(
        [for (final x in r) x.kind],
        [PlanUnitKind.easy, PlanUnitKind.long],
      );
    });

    test('Vorlauf 15, 30 und 60 Minuten', () {
      for (final lead in ReminderSettings.leadOptions) {
        final r = planTrainingReminders(
          units: [_unit(_d(11, 10), PlanUnitKind.tempo)],
          settings: ReminderSettings(enabled: true, leadMinutes: lead),
          now: now,
        );
        expect(
          r.single.at,
          DateTime(2026, 11, 10, 18).subtract(Duration(minutes: lead)),
        );
      }
    });

    test('Ruhetage (auch festgelegte) bekommen keine Erinnerung', () {
      final r = planTrainingReminders(
        units: [
          _unit(_d(11, 10), PlanUnitKind.rest),
          _unit(_d(11, 11), PlanUnitKind.easy),
          PlanUnit(
            day: _d(11, 12),
            kind: PlanUnitKind.rest,
            phase: PlanPhase.build,
            weekIndex: 0,
            minutes: 0,
            segments: const [],
            pinned: true,
            fixed: PlanUnitFixed.day,
          ),
        ],
        settings: _on,
        now: now,
      );
      expect([for (final x in r) x.day], [_d(11, 11)]);
    });

    test('nach dem Ende des Plans (Zieldatum) keine Erinnerung', () {
      final r = planTrainingReminders(
        units: [
          _unit(_d(11, 10), PlanUnitKind.easy),
          _unit(_d(11, 14), PlanUnitKind.long),
          _unit(_d(11, 15), PlanUnitKind.easy),
        ],
        settings: _on,
        now: now,
        planEnd: _d(11, 14),
      );
      expect([for (final x in r) x.day], [_d(11, 10), _d(11, 14)]);
    });

    test('vergangener Zeitpunkt, erledigte Einheit und aus: keine', () {
      final units = [
        _unit(_d(11, 8), PlanUnitKind.easy),
        _unit(_d(11, 9), PlanUnitKind.easy),
        _unit(_d(11, 10), PlanUnitKind.easy, runId: 7),
      ];
      // Heute 17:31: die Erinnerung um 17:30 ist vorbei.
      expect(
        planTrainingReminders(
          units: units,
          settings: _on,
          now: DateTime(2026, 11, 9, 17, 31),
        ),
        isEmpty,
      );
      // Heute 17:29: die Erinnerung von heute kommt noch.
      expect(
        planTrainingReminders(
          units: units,
          settings: _on,
          now: DateTime(2026, 11, 9, 17, 29),
        ).single.day,
        _d(11, 9),
      );
      expect(
        planTrainingReminders(
          units: [_unit(_d(11, 10), PlanUnitKind.easy)],
          settings: const ReminderSettings(),
          now: now,
        ),
        isEmpty,
      );
    });

    test('Fenster: höchstens reminderHorizonDays voraus', () {
      final r = planTrainingReminders(
        units: [
          _unit(_d(11, 9).add(const Duration(days: 60)), PlanUnitKind.easy),
          _unit(_d(11, 9).add(const Duration(days: 61)), PlanUnitKind.easy),
        ],
        settings: _on,
        now: now,
      );
      expect(r, hasLength(1));
    });
  });

  group('ReminderSettings', () {
    test('Vorschläge ohne Eintrag: aus, 18:00, 30 Minuten', () async {
      final store = FakeSettingsStore(FakeStorageData());
      expect(await ReminderSettings.load(store), const ReminderSettings());
      expect(const ReminderSettings().minuteOfDay, 18 * 60);
      expect(const ReminderSettings().leadMinutes, 30);
    });

    test(
      'speichern und laden; unlesbare Werte ergeben die Vorschläge',
      () async {
        final store = FakeSettingsStore(FakeStorageData());
        const s = ReminderSettings(
          enabled: true,
          minuteOfDay: 6 * 60 + 5,
          leadMinutes: 15,
        );
        await s.save(store, at: DateTime.utc(2026, 11, 9));
        expect(await store.get(SettingKeys.reminderTime), '06:05');
        expect(await ReminderSettings.load(store), s);
        await store.set(
          SettingKeys.reminderTime,
          '24:00',
          at: DateTime.utc(2026),
        );
        await store.set(
          SettingKeys.reminderLeadMinutes,
          '45',
          at: DateTime.utc(2026),
        );
        expect(
          await ReminderSettings.load(store),
          const ReminderSettings(enabled: true),
        );
      },
    );

    test(
      'Erinnerungen sind kein technischer Merker: sie kommen ins Archiv',
      () {
        for (final k in [
          SettingKeys.reminderEnabled,
          SettingKeys.reminderTime,
          SettingKeys.reminderLeadMinutes,
        ]) {
          expect(archiveExcludedSettingKeys, isNot(contains(k)));
        }
      },
    );
  });

  group('syncTrainingReminders', () {
    late FakeStorageData data;
    late FakeSettingsStore settings;
    late FakeReminderScheduler scheduler;
    late _Plans plans;

    setUp(() {
      data = FakeStorageData()..goal = _goal(DateTime.utc(2027, 6, 1));
      settings = FakeSettingsStore(data);
      scheduler = FakeReminderScheduler(granted: true);
      plans = _Plans([
        _unit(_d(11, 10), PlanUnitKind.intervals),
        _unit(_d(11, 11), PlanUnitKind.rest),
        _unit(_d(11, 12), PlanUnitKind.long),
      ]);
    });

    Future<ReminderSyncResult> sync() => syncTrainingReminders(
      settings: settings,
      goals: FakeGoalStore(data),
      plans: plans,
      scheduler: scheduler,
      clock: FakeClock(now),
      texts: _Texts(),
    );

    test('eingeschaltet und erlaubt: ersetzt alle mit Texten', () async {
      await _on.save(settings, at: DateTime.utc(2026, 11, 9));
      expect(await sync(), ReminderSyncResult.scheduled);
      expect(scheduler.scheduled, [
        ScheduledReminder(
          at: DateTime(2026, 11, 10, 17, 30),
          title: 'Geplantes Training',
          body: 'intervals 18',
        ),
        ScheduledReminder(
          at: DateTime(2026, 11, 12, 17, 30),
          title: 'Geplantes Training',
          body: 'long 18',
        ),
      ]);
      expect(scheduler.channelName, 'Erinnerungen');
      expect(plans.asked.single.$1, _d(11, 9));
    });

    test('aus, ohne Berechtigung oder ohne Ziel: alles storniert', () async {
      expect(await sync(), ReminderSyncResult.off);
      expect(scheduler.cancelCount, 1);
      await _on.save(settings, at: DateTime.utc(2026, 11, 9));
      scheduler.granted = false;
      expect(await sync(), ReminderSyncResult.notPermitted);
      expect(scheduler.cancelCount, 2);
      scheduler.granted = true;
      data.goal = null;
      expect(await sync(), ReminderSyncResult.noGoal);
      expect(scheduler.cancelCount, 3);
      expect(scheduler.replaceCount, 0);
      // Keine Anfrage der Berechtigung beim Synchronisieren.
      expect(scheduler.requestCount, 0);
    });
  });
}
