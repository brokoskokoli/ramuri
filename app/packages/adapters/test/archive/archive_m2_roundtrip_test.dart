// Abschlussprüfung M2, Teil D: Archiv mit allen neuen Daten der Phase 2 hin und
// zurück. Anders als der Rundgang mit der SQL-Füllung (archive_restore_test)
// entstehen die Daten hier über die Ports und die Kernlogik: ein wirklich
// gerechneter Plan mit mehreren Fassungen (Auslöser weekly, run, feedback,
// Warnsignal), Terminen, Ruhetag, Läufen mit RPE/sRPE, Nachtrag, aktivem
// Warnsignal, Laufband, RR-Paketen, Referenzen und den Einstellungen der
// Planung. Export mit echter Kryptografie, Reimport in eine leere App, danach
// ist jede Tabelle zeilengleich. Alle Daten sind synthetisch.
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../storage/support.dart' show testKey;
import 'archive_fixture.dart' show sql;

const String _password = 'synthetisches Testpasswort';

typedef _Dump = Map<String, List<Map<String, Object?>>>;

AppDatabase _dbOf(StorageSession s) => (s as EncryptedStorageSession).database;

/// Alle Tabellen außer `storage_meta`, `consents` und den technischen Merkern.
Future<_Dump> _dump(AppDatabase db) async {
  final names = [
    for (final r
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )
            .get())
      r.data['name']! as String,
  ];
  final out = <String, List<Map<String, Object?>>>{};
  for (final n in names) {
    if (n == 'storage_meta' || n == 'consents') continue;
    final rows = await db
        .customSelect(
          'SELECT * FROM $n ORDER BY ${n == 'settings' ? 'key' : 'rowid'}',
        )
        .get();
    out[n] = [
      for (final r in rows)
        if (n != 'settings' ||
            !archiveExcludedSettingKeys.contains(r.data['key']))
          Map<String, Object?>.of(r.data),
    ];
  }
  return out;
}

final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));

/// Die M2-Tabellen: jede muss im Quellstand Zeilen haben, sonst prüft der
/// Test nichts.
const _m2Tables = [
  'goals',
  'plans',
  'plan_units',
  'run_feedback',
  'manual_trainings',
  'active_warning',
  'treadmill_settings',
  'raw_rr_packets',
  'reference_performances',
  'rejected_suggestions',
];

/// Einstellungen der Planung (Schlüssel aus dem Kern), die ins Archiv gehören.
final _planSettings = <String, String>{
  planPauseRestartKey: '2026-11-20 restart',
  'plan.feedback_answered_on': '2026-11-25',
  'plan.walk_run_repeat_declined': '2026-11-26',
  WarningSettingKeys.lastPromptOn: '2026-12-01',
  WarningSettingKeys.pauseAnswer: 'no:2026-11-27',
  WarningSettingKeys.hintBlockedUntil: '2026-12-04',
  WarningSettingKeys.planChangeSeen: '2',
};

/// Technische Merker der Planung: gehören nicht ins Archiv.
final _technical = <String, String>{
  SettingKeys.planStartedUnit: '{"unit":1}',
  SettingKeys.guidedUnitSnapshot: '{"run":1}',
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory work;
  late Directory appDir;
  late String activePath;
  late Uint8List key;
  late StorageSession source;
  late StorageSession target;
  late _Dump sourceDump;
  late List<PlanUnit> sourceUnits;
  late String archivePath;

  setUp(() async {
    key = testKey(7);
    work = Directory.systemTemp.createTempSync('m2archiv_');
    appDir = Directory('${work.path}/app')..createSync();
    activePath = '${appDir.path}/running_app.db';
    source = await EncryptedStorage('${work.path}/source.db').open(key);
    await _populate(source);
    sourceDump = await _dump(_dbOf(source));
    sourceUnits = await (source as PlanStorage).plans.unitsBetween(
      _day(-30),
      planFarFuture,
    );
    final exportDir = Directory('${work.path}/exports')..createSync();
    final handoff = FakeFileHandoff()..directory = exportDir.path;
    final f = await ArchiveExporter(
      source: DriftArchiveSource(_dbOf(source)),
      handoff: handoff,
      clock: FakeClock(DateTime.utc(2026, 12, 5, 12)),
      cipherFactory: createArchiveCipherInWorker,
      pageSize: 7,
    ).export(password: _password);
    archivePath = f.path!;
    target = await EncryptedStorage(activePath).open(key);
  });

  tearDown(() async {
    for (final s in [source, target]) {
      try {
        await s.close();
      } catch (_) {}
    }
    work.deleteSync(recursive: true);
  });

  Future<StorageSession> restore() {
    final files = FileDatabaseFiles(activePath);
    return ArchiveRestoreService(
      session: target,
      sink: DriftArchiveSink(
        storage: EncryptedStorage(files.importPath),
        key: () => key,
        files: files,
      ),
      files: files,
      cipherFactory: createArchiveCipherInWorker,
      clock: FakeClock(DateTime.utc(2026, 12, 5, 12)),
      reopen: () async => target = await EncryptedStorage(activePath).open(key),
      serialize: <T>(Future<T> Function() a) => a(),
    ).restore(path: archivePath, password: _password);
  }

  test('Quellstand: jede M2-Tabelle hat Zeilen, mehrere Plan-Fassungen mit '
      'Auslösern, Warnsignal aktiv', () async {
    for (final t in _m2Tables) {
      expect(sourceDump[t], isNotEmpty, reason: t);
    }
    final triggers = {for (final r in sourceDump['plans']!) r['trigger']};
    expect(triggers, containsAll(<String>['create', 'run', 'feedback']));
    expect(
      sourceDump['plans']!.any(
        (r) => (r['summary']! as String).contains(planWarningKey),
      ),
      isTrue,
      reason: 'Fassung unter Warnsignal hält die Festlegungen',
    );
    final fixed = {for (final r in sourceDump['plan_units']!) r['fixed']};
    expect(fixed, containsAll(<String>['none', 'day']));
    expect(sourceDump['plan_units']!.any((r) => r['pinned'] == 1), isTrue);
    expect(sourceDump['plan_units']!.any((r) => r['run_id'] != null), isTrue);
    expect(
      sourceDump['run_feedback']!.any((r) => r['srpe_points'] != null),
      isTrue,
    );
    final keys = {for (final r in sourceDump['settings']!) r['key']};
    expect(keys, containsAll(_planSettings.keys));
    expect(keys.intersection(_technical.keys.toSet()), isEmpty);
    // Technische Merker liegen in der Quelle, sind aber im Dump gefiltert.
    for (final k in _technical.keys) {
      expect(await source.settings.get(k), isNotNull, reason: k);
    }
  });

  test('Export, Reimport in leere App: jede Tabelle zeilengleich, Plan und '
      'Warnsignal über die Ports gleich, Merker fehlen', () async {
    expect(await ArchiveRestoreService.isEmpty(target), isTrue);
    target = await restore();
    final got = await _dump(_dbOf(target));
    expect(got.keys, sourceDump.keys);
    for (final t in sourceDump.keys) {
      expect(got[t], sourceDump[t], reason: 'Tabelle $t');
    }
    for (final t in _m2Tables) {
      expect(got[t], isNotEmpty, reason: t);
    }
    // Über die Ports: Einheiten (Art, Dauer, Abschnitte, fixed, pinned, Lauf).
    final plans = (target as PlanStorage).plans;
    final units = await plans.unitsBetween(_day(-30), planFarFuture);
    expect(units.map(_sig), sourceUnits.map(_sig));
    final history = await plans.history();
    expect(
      history.map((v) => '${v.trigger.name}/${v.reason}/${v.inputsJson}'),
      (await (source as PlanStorage).plans.history()).map(
        (v) => '${v.trigger.name}/${v.reason}/${v.inputsJson}',
      ),
    );
    // Warnsignal und die Merker der Planung sind wieder da, die
    // technischen nicht.
    final w = await (target as WarningStorage).warning.read();
    expect(w?.source, WarningSource.manual);
    expect(w?.reportedOn, _day(20));
    for (final e in _planSettings.entries) {
      expect(await target.settings.get(e.key), e.value, reason: e.key);
    }
    expect(
      await target.settings.get(planLastCheckDayKey),
      await source.settings.get(planLastCheckDayKey),
    );
    for (final k in _technical.keys) {
      expect(await target.settings.get(k), isNull, reason: k);
    }
    // Angaben zum Lauf und Nachtrag über die Ports.
    final subj = target.subjective;
    final s1 = (await subj.read(1))!;
    expect(s1.subjective.rpe, 6);
    expect(s1.srpe!.points, closeTo(30 * 6, 1e-9));
    expect((await target.manualTrainings.list()).single.training.rpe, 3);
    // Die Wochenprüfung rechnet mit dem wiederhergestellten Prüftag wie vorher.
    expect(await plans.history().then((h) => h.length), history.length);
  });

  test('Nicht im Archiv: Einwilligungen (storage_meta, consents); nach dem '
      'Import ist nichts erteilt', () async {
    await source.consents.set('quelle', ConsentState.granted, at: _d0);
    target = await restore();
    expect(await target.consents.all(), isEmpty);
  });
}

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.phase.name}|${u.weekIndex}|'
    '${u.minutes}|${u.runId}|${u.pinned}|${u.fixed.name}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.durationSeconds}:${s.intensity?.rpeMin}:${s.intensity?.paceFastSecondsPerKm}'].join(',')}';

/// Vier Wochen über die Ports und die Kernlogik (wie die App sie führt).
Future<void> _populate(StorageSession s) async {
  final plans = (s as PlanStorage).plans;
  final goals = (s as GoalStorage).goals;
  final warning = (s as WarningStorage).warning;
  final subj = s;
  final goal = TrainingGoal(
    type: GoalType.distance,
    distance: GoalDistance.tenKilometers,
    targetDate: DateTime.utc(2027, 6, 1),
    runDays: const {2, 4, 6},
    maxSessionSeconds: 120 * 60.0,
    weeklyCapSeconds: 240 * 60.0,
    createdAt: DateTime.utc(2026, 11, 1),
    hardSessionEnabled: true,
    currentWeeklySeconds: 150 * 60.0,
    canRun30: ContinuousRun30.yes,
  );
  await goals.save(goal, today: goal.createdAt);

  Future<void> recalc(PlanTrigger t, int d, {PlanInputs? inputs}) =>
      recalculatePlan(
        plans: plans,
        settings: s.settings,
        trigger: t,
        today: _day(d),
        now: _day(d).add(const Duration(hours: 8)),
        inputs: inputs,
        warning: warning,
        markChecked:
            t == PlanTrigger.create ||
            t == PlanTrigger.weekly ||
            t == PlanTrigger.goalChange,
      );

  await recalc(PlanTrigger.create, 0);
  var lastMonday = DateTime.utc(2026, 11, 9);
  var firstRun = true;
  for (var d = 0; d < 28; d++) {
    final today = _day(d);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    if (monday.isAfter(lastMonday)) {
      lastMonday = monday;
      await recalc(PlanTrigger.weekly, d);
    }
    if (d == 3) {
      // Termin verschieben (Bestätigung des Nutzers): ein künftiger Lauf.
      final u = (await plans.unitsBetween(
        _day(8),
        _day(14),
      )).firstWhere((u) => u.kind != PlanUnitKind.rest && u.runId == null);
      await plans.confirmMove(
        u.id!,
        u.day.add(const Duration(days: 1)),
        today: today,
      );
    }
    if (d == 5) {
      // Ruhetag des Nutzers auf einem Nicht-Lauftag der übernächsten Woche.
      final day = _day(15);
      final there = await plans.unitOn(day);
      await plans.setRestDay(
        PlanUnit(
          day: day,
          kind: PlanUnitKind.rest,
          phase: PlanPhase.build,
          weekIndex: there?.weekIndex ?? 2,
          minutes: 0,
          segments: const [],
          pinned: true,
          fixed: PlanUnitFixed.day,
        ),
        today: today,
        expectedUnitId: there?.id,
      );
    }
    if (d == 14) {
      final r = applyPlanFeedback(
        goal: goal,
        inputs: (await plans.history()).last.inputs.copyWith(today: today),
        answer: PlanFeedback.tooHard,
        today: today,
      );
      if (r.inputs != null) {
        await recalc(PlanTrigger.feedback, d, inputs: r.inputs);
      }
    }
    final unit = await plans.unitOn(today);
    if (unit != null &&
        unit.kind != PlanUnitKind.rest &&
        unit.runId == null &&
        d != 9 &&
        d != 10) {
      final run = await s.runs.create(
        startedAt: today.add(const Duration(hours: 7)),
        mode: firstRun ? RunMode.treadmill : RunMode.gps,
      );
      await s.runs.setState(
        run.id,
        RunState.finished,
        endedAt: today.add(Duration(hours: 7, minutes: unit.minutes)),
      );
      await plans.assignRun(unit.id!, run.id);
      if (firstRun) {
        firstRun = false;
        await sql(
          _dbOf(s),
          'INSERT INTO treadmill_settings (run_id, offset_us, speed_mps, '
          'incline_percent) VALUES (${run.id}, 0, 2.5, 1.5), '
          '(${run.id}, 300000000, 3.0, NULL)',
        );
        await sql(
          _dbOf(s),
          'INSERT INTO raw_rr_packets (run_id, time_us, source, rr) VALUES '
          "(${run.id}, 1, 'strap', x'0004ffff00000a03'), (${run.id}, 2, 'strap', x'0004')",
        );
      }
      await subj.subjective.save(
        run.id,
        RunSubjective(
          rpe: 6,
          wellbeing: 4,
          complaints: d == 7 ? 'Wade' : null,
          warningAnswer: d == 7 ? WarningAnswer.yes : null,
          note: 'Notiz-Ä',
        ),
        srpe: SrpeLoad.compute(duration: const Duration(minutes: 30), rpe: 6),
      );
      await recalc(PlanTrigger.run, d);
    }
    if (d == 20) {
      await WarningService(
        plans: plans,
        settings: s.settings,
        warning: warning,
      ).report(
        source: WarningSource.manual,
        today: today,
        now: today.add(const Duration(hours: 9)),
      );
    }
  }
  await subj.manualTrainings.add(
    ManualTraining(
      day: _day(6),
      kind: ManualTrainingKind.other,
      duration: const Duration(minutes: 45),
      rpe: 3,
    ),
  );
  final prediction = (s as PredictionStorage).prediction;
  await prediction.addReference(
    ReferencePerformance(
      kind: ReferenceKind.race,
      distanceMeters: 10000,
      seconds: 3100,
      date: DateTime.utc(2026, 10, 1),
      createdAt: _d0,
    ),
  );
  await prediction.rejectSuggestion(1);
  for (final e in {..._planSettings, ..._technical}.entries) {
    await s.settings.set(e.key, e.value, at: _d0);
  }
}
