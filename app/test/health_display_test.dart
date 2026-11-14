import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show started;
import 'statistics_test.dart' show openStats;

/// Anzeige importierter Health-Connect-Daten (WP32 Teil E, K62 F2, FR-0024,
/// SEC-0005). Heute ist Mittwoch, der 17. Juni 2026. Alle Daten sind synthetisch.
final DateTime _now = DateTime.utc(2026, 6, 17, 12);

HealthRecord _exercise(String id, {String origin = 'app.beispiel.uhr'}) =>
    HealthRecord(
      kind: HealthDataKind.exercise,
      id: id,
      origin: origin,
      start: DateTime.utc(2026, 6, 16, 17, 5),
      end: DateTime.utc(2026, 6, 16, 17, 49),
      offsetSeconds: 0,
      exerciseType: 56,
    );

HealthRecord _vo2(String id, String origin, DateTime t, double v) =>
    HealthRecord(
      kind: HealthDataKind.vo2Max,
      id: id,
      origin: origin,
      start: t,
      end: t,
      value: v,
      unit: 'ml/min/kg',
    );

HealthImportStore _health(Device d) => (d.session as HealthStorage).health;

Future<Device> _start(WidgetTester tester) async {
  final d = await started(tester);
  d.clock.set(_now);
  return d;
}

Future<void> _openHistoryAll(WidgetTester tester) async {
  await tester.tap(key('home_history'));
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(of: key('history_range'), matching: find.byType(InkWell))
        .last,
  );
  await tester.pumpAndSettle();
}

String _text(String k) => (key(k).evaluate().single.widget as Text).data!;

void main() {
  group('Verlauf und Detail importierter Einheiten', () {
    testWidgets('gekennzeichnet mit Quelle, Summen zählen nur eigene Läufe', (
      tester,
    ) async {
      final d = await _start(tester);
      await _health(d).upsertExercises([_exercise('ex-1')]);
      await _openHistoryAll(tester);

      expect(key('health_exercise_ex-1'), findsOneWidget);
      expect(find.text('aus Health Connect'), findsOneWidget);
      expect(
        _text('health_exercise_source_ex-1'),
        'Quelle: app.beispiel.uhr · nur Anzeige',
      );
      expect(
        find.text(
          'Nur eigene Läufe. Importierte zählen erst nach dem Übernehmen.',
        ),
        findsOneWidget,
      );
      // Keine Läufe: keine Wochensummen aus der fremden Einheit.
      expect(key('history_total_runs'), findsNothing);
      // Nichts eingetragen, nichts übernommen.
      expect(await d.session.manualTrainings.list(), isEmpty);
    });

    testWidgets(
      'Detail zeigt Quelle und Pulskurve, Übernehmen mit Vorbelegung',
      (tester) async {
        final d = await _start(tester);
        final h = _health(d);
        await h.upsertExercises([_exercise('ex-1')]);
        await h.replaceExerciseHeartRate('ex-1', [
          for (var i = 0; i < 20; i++)
            HealthHeartRateSample(
              DateTime.utc(2026, 6, 16, 17, 5 + i),
              120 + i,
            ),
        ]);
        await _openHistoryAll(tester);
        await tapKey(tester, 'health_exercise_ex-1');

        expect(
          _text('health_detail_origin'),
          'aus Health Connect, Quelle: app.beispiel.uhr',
        );
        expect(_text('health_detail_duration'), '44 min');
        expect(key('health_detail_pulse'), findsOneWidget);
        expect(
          find.text('ohne Zonen, da nicht mit ramuri gemessen'),
          findsOneWidget,
        );
        expect(key('health_take'), findsOneWidget);
        expect(key('health_take_hint'), findsOneWidget);
        // Vor dem Übernehmen: nichts eingetragen.
        expect(await d.session.manualTrainings.list(), isEmpty);

        await tapKey(tester, 'health_take');
        // Dauer vorausgefüllt, Anstrengung fragt die App (Pflicht).
        expect(
          (tester.widget(key('manual_minutes')) as TextField).controller!.text,
          '44',
        );
        await tapKey(tester, 'manual_save');
        expect(find.text('Bitte die Anstrengung wählen.'), findsOneWidget);
        expect(await d.session.manualTrainings.list(), isEmpty);
        await tapKey(tester, 'manual_rpe_5');
        await tapKey(tester, 'manual_save');

        final list = await d.session.manualTrainings.list();
        expect(list, hasLength(1));
        expect(list.single.training.hcId, 'ex-1');
        expect(list.single.training.duration, const Duration(minutes: 44));
        expect(list.single.training.kind, ManualTrainingKind.run);
        expect(list.single.training.isoDay, '2026-06-16');
        // Detail: übernommen statt Knopf, kein zweites Übernehmen.
        expect(key('health_taken'), findsOneWidget);
        expect(key('health_take'), findsNothing);
      },
    );

    testWidgets(
      'schon übernommene Einheit: „übernommen“ im Verlauf, kein Knopf',
      (tester) async {
        final d = await _start(tester);
        await _health(d).upsertExercises([_exercise('ex-1')]);
        await d.session.manualTrainings.add(
          ManualTraining(
            day: DateTime.utc(2026, 6, 16),
            kind: ManualTrainingKind.run,
            duration: const Duration(minutes: 44),
            rpe: 4,
            hcId: 'ex-1',
          ),
        );
        await _openHistoryAll(tester);
        expect(key('health_exercise_taken_ex-1'), findsOneWidget);
        await tapKey(tester, 'health_exercise_ex-1');
        expect(key('health_taken'), findsOneWidget);
        expect(key('health_take'), findsNothing);
      },
    );
    testWidgets(
      'übernommenen Nachtrag ändern: hcId bleibt, weiter „übernommen“',
      (tester) async {
        final d = await _start(tester);
        await _health(d).upsertExercises([_exercise('ex-1')]);
        final stored = await d.session.manualTrainings.add(
          ManualTraining(
            day: DateTime.utc(2026, 6, 16),
            kind: ManualTrainingKind.run,
            duration: const Duration(minutes: 44),
            rpe: 4,
            hcId: 'ex-1',
          ),
        );
        await _openHistoryAll(tester);
        await tapKey(tester, 'manual_training_${stored.id}');
        await tester.enterText(key('manual_minutes'), '50');
        await tapKey(tester, 'manual_save');

        final list = await d.session.manualTrainings.list();
        expect(list.single.training.duration, const Duration(minutes: 50));
        expect(list.single.training.hcId, 'ex-1');
        // Die Einheit lässt sich nicht erneut übernehmen.
        expect(key('health_exercise_taken_ex-1'), findsOneWidget);
        await tapKey(tester, 'health_exercise_ex-1');
        expect(key('health_taken'), findsOneWidget);
        expect(key('health_take'), findsNothing);
      },
    );

    for (final dark in [false, true]) {
      testWidgets('Verlauf-Kachel und Detail ohne Überlauf, schmal, großer Text'
          '${dark ? ', dunkel' : ''}', (tester) async {
        final d = await _start(tester);
        final h = _health(d);
        await h.upsertExercises([_exercise('ex-1')]);
        await h.replaceExerciseHeartRate('ex-1', [
          for (var i = 0; i < 20; i++)
            HealthHeartRateSample(
              DateTime.utc(2026, 6, 16, 17, 5 + i),
              120 + i,
            ),
        ]);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _openHistoryAll(tester);
        expect(key('health_exercise_ex-1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'health_exercise_ex-1');
        expect(key('health_detail_pulse'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Fortschritt: Vergleich fremder VO₂max (FR-0024)', () {
    testWidgets('je Quell-App mit Quelle, getrennt von der eigenen VO₂max', (
      tester,
    ) async {
      final d = await _start(tester);
      final t = DateTime.utc(2026, 6, 15, 8);
      await _health(d).upsertValues([
        _vo2('a1', 'app.beispiel.uhr', t, 48),
        _vo2('a2', 'app.beispiel.uhr', t.add(const Duration(days: 1)), 49),
        _vo2('b1', 'app.beispiel.band', t, 44),
      ]);
      await openStats(d, tester);

      expect(key('health_vo2_card'), findsOneWidget);
      expect(
        _text('health_vo2_source_app.beispiel.uhr'),
        'Quelle: app.beispiel.uhr',
      );
      expect(
        _text('health_vo2_source_app.beispiel.band'),
        'Quelle: app.beispiel.band',
      );
      expect(find.textContaining('49,0'), findsOneWidget);
      expect(find.textContaining('44,0'), findsOneWidget);
      // Eigene Reihe: ohne eigene Läufe kein Wert, die fremden fließen nicht ein.
      expect(key('progress_vo2'), findsNothing);
      expect(key('progress_vo2_reason'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('Vergleichskarte ohne Überlauf, schmal, großer Text'
          '${dark ? ', dunkel' : ''}', (tester) async {
        final d = await _start(tester);
        final t = DateTime.utc(2026, 6, 15, 8);
        await _health(d).upsertValues([
          _vo2('a1', 'app.beispiel.uhr', t, 48),
          _vo2('b1', 'app.beispiel.band', t, 44),
        ]);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await openStats(d, tester);
        expect(key('health_vo2_card'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ohne Importdaten keine Vergleichskarte', (tester) async {
      final d = await _start(tester);
      await openStats(d, tester);
      expect(key('health_vo2_card'), findsNothing);
    });
  });
}
