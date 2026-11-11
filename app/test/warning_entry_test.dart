// WP23 Teil B2: Einstieg Warnsignal aus der Zusammenfassung (FR-0203, K58).
// Synthetische Daten.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/summary/subjective_section.dart';
import 'package:running_app/features/summary/warning_entry.dart';

import 'app_harness.dart';

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

  Future<void> pump(WidgetTester tester, StorageSession s, int runId) async {
    final clock = FakeClock(DateTime.utc(2030, 1, 2, 9));
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('de'),
        brightness: Brightness.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SubjectiveSection(
              service: SubjectiveService(session: s, clock: clock),
              runId: runId,
              onWarning: warningEntry(session: s, clock: clock, runId: runId),
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
    },
  );
}
