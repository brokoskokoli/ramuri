import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/health/health_connect_controller.dart';
import 'package:running_app/features/plan/plan_change_card.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_recovery_trigger.dart';
import 'package:running_app/l10n/app_localizations_de.dart';

/// Auslöser „veränderter Erholungszustand“ (FR-0157, FR-0158, Teil „3
/// (Erholung)“): Prüfung nach Import und Morgenmessung, Wochenprüfung, nur
/// bei „adaptiv“ und nur für heute. Synthetische Daten: Ziel, Plan und
/// Readiness-Bänder sind ausgedacht.

final Uint8List _k = Uint8List.fromList(List.generate(32, (i) => i));
final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
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

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.minutes}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

class _Env {
  _Env(this.session);

  final StorageSession session;
  late final FakeClock clock;

  PlanReadinessDay? Function(DateTime day) readiness = (_) => null;
  final asked = <DateTime>[];

  PlanRepository get plans => (session as PlanStorage).plans;

  /// Plan mit harter Einheit in jeder Woche, angelegt am Mittwoch [_d0]
  /// (Prüftag gesetzt); die Uhr steht am Mittag der ersten harten Einheit ab
  /// dem Tag [from].
  static Future<_Env> open({int from = 1}) async {
    final s = await FakeStorage().open(_k);
    await (s as GoalStorage).goals.save(_goal(), today: _day(0));
    await recalculatePlan(
      plans: (s as PlanStorage).plans,
      settings: s.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: _day(0).add(const Duration(hours: 8)),
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 180),
      warning: (s as WarningStorage).warning,
    );
    final e = _Env(s);
    e.clock = FakeClock(
      _day(await e.hardFrom(from)).add(const Duration(hours: 12)),
    );
    return e;
  }

  /// Erster Tag ab [from] mit einer harten Einheit.
  Future<int> hardFrom(int from) async {
    for (var n = from; n < from + 28; n++) {
      final u = await plans.unitOn(_day(n));
      if (u != null && u.isHard) return n;
    }
    fail('keine harte Einheit');
  }

  DateTime get today => planDay(clock.now());

  Future<void> mode(PlanAdaptationMode m) =>
      SettingsPlanAdaptationStore(session.settings).set(m, at: clock.now());

  Future<PlanReadinessDay?> source(DateTime day) async {
    asked.add(day);
    return readiness(day);
  }

  PlanController controller() => PlanController(
    session: session,
    clock: clock,
    reader: PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => const [],
    ),
    readinessToday: source,
  );

  Future<int> versions() async => (await plans.history()).length;

  Future<List<String>> all() async => [
    for (final u in await plans.unitsBetween(_day(-30), _day(400))) _sig(u),
  ];
}

PlanReadinessDay _band(DateTime day, ReadinessBand band) => PlanReadinessDay(
  day: day,
  band: band,
  drivers: const [ReadinessFactorId.hrv],
);

void main() {
  group('recheckRecovery (Auslöser nach Import und Morgenmessung)', () {
    for (final band in [
      ReadinessBand.elevatedLoad,
      ReadinessBand.recoveryAdvised,
    ]) {
      test('„adaptiv“, harte Einheit heute, Band ${band.name}: eine Fassung '
          '(feedback, Grund readiness), nur die Einheit von heute wird '
          'locker', () async {
        final e = await _Env.open();
        await e.mode(PlanAdaptationMode.adaptive);
        final today = e.today;
        final hard = (await e.plans.unitOn(today))!;
        final before = await e.all();
        final versions = await e.versions();
        e.readiness = (d) => _band(d, band);
        final c = e.controller();
        expect(await c.recheckRecovery(), isTrue);
        expect(await e.versions(), versions + 1);
        final v = (await e.plans.history()).last;
        expect(v.trigger, PlanTrigger.feedback);
        expect(v.reason, planReasonReadiness);
        final now = (await e.plans.unitOn(today))!;
        expect(now.kind, PlanUnitKind.easy);
        expect(now.minutes, hard.minutes);
        // Nur die Einheit von heute ändert sich (FR-0157, PAR-173).
        final after = await e.all();
        final changed = [
          for (var i = 0; i < before.length; i++)
            if (before[i] != after[i]) after[i],
        ];
        expect(after.length, before.length);
        expect(changed, [_sig(now)]);
        expect(e.asked, [today]);
        // Die Lockerung zeigt einen Grund (FR-0170, ACC-10).
        await c.reload();
        final notice = c.state.changeNotice!;
        expect(notice.explanation.code, planReasonReadiness);
        expect(
          planChangeReasonText(
            AppLocalizationsDe(),
            notice.explanation,
            notice.version,
          ),
          AppLocalizationsDe().planAdaptReasonReadiness,
        );
        c.dispose();
      });
    }

    test('„adaptiv“, zweiter Aufruf nach der Lockerung: keine weitere '
        'Fassung; ein besserer Wert macht sie nicht rückgängig', () async {
      final e = await _Env.open();
      await e.mode(PlanAdaptationMode.adaptive);
      e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
      final c = e.controller();
      expect(await c.recheckRecovery(), isTrue);
      final versions = await e.versions();
      final eased = await e.all();
      e.readiness = (d) => _band(d, ReadinessBand.wellRecovered);
      expect(await c.recheckRecovery(), isFalse);
      expect(await e.versions(), versions);
      expect(await e.all(), eased);
      c.dispose();
    });

    test(
      '„fix“: ein niedriger Wert ändert nichts und wird nicht gelesen',
      () async {
        final e = await _Env.open();
        e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
        final before = await e.all();
        final versions = await e.versions();
        final c = e.controller();
        expect(await c.recheckRecovery(), isFalse);
        expect(await e.versions(), versions);
        expect(await e.all(), before);
        expect(e.asked, isEmpty);
        c.dispose();
      },
    );

    for (final (name, source)
        in <(String, PlanReadinessDay? Function(DateTime))>[
          ('ohne Wert', (_) => null),
          ('Wert ohne Zahl', (d) => PlanReadinessDay(day: d, band: null)),
          ('normaler Wert', (d) => _band(d, ReadinessBand.normal)),
          ('hoher Wert', (d) => _band(d, ReadinessBand.wellRecovered)),
          (
            'niedriger Wert des Vortags',
            (d) => _band(
              d.subtract(const Duration(days: 1)),
              ReadinessBand.recoveryAdvised,
            ),
          ),
          ('Fehler beim Laden', (_) => throw StateError('x')),
        ]) {
      test('„adaptiv“, harte Einheit heute, $name: nichts', () async {
        final e = await _Env.open();
        await e.mode(PlanAdaptationMode.adaptive);
        e.readiness = source;
        final before = await e.all();
        final versions = await e.versions();
        final c = e.controller();
        expect(await c.recheckRecovery(), isFalse);
        expect(await e.versions(), versions);
        expect(await e.all(), before);
        c.dispose();
      });
    }

    test('„adaptiv“, heute keine harte Einheit: nichts, auch die harte '
        'Einheit eines späteren Tags bleibt (nur heute)', () async {
      final e = await _Env.open();
      await e.mode(PlanAdaptationMode.adaptive);
      // Ein Tag vor der harten Einheit ohne harte Einheit.
      e.clock.advance(const Duration(days: -1));
      final u = await e.plans.unitOn(e.today);
      expect(u == null || !u.isHard, isTrue);
      e.readiness = (_) => _band(
        e.today.add(const Duration(days: 1)),
        ReadinessBand.recoveryAdvised,
      );
      final before = await e.all();
      final c = e.controller();
      expect(await c.recheckRecovery(), isFalse);
      expect(await e.all(), before);
      // Auch der heutige niedrige Wert ändert keine spätere Einheit.
      e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
      expect(await c.recheckRecovery(), isFalse);
      expect(await e.all(), before);
      c.dispose();
    });

    test('„adaptiv“ unter Warnsignal: nichts (Vorrang, FR-0203)', () async {
      final e = await _Env.open();
      await e.mode(PlanAdaptationMode.adaptive);
      final c = e.controller();
      expect(await c.reportWarning(), PlanActionResult.done);
      final before = await e.all();
      final versions = await e.versions();
      e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
      expect(await c.recheckRecovery(), isFalse);
      expect(await e.versions(), versions);
      expect(await e.all(), before);
      c.dispose();
    });
  });

  group('Wochenprüfung (FR-0158)', () {
    Future<_Env> due() async {
      // Erste harte Einheit in der nächsten Kalenderwoche: der Prüftag
      // (Mittwoch der Anlage) liegt dann in einer früheren Woche.
      final e = await _Env.open(from: 5);
      expect(
        weeklyCheckDue(
          await e.session.settings.get(planLastCheckDayKey),
          e.today,
        ),
        isTrue,
      );
      return e;
    }

    test(
      '„adaptiv“ mit niedrigem Wert heute: nach der Prüfung eine eigene '
      'Fassung mit Grund readiness, die Einheit von heute ist locker',
      () async {
        final e = await due();
        await e.mode(PlanAdaptationMode.adaptive);
        e.readiness = (d) => _band(d, ReadinessBand.elevatedLoad);
        final c = e.controller();
        await c.open();
        final history = await e.plans.history();
        expect(history.last.reason, planReasonReadiness);
        expect(history.last.trigger, PlanTrigger.feedback);
        expect((await e.plans.unitOn(e.today))!.kind, PlanUnitKind.easy);
        expect(c.state.changeNotice?.explanation.code, planReasonReadiness);
        expect(
          await e.session.settings.get(planLastCheckDayKey),
          isoDay(e.today),
        );
        c.dispose();
      },
    );

    test('„fix“ mit niedrigem Wert heute: die Prüfung läuft, die harte '
        'Einheit bleibt, kein Wert wird gelesen', () async {
      final e = await due();
      e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
      final c = e.controller();
      await c.open();
      expect((await e.plans.unitOn(e.today))!.isHard, isTrue);
      expect([
        for (final v in await e.plans.history()) v.reason,
      ], isNot(contains(planReasonReadiness)));
      expect(
        await e.session.settings.get(planLastCheckDayKey),
        isoDay(e.today),
      );
      expect(e.asked, isEmpty);
      c.dispose();
    });

    test(
      'Öffnen ohne fällige Prüfung liest keinen Wert und rechnet nicht',
      () async {
        final e = await due();
        await e.mode(PlanAdaptationMode.adaptive);
        e.readiness = (d) => _band(d, ReadinessBand.normal);
        final c = e.controller();
        await c.open();
        final versions = await e.versions();
        e.asked.clear();
        e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
        await c.open();
        expect(await e.versions(), versions);
        expect(e.asked, isEmpty);
        expect((await e.plans.unitOn(e.today))!.isHard, isTrue);
        c.dispose();
      },
    );
  });

  group('PlanRecoveryTrigger', () {
    test('meldet nur eine geschriebene Fassung', () async {
      final e = await _Env.open();
      var changed = 0;
      final t = PlanRecoveryTrigger(
        session: e.session,
        clock: e.clock,
        readinessToday: e.source,
        onChanged: () => changed++,
      );
      e.readiness = (d) => _band(d, ReadinessBand.recoveryAdvised);
      expect(await t.recheck(), isFalse); // „fix“
      expect(changed, 0);
      await e.mode(PlanAdaptationMode.adaptive);
      final results = await Future.wait([t.recheck(), t.recheck()]);
      // Nacheinander: die zweite Prüfung sieht die Lockerung schon.
      expect(results, [true, false]);
      expect(changed, 1);
      expect((await e.plans.unitOn(e.today))!.kind, PlanUnitKind.easy);
    });
  });

  group('Import: neue Gesundheitsdaten', () {
    HealthImportResult r(
      HealthImportStatus s,
      Map<HealthDataKind, HealthKindResult> k,
    ) => HealthImportResult(s, k);
    test('nur gespeicherte Sätze zählen als neue Daten', () {
      expect(
        healthImportStoredNew(
          r(HealthImportStatus.done, {
            HealthDataKind.sleep: const HealthKindResult(
              HealthKindStatus.imported,
              stored: 1,
            ),
          }),
        ),
        isTrue,
      );
      expect(
        healthImportStoredNew(
          r(HealthImportStatus.done, {
            HealthDataKind.sleep: const HealthKindResult(
              HealthKindStatus.imported,
            ),
            HealthDataKind.hrvRmssd: const HealthKindResult(
              HealthKindStatus.failed,
              stored: 3,
            ),
          }),
        ),
        isFalse,
      );
      expect(
        healthImportStoredNew(r(HealthImportStatus.throttled, const {})),
        isFalse,
      );
      expect(
        healthImportStoredNew(r(HealthImportStatus.unavailable, const {})),
        isFalse,
      );
    });
  });

  group('HealthConnectController.onNewData', () {
    Future<(HealthConnectController, _ImportPort)> setup() async {
      final storage = FakeStorage();
      final port = _ImportPort();
      final c = HealthConnectController(
        port: port,
        store: storage.data.health,
        settings: FakeSettingsStore(storage.data),
        consentStore: FakeConsentStore(storage.data),
        clock: FakeClock(DateTime.utc(2026, 11, 14, 12)),
      );
      await c.consents.grant(healthSourceKey(HealthDataKind.restingHeartRate));
      return (c, port);
    }

    test('ein Import mit neuen Sätzen meldet sich, einer ohne nicht', () async {
      final (c, port) = await setup();
      var calls = 0;
      c.onNewData = () => calls++;
      port.records = const [];
      await c.fetchNow();
      expect(calls, 0);
      port.records = [
        HealthRecord(
          kind: HealthDataKind.restingHeartRate,
          id: 'r1',
          origin: 'x',
          start: DateTime.utc(2026, 11, 14, 6),
          end: DateTime.utc(2026, 11, 14, 7),
          value: 50,
          unit: 'bpm',
        ),
      ];
      await c.fetchNow();
      expect(calls, 1);
      c.dispose();
    });
  });
}

/// Port, der für den Ruhepuls [records] liefert, für alles andere nichts.
class _ImportPort implements HealthConnectPort {
  List<HealthRecord> records = const [];

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
  }) async => HealthPage(
    kind == HealthDataKind.restingHeartRate ? records : const [],
    null,
  );
}
