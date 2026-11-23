// E2E M2: Profil -> Ziel -> Plan -> heutige Einheit als gefuehrte Einheit (WP24)
// laufen, Abschnittswechsel, Beenden -> Zusammenfassung "Aus dem Plan" ->
// Rueckmeldung "zu schwer" und Neuberechnung -> Plan angepasst (WP23, Verlauf).
// Zusaetzlich: die Karten-Frage erscheint weder im Lauf noch ueber dem
// Beenden-Dialog, sondern erst in der Zusammenfassung. Geprueft gegen sichtbare
// Keys und gespeicherten Zustand. Synthetische Daten, Ausgabe nur Zaehler.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/l10n/app_localizations.dart';

import 'support/e2e_plan_form.dart';
import 'support/e2e_support.dart';

/// Plan-Menue oeffnen; die Plan-Liste ist lazy, daher nach oben scrollen.
Future<void> _openPlanMenu(WidgetTester t) async {
  for (var i = 0; i < 10 && !has('plan_menu'); i++) {
    await t.drag(
      find.byKey(const Key('plan_list')).first,
      const Offset(0, 500),
    );
    await pumpFor(t, const Duration(milliseconds: 200));
  }
  await tapKey(t, 'plan_menu');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M2: Plan, gefuehrte Einheit, Zusammenfassung, Anpassung',
    reportingFailures((t) async {
      step('M2 start');
      final w = buildWorld();
      await startApp(t, w);
      await setupIfShown(t);
      final s = await session(t, w);
      expect(
        await t.runAsync(() => (s as GoalStorage).goals.goal()),
        isNull,
        reason: 'Test erwartet frischen Speicher ohne Ziel',
      );

      step('M2 profil');
      // Profil ueber die Oberflaeche.
      await enterProfile(t, s);

      step('M2 tageswechsel_abwarten');
      // Kurz vor Mitternacht erst den Tageswechsel abwarten: Der Lauftag wird jetzt festgelegt, die Einheit muss
      // beim Start noch auf "heute" liegen, und der Lauf (ca. 6 min) darf Mitternacht nicht ueberqueren.
      await waitPastLateEvening(t);
      step('M2 ziel_anlegen');
      // Ziel anlegen: heutiger Wochentag ist Lauftag, damit heute eine Einheit liegt.
      final today = DateTime.now().weekday;
      int wd(int add) => ((today - 1 + add) % 7) + 1;
      await tapKey(t, 'home_plan');
      await waitFor(t, () => has('plan_empty'), 'Plan leer');
      await tapKey(t, 'plan_create_goal');
      await waitFor(t, () => has('plan_form'), 'Zielformular');
      await setRunDays(t, {today, wd(2), wd(4)});
      await enterField(t, 'plan_form_max_session', '45');
      // Kein Wochenstand und "keine 30 min am Stueck": Geh-Lauf-Plan mit kurzen
      // Abschnitten, damit die Fuehrung den Abschnitt wechselt.
      await revealInPlanForm(t, 'plan_form_weekly');
      if (has('plan_form_weekly')) await enterField(t, 'plan_form_weekly', '');
      final l10n = AppLocalizations.of(t.element(find.byType(Scaffold).last));
      final no = find.descendant(
        of: find.byKey(const Key('plan_form_can30')),
        matching: find.text(l10n.planFormNo),
      );
      await tapUntil(
        t,
        no,
        () => can30State() == ContinuousRun30.no,
        'plan_form_can30 Nein',
        reveal: () => revealInPlanForm(t, 'plan_form_can30'),
      );
      step('M2 can30_pruefen');
      // Harte Pruefung: am Ende ist "Nein" gewaehlt.
      await revealInPlanForm(t, 'plan_form_can30');
      final can30 = can30State();
      if (can30 != ContinuousRun30.no) {
        logPub(
          'M2 plan_form_can30 nicht_nein im_baum=${can30 == null ? 'nein' : 'ja'}',
        );
        fail('plan_form_can30 nicht Nein');
      }
      await revealInPlanForm(t, 'plan_form_date_pick');
      await pickTargetDate(t);
      await checkAndSaveGoal(t, 'M2');
      final plans = (s as PlanStorage).plans;
      var history = (await t.runAsync(plans.history))!;
      log('M2 plan_versions=${history.length}');
      expect(history, hasLength(1), reason: 'Plan entsteht');
      await waitFor(t, () => has('plan_goal_card'), 'Zielkarte');
      await tapKey(t, 'home_today');

      step('M2 einheit_starten');
      // Heute: Einheit starten (gefuehrt).
      // Einheiten um heute ins Log (nur Zaehler); die Frist des Wechsels nach Zeit
      // braucht dieser Test nicht, er springt per Knopf.
      await firstSegmentSecondsToday(t, plans, 'M2');
      await waitFor(t, () => has('home_start_unit'), 'heutige Einheit');
      log('M2 unit_today_len=${txt('home_today_unit').length}');
      await tapKey(t, 'home_start_unit');
      await waitFor(t, () => has('run_start_ready'), 'Start-Seite bereit');
      expect(has('guided_card'), isTrue, reason: 'gefuehrte Einheit angeboten');
      expect(has('map_consent_dialog'), isFalse);
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (!has('start_gps_good')) {
        if (DateTime.now().isAfter(end)) {
          log(
            'M2 gps_diag blocked=${has('start_gps_blocked')} searching=${has('start_gps_searching')} ask=${has('run_block_ask')} recheck=${has('run_block_recheck')} checking=${has('run_checking')}',
          );
          fail('GPS gut nicht erreicht');
        }
        if (has('run_block_recheck')) await tapKey(t, 'run_block_recheck');
        // Die Start-Seite ist eine lazy Liste: GPS-Zeile liegt unter der Einheit.
        if (!has('start_gps_good') && !has('start_gps_searching')) {
          await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
        }
        await pumpFor(t, const Duration(seconds: 1));
      }
      await tapKey(t, 'run_start_ready');
      await waitFor(t, () => has('guided_section'), 'Fuehrungsseite');
      log('M2 guided_started run_time_built=${has('run_time')}');

      step('M2 abschnittswechsel');
      // Abschnitt überspringen (FR-0218) statt auf den Wechsel nach Zeit zu
      // warten: erst überspringen und „Rückgängig“ (der Abschnitt ist wieder
      // da), dann überspringen und den Wechsel prüfen.
      final first = txt('guided_section');
      await tapVisible(t, 'guided_skip');
      await waitFor(
        t,
        () => txt('guided_section') != first,
        'Wechsel nach Ueberspringen (guided_section)',
      );
      await waitFor(
        t,
        () => has('guided_skip_undo'),
        'Hinweis Rueckgaengig (guided_skip_undo)',
      );
      await tapVisible(t, 'guided_skip_undo');
      await waitFor(
        t,
        () => txt('guided_section') == first,
        'Abschnitt nach Rueckgaengig (guided_section)',
      );
      log('M2 skip_undone');
      // Der Hinweis des ersten Sprungs ist weg, bevor erneut gesprungen wird.
      await waitFor(t, () => !has('guided_skip_undo'), 'Hinweis zu');
      await tapVisible(t, 'guided_skip');
      await waitFor(
        t,
        () => txt('guided_section') != first,
        'Wechsel nach Ueberspringen (guided_section)',
      );
      expect(
        has('map_consent_dialog'),
        isFalse,
        reason: 'Karten-Frage im Lauf',
      );
      log('M2 section_changed');
      // Der Sprung verkürzt den Lauf auf wenige Sekunden. Damit die
      // Zusammenfassung eine Route hat (sonst keine Karte und keine
      // Karten-Frage), laufen, bis genug Positionen gespeichert sind.
      final routeDl = DateTime.now().add(const Duration(seconds: 90));
      while ((await countRuns(t, w)).first.positions < 15) {
        if (DateTime.now().isAfter(routeDl)) {
          fail('keine Positionen fuer die Route in 90 s');
        }
        expect(
          has('map_consent_dialog'),
          isFalse,
          reason: 'Karten-Frage im Lauf',
        );
        await pumpFor(t, const Duration(seconds: 1));
      }
      log('M2 route_recorded');

      step('M2 beenden');
      // Beenden: kein Karten-Dialog davor oder darueber.
      await tapVisible(t, 'run_pause');
      await waitFor(t, () => has('run_resume'), 'Pause (run_resume)');
      await tapVisible(t, 'run_finish');
      await waitFor(t, () => has('run_finish_confirm'), 'Beenden-Dialog');
      expect(
        has('map_consent_dialog'),
        isFalse,
        reason: 'Karten-Frage ueber Beenden',
      );
      await tapDialog(t, 'run_finish_confirm');
      await waitFor(t, () => has('run_done_status'), 'Laufende angezeigt');
      expect(has('map_consent_dialog'), isFalse);
      final runs = await countRunsFinished(t, w);
      expect(runs.first.state, RunState.finished);

      step('M2 zusammenfassung');
      // Zusammenfassung (auf der Laufende-Seite): erst jetzt kommt die Karten-Frage.
      await waitFor(
        t,
        () => has('map_consent_dialog'),
        'Karten-Frage in der Zusammenfassung',
      );
      log('M2 consent_in_summary sum_from_plan=${has('sum_from_plan')}');
      await tapDialog(t, 'map_consent_not_now');
      await waitFor(t, () => !has('map_consent_dialog'), 'Karten-Frage zu');
      await waitFor(t, () => has('sum_from_plan'), 'Aus dem Plan');
      log('M2 sum_from_plan');
      await tapKey(t, 'run_done_close');
      await waitFor(t, () => has('home_plan'), 'Heute');
      await waitFor(t, () => has('home_today_done'), 'Einheit als erledigt');
      // Erledigt mit Bewegungszeit und Strecke des Laufs (FR-0171).
      await waitFor(
        t,
        () => has('home_today_done_run'),
        'Lauf an der erledigten Einheit',
      );
      log(
        'E2E home_today_done_run='
        '${t.widget<Text>(find.byKey(const Key('home_today_done_run'))).data}',
      );

      step('M2 rueckmeldung');
      // Rueckmeldung "zu schwer" und Neuberechnen: Plan angepasst, Verlauf.
      final before = (await t.runAsync(plans.history))!.length;
      await tapKey(t, 'home_plan');
      await waitFor(t, () => has('plan_goal_card'), 'Plan');
      await _openPlanMenu(t);
      await waitFor(t, () => has('plan_menu_feedback'), 'Menue');
      await tapDialog(t, 'plan_menu_feedback');
      await waitFor(t, () => has('plan_feedback_sheet'), 'Rueckmeldung');
      await tapDialog(t, 'plan_feedback_too_hard');
      await waitFor(
        t,
        () => has('plan_feedback_done'),
        'Rueckmeldung gespeichert',
      );
      history = (await t.runAsync(plans.history))!;
      // "Zu schwer" legt nur dann eine Fassung an, wenn sich die Einheiten aendern
      // (im kleinsten Geh-Lauf-Plan kann das ausbleiben); die Meldung sagt es.
      final changed = history.length > before;
      log('M2 feedback versions_before=$before after=${history.length}');
      if (changed) expect(history.last.trigger, PlanTrigger.feedback);
      // Die Meldung sagt, ob eine neue Fassung entstand (Teil G: im kleinsten
      // Geh-Lauf-Plan bleibt der Plan, wie er ist).
      final fb = AppLocalizations.of(t.element(find.byType(Scaffold).last));
      expect(
        find.descendant(
          of: find.byKey(const Key('plan_feedback_done')),
          matching: find.text(
            changed ? fb.planFeedbackChanged : fb.planFeedbackSame,
          ),
        ),
        findsOneWidget,
        reason: 'Meldung zur Rueckmeldung "zu schwer" passt zur Fassung',
      );

      step('M2 ziel_aendern');
      // Ziel aendern (vierter Lauftag): neue Fassung mit Erklaerung (WP23).
      ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await pumpFor(t, const Duration(milliseconds: 300));
      final versions = history.length;
      await tapKey(t, 'plan_edit_goal');
      await waitFor(t, () => has('plan_form'), 'Zielformular (Aendern)');
      await revealInPlanForm(t, 'plan_form_day_${wd(1)}');
      final was = daySelected(t, wd(1));
      await tapUntil(
        t,
        find.byKey(Key('plan_form_day_${wd(1)}')),
        () {
          final now = dayState(wd(1));
          return now != null && now != was;
        },
        'plan_form_day_${wd(1)}',
        reveal: () => revealInPlanForm(t, 'plan_form_day_${wd(1)}'),
      );
      await checkAndSaveGoal(t, 'M2');
      history = (await t.runAsync(plans.history))!;
      expect(
        history.length,
        versions + 1,
        reason: 'Zielaenderung: neue Fassung',
      );
      expect(history.last.trigger, PlanTrigger.goalChange);
      await waitFor(t, () => has('plan_change_card'), 'Aenderungskarte');
      expect(
        has('plan_change_reason'),
        isTrue,
        reason: 'Erklaerung der Aenderung',
      );
      log('M2 plan_changed versions=${history.length}');

      ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await pumpFor(t, const Duration(milliseconds: 300));
      step('M2 neu_berechnen');
      await tapKey(t, 'plan_recalculate');
      await waitFor(t, () => has('plan_recalculate_dialog'), 'Rueckfrage');
      await tapDialog(t, 'plan_recalculate_confirm');
      await waitFor(t, () => has('plan_recalculated'), 'neu berechnet');

      step('M2 planverlauf');
      await _openPlanMenu(t);
      await waitFor(t, () => has('plan_menu_history'), 'Menue');
      await tapDialog(t, 'plan_menu_history');
      await waitFor(t, () => has('plan_history'), 'Verlauf der Planfassungen');
    }),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
