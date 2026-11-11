import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun, started, text;

/// Training nachtragen (WP18, FR-0199). Heute ist Mittwoch, der 17. Juni 2026.
final DateTime _now = DateTime.utc(2026, 6, 17, 12);

Future<Device> _start(WidgetTester tester) async {
  final d = await started(tester);
  d.clock.set(_now);
  return d;
}

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(key('home_history'));
  await tester.pumpAndSettle();
}

Future<void> _all(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(of: key('history_range'), matching: find.byType(InkWell))
        .last,
  );
  await tester.pumpAndSettle();
}

Future<void> _fill(
  WidgetTester tester, {
  String? minutes,
  int? rpe,
  String? kind,
}) async {
  if (kind != null) await tapKey(tester, 'manual_kind_$kind');
  if (minutes != null) {
    await tester.enterText(key('manual_minutes'), minutes);
    await tester.pump();
  }
  if (rpe != null) await tapKey(tester, 'manual_rpe_$rpe');
}

Future<List<StoredManualTraining>> _stored(Device d) =>
    d.session.manualTrainings.list();

void main() {
  group('Anlegen, Ändern, Löschen', () {
    testWidgets('Sonstiges anlegen: im Speicher, im Verlauf gekennzeichnet', (
      tester,
    ) async {
      final d = await _start(tester);
      await _openHistory(tester);
      expect(key('manual_add'), findsOneWidget);
      await tester.tap(key('manual_add'));
      await tester.pumpAndSettle();
      await _fill(tester, kind: 'other', minutes: '45', rpe: 5);
      await tapKey(tester, 'manual_save');

      final list = await _stored(d);
      expect(list, hasLength(1));
      final t = list.single.training;
      expect(t.kind, ManualTrainingKind.other);
      expect(t.duration, const Duration(minutes: 45));
      expect(t.rpe, 5);
      expect(t.isoDay, '2026-06-17', reason: 'Standard ist heute');

      final id = list.single.id;
      expect(find.text('Nachgetragen'), findsOneWidget);
      expect(text('manual_kind_$id'), 'Sonstiges');
      expect(text('manual_srpe_$id'), '225 Punkte (Schätzung)');
      expect(
        text('manual_basis_$id'),
        'Grundlage: Dauer 45:00 · Anstrengung 5',
      );
      expect(text('manual_not_rated_$id'), 'Belastung: nicht bewertet');
      expect(find.text('Ohne Karte und Distanz'), findsOneWidget);
      // Keine Karte, Distanz oder Pace für diesen Eintrag.
      expect(find.byType(Image), findsNothing);
      expect(key('history_distance_$id'), findsNothing);
      expect(key('history_pace_$id'), findsNothing);
      expect(key('history_miniature_$id'), findsNothing);
    });

    testWidgets(
      'Dauer 0, leere Dauer und fehlendes RPE sind nicht speicherbar',
      (tester) async {
        final d = await _start(tester);
        await _openHistory(tester);
        await tester.tap(key('manual_add'));
        await tester.pumpAndSettle();
        // Alles leer.
        await tapKey(tester, 'manual_save');
        expect(find.text('Bitte die Anstrengung wählen.'), findsOneWidget);
        expect(
          find.text('Bitte eine Dauer über 0 Minuten angeben.'),
          findsOneWidget,
        );
        // Dauer 0 mit RPE.
        await _fill(tester, minutes: '0', rpe: 4);
        await tapKey(tester, 'manual_save');
        expect(
          find.text('Bitte eine Dauer über 0 Minuten angeben.'),
          findsOneWidget,
        );
        // Gültige Dauer, RPE bleibt gewählt.
        await _fill(tester, minutes: '30');
        await tapKey(tester, 'manual_save');
        expect(await _stored(d), hasLength(1), reason: 'jetzt gültig');
      },
    );

    testWidgets('fehlendes RPE allein verhindert das Speichern', (
      tester,
    ) async {
      final d = await _start(tester);
      await _openHistory(tester);
      await tester.tap(key('manual_add'));
      await tester.pumpAndSettle();
      await _fill(tester, minutes: '30');
      await tapKey(tester, 'manual_save');
      expect(key('manual_rpe_error'), findsOneWidget);
      expect(key('manual_form'), findsOneWidget, reason: 'bleibt offen');
      expect(await _stored(d), isEmpty);
    });

    testWidgets('Ändern: RPE neu, sRPE folgt', (tester) async {
      final d = await _start(tester);
      final s = await d.session.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2026, 6, 16),
          kind: ManualTrainingKind.run,
          duration: const Duration(minutes: 45),
          rpe: 5,
        ),
      );
      await _openHistory(tester);
      expect(text('manual_srpe_${s.id}'), '225 Punkte (Schätzung)');
      await tester.tap(key('manual_training_${s.id}'));
      await tester.pumpAndSettle();
      expect(text('manual_rpe_label'), contains('5'));
      await _fill(tester, rpe: 7);
      await tapKey(tester, 'manual_save');
      final now = (await _stored(d)).single;
      expect(now.id, s.id);
      expect(now.training.rpe, 7);
      expect(now.training.kind, ManualTrainingKind.run);
      expect(text('manual_srpe_${s.id}'), '315 Punkte (Schätzung)');
    });

    testWidgets('Löschen mit Rückfrage: Abbrechen behält, Löschen entfernt', (
      tester,
    ) async {
      final d = await _start(tester);
      final s = await d.session.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2026, 6, 16),
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 20),
          rpe: 3,
        ),
      );
      await _openHistory(tester);
      await tester.tap(key('manual_delete_${s.id}'));
      await tester.pumpAndSettle();
      expect(find.text('Training löschen?'), findsOneWidget);
      await tester.tap(key('manual_delete_cancel'));
      await tester.pumpAndSettle();
      expect(await _stored(d), hasLength(1));
      await tester.tap(key('manual_delete_${s.id}'));
      await tester.pumpAndSettle();
      await tester.tap(key('manual_delete_confirm'));
      await tester.pumpAndSettle();
      expect(await _stored(d), isEmpty);
      expect(key('manual_training_${s.id}'), findsNothing);
    });

    testWidgets('Speicherfehler: Hinweis ohne Inhalt, nichts gespeichert', (
      tester,
    ) async {
      final d = await _start(tester);
      await _openHistory(tester);
      await tester.tap(key('manual_add'));
      await tester.pumpAndSettle();
      await _fill(tester, minutes: '30', rpe: 6);
      // Die Uhr springt zurück: Der gewählte Tag (heute) liegt nun in der
      // Zukunft, der Dienst lehnt ab.
      d.clock.set(DateTime.utc(2026, 6, 10, 12));
      await tapKey(tester, 'manual_save');
      expect(
        text('manual_save_failed'),
        'Das Training konnte nicht gespeichert werden.',
      );
      expect(await _stored(d), isEmpty);
      expect(find.textContaining('SubjectiveRangeError'), findsNothing);
    });
  });

  group('Datum', () {
    testWidgets('Zukunft nicht wählbar, Vergangenheit schon', (tester) async {
      await _start(tester).then((d) async {
        await _openHistory(tester);
        await tester.tap(key('manual_add'));
        await tester.pumpAndSettle();
        final before = tester
            .widgetList<Text>(
              find.descendant(
                of: key('manual_date'),
                matching: find.byType(Text),
              ),
            )
            .single
            .data;
        // Morgen (18.) lässt sich nicht antippen.
        await tester.tap(key('manual_date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('18'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        String shown() => tester
            .widgetList<Text>(
              find.descendant(
                of: key('manual_date'),
                matching: find.byType(Text),
              ),
            )
            .single
            .data!;
        expect(shown(), before);
        // Gestern (16.) schon.
        await tester.tap(key('manual_date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('16'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(shown(), isNot(before));
        await _fill(tester, minutes: '30', rpe: 3);
        await tapKey(tester, 'manual_save');
        expect((await _stored(d)).single.training.isoDay, '2026-06-16');
      });
    });
  });

  group('Verlauf', () {
    testWidgets('Lauf und Sonstiges nach Datum einsortiert, beide gezeigt', (
      tester,
    ) async {
      final d = await _start(tester);
      final run = await seedRun(d.session, DateTime.utc(2026, 6, 16, 8));
      final other = await d.session.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2026, 6, 17),
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 60),
          rpe: 4,
        ),
      );
      final manualRun = await d.session.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2026, 6, 15),
          kind: ManualTrainingKind.run,
          duration: const Duration(minutes: 30),
          rpe: 6,
        ),
      );
      await _openHistory(tester);
      await _all(tester);
      double top(String k) => tester.getTopLeft(key(k)).dy;
      expect(
        top('manual_training_${other.id}'),
        lessThan(top('history_run_$run')),
      );
      expect(
        top('history_run_$run'),
        lessThan(top('manual_training_${manualRun.id}')),
      );
      expect(text('manual_kind_${other.id}'), 'Sonstiges');
      expect(text('manual_kind_${manualRun.id}'), 'Lauf');
      expect(text('manual_srpe_${manualRun.id}'), '180 Punkte (Schätzung)');
      // Der aufgezeichnete Lauf behält Strecke und Pace, die Summe zählt ihn allein.
      expect(key('history_distance_$run'), findsOneWidget);
      expect(text('history_total_runs'), '1');
    });

    testWidgets('nur nachgetragene Trainings: Liste statt Leerzustand', (
      tester,
    ) async {
      final d = await _start(tester);
      await d.session.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2026, 6, 16),
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 20),
          rpe: 2,
        ),
      );
      await _openHistory(tester);
      expect(key('history_empty'), findsNothing);
      expect(find.text('Nachgetragen'), findsOneWidget);
      expect(key('history_total_runs'), findsNothing);
    });

    testWidgets('Englisch', (tester) async {
      final d = Device();
      await d.start(tester, const Locale('en'));
      await d.skipSetup(tester);
      d.clock.set(_now);
      await d.session.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2026, 6, 16),
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 45),
          rpe: 5,
        ),
      );
      await _openHistory(tester);
      expect(find.text('Added manually'), findsOneWidget);
      expect(find.text('Load: not rated'), findsOneWidget);
      expect(find.text('225 points (estimate)'), findsOneWidget);
    });
  });

  group('Statistik, VO₂max, Bestwerte unverändert', () {
    testWidgets(
      'mit nachgetragenem Training bleiben alle Läufauswertungen gleich',
      (tester) async {
        final d = await _start(tester);
        await seedRun(d.session, DateTime.utc(2026, 6, 16, 8));
        await seedRun(d.session, DateTime.utc(2026, 6, 10, 8), minutes: 30);

        Future<List<Object?>> snapshot() async {
          final runs = await d.session.runs.list();
          final overviews = await RunOverviewService(
            session: d.session,
            clock: d.clock,
          ).load();
          final figures = [for (final o in overviews) o.toFigures()];
          final totals = historyTotals(HistoryRange.all, '2026-06-17', figures);
          final stats = computePeriodStatistics(
            StatisticsPeriod.weekOf('2026-06-17'),
            figures,
          );
          final fitness = await FitnessOverviewService(session: d.session)
              .load(runs);
          final values = await d.session.values.readRunValues({
            vo2maxRunValueKey,
          });
          return [
            [for (final r in runs) r.id],
            [
              for (final o in overviews)
                (
                  o.run.id,
                  o.distanceMeters,
                  o.averagePaceSecondsPerKm,
                  o.totalTime,
                ),
            ],
            (totals.runCount, totals.distanceMeters, totals.totalTime),
            (
              stats.runCount,
              stats.trainingDays,
              stats.distanceMeters.toString(),
              stats.bestPaceSecondsPerKm.toString(),
              stats.trimpPoints.toString(),
            ),
            (
              fitness.runEstimates.length,
              fitness.pendingRuns,
              fitness.longTerm?.value,
            ),
            values.keys.toList(),
          ];
        }

        final before = await snapshot();
        // Über den Dienst wie die Oberfläche, nicht am Dienst vorbei.
        await SubjectiveService(session: d.session, clock: d.clock).addTraining(
          ManualTraining(
            day: DateTime.utc(2026, 6, 16),
            kind: ManualTrainingKind.run,
            duration: const Duration(minutes: 90),
            rpe: 9,
          ),
        );
        expect(await snapshot(), before);
        expect((await d.session.runs.list()), hasLength(2));
      },
    );
  });

  group('Schriftfaktor 1,3 auf 360 x 640', () {
    for (final dark in [false, true]) {
      testWidgets(
        '${dark ? 'dunkel' : 'hell'}: Formular und Eintrag ohne Überlauf, 48 dp',
        (tester) async {
          final d = await _start(tester);
          final s = await d.session.manualTrainings.add(
            ManualTraining(
              day: DateTime.utc(2026, 6, 16),
              kind: ManualTrainingKind.other,
              duration: const Duration(minutes: 45),
              rpe: 5,
            ),
          );
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await _openHistory(tester);
          expect(tester.takeException(), isNull);
          for (final k in ['manual_add', 'manual_delete_${s.id}']) {
            final size = tester.getSize(key(k));
            expect(
              size.height,
              greaterThanOrEqualTo(RamuriTheme.minTarget),
              reason: k,
            );
            expect(
              size.width,
              greaterThanOrEqualTo(RamuriTheme.minTarget),
              reason: k,
            );
          }
          await tester.tap(key('manual_add'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final k in [
            'manual_date',
            'manual_kind_run',
            'manual_kind_other',
            'manual_rpe_0',
            'manual_rpe_10',
            'manual_save',
          ]) {
            await tester.ensureVisible(key(k));
            final size = tester.getSize(key(k));
            expect(
              size.height,
              greaterThanOrEqualTo(RamuriTheme.minTarget),
              reason: k,
            );
            expect(
              size.width,
              greaterThanOrEqualTo(RamuriTheme.minTarget),
              reason: k,
            );
          }
          await tapKey(tester, 'manual_save');
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
