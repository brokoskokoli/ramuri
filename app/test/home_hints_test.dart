import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_recovery.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/l10n/app_localizations_de.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun, text;

// WP23 Teil D2, „Heute“: wöchentliche Prüfung beim Öffnen, Karte „Erholung“
// (nur Texthinweis, ohne Auslöser ausgeblendet), „Locker laufen“, Pausenfrage
// (PAR-202), Erinnerung unter Warnsignal und Karte „Plan angepasst“. Alle
// Werte sind erfunden.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, 11.11.2026, mittags (UTC, Versatz 0).
final _now = DateTime.utc(2026, 11, 11, 12);
final _created = DateTime.utc(2026, 11, 2, 12); // Montag der Vorwoche

TrainingGoal _goal([ContinuousRun30 canRun30 = ContinuousRun30.yes]) =>
    TrainingGoal(
      type: GoalType.distance,
      distance: GoalDistance.tenKilometers,
      targetDate: DateTime.utc(2027, 3, 14),
      runDays: const {1, 3, 5},
      maxSessionSeconds: 7200,
      weeklyCapSeconds: 240 * 60.0,
      createdAt: DateTime.utc(2026, 11, 1),
      hardSessionEnabled: false,
      canRun30: canRun30,
    );

PlanController _controller(Device d, StorageSession s) => PlanController(
  session: s,
  clock: d.clock,
  reader: PlanDataReader(
    session: s,
    clock: d.clock,
    loadRuns: () async => const [],
  ),
);

/// Speicher vor dem Start: Einrichtung erledigt, Ziel und erste Fassung an
/// [created]; danach gilt [_now]. Mit [checked] gilt die wöchentliche Prüfung
/// als erledigt (sonst ist sie fällig).
Future<StorageSession> _preopen(
  Device d, {
  bool plan = true,
  bool checked = true,
  ContinuousRun30 canRun30 = ContinuousRun30.yes,
}) async {
  d.clock.set(_created);
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  if (plan) {
    final c = _controller(d, s);
    expect(await c.saveGoal(_goal(canRun30)), PlanActionResult.done);
    c.dispose();
  }
  d.clock.set(_now);
  if (checked && plan) {
    await s.settings.set(planLastCheckDayKey, '2026-11-11', at: _now);
  }
  return s;
}

/// Ein beendeter Lauf [daysAgo] Tage vor heute (mittags), optional mit
/// Befinden und Anstrengung.
Future<int> _run(
  StorageSession s,
  int daysAgo, {
  int minutes = 20,
  int? wellbeing,
  int? rpe,
}) async {
  final id = await seedRun(
    s,
    _now.subtract(Duration(days: daysAgo, hours: 1)),
    minutes: minutes,
  );
  if (wellbeing != null || rpe != null) {
    await s.subjective.save(id, RunSubjective(wellbeing: wellbeing, rpe: rpe));
  }
  return id;
}

/// Heute ist eine intensive Einheit geplant (statt der gespeicherten).
Future<void> _hardToday(StorageSession s) async {
  final plans = (s as PlanStorage).plans;
  final last = (await plans.history()).last;
  final all = await plans.unitsBetween(
    planDay(last.inputs.anchor),
    DateTime.utc(2028),
  );
  final today = DateTime.utc(2026, 11, 11);
  await plans.writeVersion(
    PlanVersionDraft(
      createdAt: _now,
      validFrom: today,
      trigger: last.trigger,
      reason: last.reason,
      version: last.version,
      inputs: last.inputs,
      summary: last.summary,
      units: [
        for (final u in all)
          if (!u.day.isBefore(today))
            PlanUnit(
              day: u.day,
              kind: isoDay(u.day) == isoDay(today)
                  ? PlanUnitKind.intervals
                  : u.kind,
              phase: u.phase,
              weekIndex: u.weekIndex,
              minutes: u.minutes,
              segments: u.segments,
            ),
      ],
      readState: planUnitsFingerprint(all),
    ),
  );
}

PlanRepository plansOf(StorageSession s) => (s as PlanStorage).plans;

Future<void> _pumpSettle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

Future<List<PlanVersionRecord>> _history(StorageSession s) =>
    (s as PlanStorage).plans.history();

void main() {
  group('wöchentliche Prüfung beim Öffnen von „Heute“ (FR-0158)', () {
    testWidgets('fällig: Heute prüft wie die Plan-Seite', (tester) async {
      final d = Device();
      final s = await _preopen(d, checked: false);
      expect(await s.settings.get(planLastCheckDayKey), '2026-11-02');
      await d.start(tester, const Locale('de'));
      expect(await s.settings.get(planLastCheckDayKey), '2026-11-11');
    });

    testWidgets('nicht fällig: Öffnen ändert nichts', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      final before = (await _history(s)).length;
      await d.start(tester, const Locale('de'));
      expect((await _history(s)).length, before);
    });
  });

  group('Karte „Erholung“', () {
    testWidgets('ohne Auslöser ausgeblendet, nie eine positive Meldung', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 2, rpe: 3, wellbeing: 4);
      await d.start(tester, const Locale('de'));
      expect(key('home_today_plan'), findsOneWidget);
      expect(key('home_recovery_card'), findsNothing);
      expect(find.text('Erholung'), findsNothing);
      expect(find.textContaining('erholt'), findsNothing);
    });

    for (final (name, dark, locale, width, scale) in [
      ('hell, de', false, 'de', 411.0, 1.0),
      ('dunkel, en, 320 dp, Schrift 2.0', true, 'en', 320.0, 2.0),
    ]) {
      testWidgets('niedriges Befinden: Text, Belege, ohne Zahl ($name)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 2600);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (dark) {
          tester.platformDispatcher.platformBrightnessTestValue =
              Brightness.dark;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
        }
        final d = Device();
        final s = await _preopen(d);
        await _run(s, 1, wellbeing: 1);
        await d.start(tester, Locale(locale));
        final de = locale == 'de';
        expect(key('home_recovery_card'), findsOneWidget);
        expect(
          text('home_recovery_text'),
          de
              ? 'Du hast dein Befinden beim letzten Lauf als niedrig '
                    'angegeben. Für heute wird ein lockerer Lauf oder ein '
                    'Ruhetag empfohlen.'
              : 'You rated how you felt on your last run as low. An easy run '
                    'or a rest day is recommended for today.',
        );
        expect(find.text(de ? 'Erholung' : 'Recovery'), findsNothing);
        expect(find.text(de ? 'ERHOLUNG' : 'RECOVERY'), findsOneWidget);
        // Keine Zahl auf der Karte.
        final card = find.descendant(
          of: key('home_recovery_card'),
          matching: find.byType(Text),
        );
        for (final t in tester.widgetList<Text>(card)) {
          expect(RegExp(r'\d').hasMatch(t.data ?? ''), isFalse);
        }
        await tester.ensureVisible(key('home_recovery_basis'));
        expect(
          tester.getSize(key('home_recovery_basis')).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(key('home_recovery_basis'));
        await tester.pumpAndSettle();
        expect(key('home_recovery_basis_dialog'), findsOneWidget);
        expect(
          text('home_recovery_basis_0'),
          de
              ? 'Befinden beim letzten Lauf: sehr schlecht, gestern.'
              : 'How you felt on the last run: very bad, yesterday.',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(key('home_recovery_basis_close'));
        await tester.pumpAndSettle();
        expect(key('home_recovery_basis_dialog'), findsNothing);
      });
    }

    testWidgets('Pause nach Zusage „alles erfasst“: Text mit Tagen und Beleg', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 9);
      await LoadSettings.saveAllRecorded(s.settings, true, at: _now);
      await d.start(tester, const Locale('de'));
      expect(
        text('home_recovery_text'),
        startsWith('Dein letztes erfasstes Training liegt 9 Tage zurück.'),
      );
      // Mit der Zusage keine Pausenfrage (PAR-202).
      expect(key('home_pause_card'), findsNothing);
      await tester.tap(key('home_recovery_basis'));
      await tester.pumpAndSettle();
      expect(find.text('Du hast zugesagt, alles zu erfassen.'), findsOneWidget);
    });

    testWidgets(
      'Zusage „alles erfasst“: Neustart beim Öffnen, einmal je Pause, '
      'Text nennt ihn',
      (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await _run(s, 12, minutes: 30);
        await LoadSettings.saveAllRecorded(s.settings, true, at: _now);
        final before = (await _history(s)).length;
        await d.start(tester, const Locale('de'));
        final h = await _history(s);
        expect(h.length, before + 1);
        expect(h.last.trigger, PlanTrigger.pause);
        expect(
          text('home_recovery_text'),
          contains('Der Plan beginnt deshalb ruhiger'),
        );
        // Erneutes Öffnen (Heute und Plan): keine weitere Fassung.
        final c = _controller(d, s);
        await c.open();
        c.dispose();
        expect((await _history(s)).length, before + 1);
      },
    );

    testWidgets(
      'Zusage „alles erfasst“ in der Geh-Lauf-Abfolge: kein Neustart, '
      'Text ohne Aussage über den Plan',
      (tester) async {
        final d = Device();
        final s = await _preopen(d, canRun30: ContinuousRun30.no);
        await _run(s, 12, minutes: 30);
        await LoadSettings.saveAllRecorded(s.settings, true, at: _now);
        final before = (await _history(s)).length;
        await d.start(tester, const Locale('de'));
        expect((await _history(s)).length, before);
        expect(
          text('home_recovery_text'),
          'Dein letztes erfasstes Training liegt 12 Tage zurück. '
          'Starte ruhig und hole Ausgefallenes nicht nach.',
        );
      },
    );

    testWidgets(
      'lange Pause (PAR-181): vorläufig Stufe 2 statt altem Plan, Wortlaut der '
      'Spezifikation, Knopf zur Wahl; die Wahl ersetzt die Vorgabe',
      (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await _run(s, 70, minutes: 30);
        await LoadSettings.saveAllRecorded(s.settings, true, at: _now);
        final before = (await _history(s)).length;
        await d.start(tester, const Locale('de'));
        // Sichere Vorgabe bis zur Wahl: Stufe 2 (2 Wochen ohne harte Einheit).
        var h = await _history(s);
        expect(h.length, before + 1);
        expect(h.last.trigger, PlanTrigger.pause);
        final noHard = h.last.inputs.noHardUntil!;
        expect(noHard.difference(h.last.inputs.anchor).inDays, 13);
        expect(
          text('home_recovery_text'),
          'Dein letztes erfasstes Training liegt 70 Tage zurück. '
          'Wir schlagen dir einen neuen Einstieg vor. '
          'Du kannst dabei wählen, wie du startest.',
        );
        expect(
          tester.getSize(key('home_recovery_new_start')).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(key('home_recovery_new_start'));
        await tester.pumpAndSettle();
        expect(text('plan_form_title'), 'Neuer Einstieg');
        // Der Stand wird neu gefragt, nicht übernommen.
        expect(key('plan_form_weekly'), findsOneWidget);
        expect(
          tester.widget<TextField>(key('plan_form_weekly')).controller!.text,
          isEmpty,
        );
        await tester.enterText(key('plan_form_weekly'), '75');
        await tester.pumpAndSettle();
        await tester.ensureVisible(key('plan_form_check'));
        await tester.tap(key('plan_form_check'));
        await _pumpSettle(tester);
        await tester.ensureVisible(key('plan_form_save'));
        await tester.tap(key('plan_form_save'));
        await _pumpSettle(tester);
        h = await _history(s);
        expect(h.length, before + 2);
        expect(h.last.trigger, PlanTrigger.goalChange);
        expect(h.last.inputs.startWeeklyMinutes, 75);
        // Die Wahl ersetzt die Vorgabe: keine Sperre für harte Einheiten mehr.
        expect(h.last.inputs.noHardUntil, isNull);
        final goal = (await (s as GoalStorage).goals.goal())!;
        expect(goal.currentWeeklySeconds, 75 * 60);
        // Gewählt: kein Knopf mehr, keine Aussage über den Plan.
        expect(key('home_recovery_new_start'), findsNothing);
        expect(
          text('home_recovery_text'),
          'Dein letztes erfasstes Training liegt 70 Tage zurück. '
          'Starte ruhig und hole Ausgefallenes nicht nach.',
        );
      },
    );

    testWidgets('lange Pause: „Ja“ der Pausenfrage setzt die vorläufige '
        'Vorgabe, der Einstieg bleibt wählbar', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 70, minutes: 30);
      final before = (await _history(s)).length;
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_pause_yes'));
      await _pumpSettle(tester);
      final h = await _history(s);
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.pause);
      expect(key('home_recovery_new_start'), findsOneWidget);
    });

    testWidgets(
      '„Locker laufen“ ersetzt die heutige Einheit nach Bestätigung',
      (tester) async {
        final d = Device();
        final s = await _preopen(d);
        await _hardToday(s);
        await _run(s, 1, wellbeing: 1);
        await d.start(tester, const Locale('de'));
        expect(key('home_recovery_easy'), findsOneWidget);
        expect(
          tester.getSize(key('home_recovery_easy')).height,
          greaterThanOrEqualTo(48),
        );
        // Abbrechen ändert nichts.
        await tester.tap(key('home_recovery_easy'));
        await tester.pumpAndSettle();
        expect(key('home_easy_dialog'), findsOneWidget);
        await tester.tap(key('home_easy_cancel'));
        await tester.pumpAndSettle();
        var unit = (await (s as PlanStorage).plans.unitOn(
          DateTime.utc(2026, 11, 11),
        ))!;
        expect(unit.kind, PlanUnitKind.intervals);
        // Bestätigen ersetzt.
        await tester.tap(key('home_recovery_easy'));
        await tester.pumpAndSettle();
        await tester.tap(key('home_easy_confirm'));
        await tester.pumpAndSettle();
        unit = (await plansOf(s).unitOn(DateTime.utc(2026, 11, 11)))!;
        expect(unit.kind, PlanUnitKind.easy);
        expect(key('home_recovery_easy'), findsNothing);
      },
    );

    testWidgets('ohne offene Einheit heute kein Knopf „Locker laufen“', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      final unit = (await (s as PlanStorage).plans.unitOn(
        DateTime.utc(2026, 11, 11),
      ))!;
      await plansOf(s)
          .assignRun(unit.id!, await _run(s, 0, minutes: 10, wellbeing: 1));
      await _run(s, 1, wellbeing: 1);
      await d.start(tester, const Locale('de'));
      expect(key('home_recovery_card'), findsOneWidget);
      expect(key('home_recovery_easy'), findsNothing);
    });
  });

  group('Worauf beruht die heutige Einheit (FR-0179)', () {
    testWidgets('Heute zeigt die Belege zur geplanten Einheit', (tester) async {
      final d = Device();
      await _preopen(d);
      await d.start(tester, const Locale('de'));
      expect(key('home_today_unit'), findsOneWidget);
      await tester.ensureVisible(key('home_today_why'));
      expect(
        tester.getSize(key('home_today_why')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(key('home_today_why'));
      await tester.pumpAndSettle();
      expect(
        text('home_recovery_basis_0'),
        allOf(
          startsWith('Die Einheit „'),
          contains('steht für heute in deinem Plan'),
          // Keine Läufe in der Fassung: sie werden nicht genannt.
          isNot(contains('erfassten Läufen')),
        ),
      );
      await tester.tap(key('home_recovery_basis_close'));
      await tester.pumpAndSettle();
      expect(key('home_recovery_basis_dialog'), findsNothing);
    });

    test('mit Läufen in der Fassung nennt der Text sie', () {
      final unit = PlanUnit(
        day: DateTime.utc(2026, 11, 11),
        kind: PlanUnitKind.easy,
        phase: PlanPhase.build,
        weekIndex: 0,
        minutes: 30,
        segments: const [],
      );
      final l = AppLocalizationsDe();
      expect(
        trainingBasisLines(l, unit, withRuns: true)!.single,
        contains('erfassten Läufen'),
      );
      expect(
        trainingBasisLines(l, unit, withRuns: false)!.single,
        isNot(contains('Läufen')),
      );
    });

    testWidgets('ohne Plan kein Einstieg', (tester) async {
      final d = Device();
      await _preopen(d, plan: false);
      await d.start(tester, const Locale('de'));
      expect(key('home_today_why'), findsNothing);
    });
  });

  group('Pausenfrage (PAR-202)', () {
    testWidgets('unter 7 Tagen keine Frage', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 7);
      await _run(s, 6);
      await d.start(tester, const Locale('de'));
      // Der neueste Lauf gilt: 6 Tage, noch keine Frage.
      expect(key('home_pause_card'), findsNothing);
    });

    testWidgets('ab 7 Tagen ohne Training: Frage, „Nein“ ändert nichts und '
        'sie kommt nicht wieder', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 8);
      final before = (await _history(s)).length;
      await d.start(tester, const Locale('de'));
      expect(text('home_pause_text'), contains('8 Tage'));
      expect(
        tester.getSize(key('home_pause_no')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(key('home_pause_no'));
      await _pumpSettle(tester);
      expect(key('home_pause_card'), findsNothing);
      expect((await _history(s)).length, before);
      final a = await WarningState(s.settings).pauseAnswer();
      expect(a!.paused, isFalse);
      final q = await HintService(session: s, clock: d.clock).pauseQuestion();
      expect(q, isNull);
    });

    testWidgets('„Ja“ startet den Plan neu (Auslöser pause) und merkt die '
        'Antwort', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 12, minutes: 30);
      final before = (await _history(s)).length;
      await d.start(tester, const Locale('de'));
      expect(key('home_pause_card'), findsOneWidget);
      await tester.tap(key('home_pause_yes'));
      await _pumpSettle(tester);
      final h = await _history(s);
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.pause);
      expect(key('home_pause_card'), findsNothing);
      final a = await WarningState(s.settings).pauseAnswer();
      expect(a!.paused, isTrue);
      // Die Pause ist bestätigt: der Hinweis PAR-180 steht auf der Karte.
      expect(
        text('home_recovery_text'),
        startsWith('Dein letztes erfasstes Training liegt 12 Tage zurück.'),
      );
    });

    testWidgets('nach „alles erfasst“ keine Frage', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 10);
      await LoadSettings.saveAllRecorded(s.settings, true, at: _now);
      await d.start(tester, const Locale('de'));
      expect(key('home_pause_card'), findsNothing);
    });

    testWidgets('unter Warnsignal keine Frage', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _run(s, 10);
      await (s as WarningStorage).warning.set(
        WarningSignal(
          reportedOn: DateTime.utc(2026, 11, 10),
          source: WarningSource.manual,
        ),
      );
      await d.start(tester, const Locale('de'));
      expect(key('home_pause_card'), findsNothing);
    });
  });

  group('Warnsignal und „Plan angepasst“ auf „Heute“', () {
    testWidgets('Erinnerung nach 7 Tagen, Warntext, keine zweite Karte; '
        'Aufheben zeigt „Plan angepasst“ bis „Verstanden“', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      d.clock.set(DateTime.utc(2026, 11, 4, 12));
      final c = _controller(d, s);
      expect(await c.reportWarning(), PlanActionResult.done);
      c.dispose();
      d.clock.set(_now);
      await s.settings.set(planLastCheckDayKey, '2026-11-11', at: _now);

      await d.start(tester, const Locale('de'));
      // Fester Text aus FR-0203, Erinnerung, aber nicht die Karte mit dem
      // Grund „warning“.
      expect(
        text('home_recovery_text'),
        endsWith('Diese App stellt keine Diagnose.'),
      );
      expect(key('home_warning_reminder'), findsOneWidget);
      expect(key('plan_change_card'), findsNothing);
      expect(key('home_pause_card'), findsNothing);

      await tester.ensureVisible(key('home_warning_lift'));
      expect(
        tester.getSize(key('home_warning_lift')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(key('home_warning_lift'));
      await _pumpSettle(tester);
      expect(key('home_warning_reminder'), findsNothing);
      expect(key('home_recovery_card'), findsNothing);
      expect(key('plan_change_card'), findsOneWidget);
      expect(
        text('plan_change_reason'),
        'Du hast die Meldung aufgehoben, deshalb gilt dein Plan wieder.',
      );
      await tester.tap(key('plan_change_seen'));
      await _pumpSettle(tester);
      expect(key('plan_change_card'), findsNothing);
      final seen = await WarningState(s.settings).planChangeSeen();
      expect(seen, (await _history(s)).last.id);
    });

    testWidgets('vor 7 Tagen keine Erinnerung', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await (s as WarningStorage).warning.set(
        WarningSignal(
          reportedOn: DateTime.utc(2026, 11, 5),
          source: WarningSource.manual,
        ),
      );
      await d.start(tester, const Locale('de'));
      expect(key('home_recovery_card'), findsOneWidget);
      expect(key('home_warning_reminder'), findsNothing);
    });
  });
}
