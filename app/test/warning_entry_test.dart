// WP23 Teil B2: Einstieg Warnsignal aus der Zusammenfassung (FR-0203, K58).
// Synthetische Daten.

import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/summary/subjective_section.dart';
import 'package:running_app/features/summary/warning_entry.dart';

import 'app_harness.dart';

/// Sitzung, deren Plan- bzw. Warnsignal-Speicher beim Schreiben scheitert
/// (Platte voll u. Ä.); alles andere geht an die echte Sitzung.
class _FailingSession
    implements StorageSession, PlanStorage, WarningStorage, GoalStorage {
  _FailingSession(this.s, {this.failPlan = false, this.failWarning = false});
  final StorageSession s;
  final bool failPlan;
  final bool failWarning;

  @override
  PlanRepository get plans {
    final p = (s as PlanStorage).plans;
    return failPlan ? _FailingPlans(p) : p;
  }

  @override
  WarningStore get warning {
    final w = (s as WarningStorage).warning;
    return failWarning ? _FailingWarning(w) : w;
  }

  @override
  GoalStore get goals => (s as GoalStorage).goals;
  @override
  RunStore get runs => s.runs;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  RawDataStore get rawData => s.rawData;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  ProfileStore get profile => s.profile;
  @override
  SettingsStore get settings => s.settings;
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

/// Schreiben der Planfassung scheitert.
class _FailingPlans implements PlanRepository {
  _FailingPlans(this.inner);
  final PlanRepository inner;

  @override
  Future<TrainingGoal?> currentGoal() => inner.currentGoal();
  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) =>
      inner.unitsBetween(from, to);
  @override
  Future<PlanUnit?> unitOn(DateTime day) => inner.unitOn(day);
  @override
  Future<List<PlanVersionRecord>> history() => inner.history();
  @override
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft draft) =>
      throw const StorageException(StorageFailure.rejected);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Speichern des Warnsignals scheitert.
class _FailingWarning implements WarningStore {
  _FailingWarning(this.inner);
  final WarningStore inner;

  @override
  Future<WarningSignal?> read() => inner.read();
  @override
  Future<void> set(WarningSignal warning) =>
      throw const StorageException(StorageFailure.failed);
  @override
  Future<void> lift() => inner.lift();
}

void main() {
  Future<(StorageSession, int)> world() async {
    final session = await FakeStorage().open(Uint8List(32));
    final run = await session.runs.create(startedAt: DateTime.utc(2030, 1, 1));
    final goals = (session as GoalStorage).goals;
    final g = TrainingGoal(
      type: GoalType.open,
      runDays: const {2, 4, 6},
      maxSessionSeconds: 7200,
      weeklyCapSeconds: 240 * 60.0,
      createdAt: DateTime.utc(2030, 1, 1),
      hardSessionEnabled: false,
      canRun30: ContinuousRun30.yes,
    );
    await goals.save(g, today: g.createdAt);
    return (session, run.id);
  }

  final clock = FakeClock(DateTime.utc(2030, 1, 2, 9));

  Future<void> pump(
    WidgetTester tester,
    StorageSession s,
    int runId, {
    StorageSession? entry,
  }) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('de'),
        brightness: Brightness.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SubjectiveSection(
              service: SubjectiveService(session: s, clock: clock),
              runId: runId,
              onWarning: warningEntry(
                session: entry ?? s,
                clock: clock,
                runId: runId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String k) async {
    await tester.tap(find.byKey(ValueKey(k)));
    await tester.pumpAndSettle();
  }

  Future<void> answerYes(WidgetTester tester) async {
    await tap(tester, 'subjective_complaints_button');
    await tester.enterText(
      find.byKey(const ValueKey('subjective_complaints')),
      'Knie',
    );
    await tester.pumpAndSettle();
    await tap(tester, 'subjective_warn_yes');
  }

  PlanController planOf(StorageSession s) => PlanController(
    session: s,
    clock: clock,
    reader: PlanDataReader(
      session: s,
      clock: clock,
      loadRuns: () async => const [],
    ),
  );

  testWidgets('Neuberechnung scheitert: das Warnsignal bleibt gespeichert, '
      'die Zusammenfassung meldet den Fehler; das Öffnen des Plans holt die '
      'Ruhetag-Fassung nach', (tester) async {
    final (s, runId) = await world();
    final plan = planOf(s);
    await plan.open();
    final plans = (s as PlanStorage).plans;
    final before = (await plans.history()).length;
    expect(before, greaterThan(0));
    await pump(tester, s, runId, entry: _FailingSession(s, failPlan: true));
    await answerYes(tester);
    expect(
      find.byKey(const ValueKey('subjective_save_failed')),
      findsOneWidget,
    );
    final w = (await (s as WarningStorage).warning.read())!;
    expect(w.source, WarningSource.runFeedback);
    expect(w.runId, runId);
    expect(w.reportedOn, DateTime.utc(2030, 1, 2));
    expect((await plans.history()).length, before);

    await plan.open();
    final versions = await plans.history();
    expect(versions.length, before + 1);
    expect(versions.last.reason, planReasonWarning);
    expect(versions.last.trigger, PlanTrigger.feedback);
    expect((await (s as WarningStorage).warning.read())!.runId, runId);
    plan.dispose();
  });

  testWidgets('Speichern des Warnsignals scheitert: kein Warnsignal, die '
      'Zusammenfassung meldet den Fehler', (tester) async {
    final (s, runId) = await world();
    await pump(tester, s, runId, entry: _FailingSession(s, failWarning: true));
    await answerYes(tester);
    expect(
      find.byKey(const ValueKey('subjective_save_failed')),
      findsOneWidget,
    );
    expect(await (s as WarningStorage).warning.read(), isNull);
    expect(await (s as PlanStorage).plans.history(), isEmpty);
  });

  testWidgets('Antwort ja meldet das Warnsignal (run_feedback), nein nicht; '
      'es übersteht das Löschen des Laufs', (tester) async {
    final (s, runId) = await world();
    await pump(tester, s, runId);
    final warning = (s as WarningStorage).warning;
    await tap(tester, 'subjective_complaints_button');
    await tester.enterText(
      find.byKey(const ValueKey('subjective_complaints')),
      'Knie',
    );
    await tester.pumpAndSettle();
    await tap(tester, 'subjective_warn_no');
    expect(await warning.read(), isNull);
    await tap(tester, 'subjective_warn_yes');
    final w = (await warning.read())!;
    expect(w.source, WarningSource.runFeedback);
    expect(w.runId, runId);
    expect(w.reportedOn, DateTime.utc(2030, 1, 2));
    final versions = await (s as PlanStorage).plans.history();
    expect(versions.last.reason, 'warning');
    expect(versions.last.trigger, PlanTrigger.feedback);
    await s.deleteRun(runId);
    expect(await warning.read(), isNotNull);
    expect(
      (await (s as PlanStorage).plans.unitsBetween(
        DateTime.utc(2030, 1, 2),
        DateTime.utc(2031, 1, 1),
      )).every((u) => u.kind == PlanUnitKind.rest),
      isTrue,
    );
  });

  testWidgets('schnelles ja, dann nein: Melden und Aufheben überlappen nicht', (
    tester,
  ) async {
    final (s, runId) = await world();
    final clock = FakeClock(DateTime.utc(2030, 1, 2, 9));
    final log = <String>[];
    final firstDone = Completer<void>();
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('de'),
        brightness: Brightness.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SubjectiveSection(
              service: SubjectiveService(session: s, clock: clock),
              runId: runId,
              onWarning: (yes) async {
                log.add(yes ? 'ja:start' : 'nein:start');
                if (yes) await firstDone.future;
                log.add(yes ? 'ja:ende' : 'nein:ende');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'subjective_complaints_button');
    await tester.enterText(
      find.byKey(const ValueKey('subjective_complaints')),
      'Knie',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subjective_warn_yes')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('subjective_warn_no')));
    await tester.pumpAndSettle();
    // Das Melden läuft noch: Das Aufheben hat nicht begonnen.
    expect(log, ['ja:start']);
    firstDone.complete();
    await tester.pumpAndSettle();
    expect(log, ['ja:start', 'ja:ende', 'nein:start', 'nein:ende']);
  });

  testWidgets(
    'Antwort ja zurücknehmen (nein oder abwählen) hebt das Warnsignal '
    'dieses Laufs auf; ein anderes bleibt',
    (tester) async {
      final (s, runId) = await world();
      await pump(tester, s, runId);
      final warning = (s as WarningStorage).warning;
      await tap(tester, 'subjective_complaints_button');
      await tester.enterText(
        find.byKey(const ValueKey('subjective_complaints')),
        'Knie',
      );
      await tester.pumpAndSettle();
      await tap(tester, 'subjective_warn_yes');
      expect((await warning.read())!.runId, runId);
      await tap(tester, 'subjective_warn_no');
      expect(await warning.read(), isNull);
      final versions = await (s as PlanStorage).plans.history();
      expect(versions.last.reason, 'warningLifted');
      // Erneut ja, dann abwählen.
      await tap(tester, 'subjective_warn_yes');
      expect(await warning.read(), isNotNull);
      await tap(tester, 'subjective_warn_yes');
      expect(await warning.read(), isNull);

      // Ein Warnsignal einer anderen Quelle bleibt.
      await warning.set(
        WarningSignal(
          reportedOn: DateTime.utc(2030, 1, 2),
          source: WarningSource.manual,
        ),
      );
      await tap(tester, 'subjective_warn_yes');
      await tap(tester, 'subjective_warn_no');
      expect((await warning.read())!.source, WarningSource.manual);
      // Gleiche Quelle, anderer Lauf; andere Quelle, gleicher Lauf: bleibt.
      for (final (source, id) in [
        (WarningSource.runFeedback, runId + 1),
        (WarningSource.manual, runId),
      ]) {
        await warning.lift();
        await warning.set(
          WarningSignal(
            reportedOn: DateTime.utc(2030, 1, 2),
            source: source,
            runId: id,
          ),
        );
        await tap(tester, 'subjective_warn_yes');
        await tap(tester, 'subjective_warn_no');
        expect(await warning.read(), isNotNull, reason: '$source $id');
      }
    },
  );
}
