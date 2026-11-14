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
import 'package:running_app/ui/ui.dart';

import 'support/e2e_support.dart';

Future<void> _enter(WidgetTester t, String key, String text) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.enterText(f, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(t, const Duration(milliseconds: 300));
}

bool _daySelected(WidgetTester t, int weekday) =>
    t.widget<FilterChip>(find.byKey(Key('plan_form_day_$weekday'))).selected;

Future<void> _setDays(WidgetTester t, Set<int> days) async {
  for (var d = 1; d <= 7; d++) {
    final want = days.contains(d);
    if (_daySelected(t, d) != want) {
      await tapUntil(
        t,
        find.byKey(Key('plan_form_day_$d')),
        () => _daySelected(t, d) == want,
        'plan_form_day_$d',
      );
    }
  }
}

Future<void> _pickTargetDate(WidgetTester t) async {
  await tapKey(t, 'plan_form_date_pick');
  await waitFor(
    t,
    () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
    'Datumsdialog',
  );
  for (var i = 0; i < 4; i++) {
    await t.tap(find.byIcon(Icons.chevron_right).first);
    await pumpFor(t, const Duration(milliseconds: 300));
  }
  await t.tap(find.text('15').first);
  await pumpFor(t, const Duration(milliseconds: 300));
  final ok = MaterialLocalizations.of(t.element(find.byType(DatePickerDialog)))
      .okButtonLabel;
  await t.tap(find.text(ok));
  await waitFor(
    t,
    () => find.byType(DatePickerDialog).evaluate().isEmpty,
    'Datumsdialog zu',
  );
}

Future<void> _checkAndSave(WidgetTester t) async {
  await _reveal(t, 'plan_form_check', down: true);
  await tapKey(t, 'plan_form_check');
  final list = find.descendant(
    of: find.byKey(const Key('plan_form')),
    matching: find.byType(Scrollable),
  );
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (!has('plan_form_save') && !has('plan_form_error')) {
    if (DateTime.now().isAfter(end)) fail('keine Einschaetzung nach 40 s');
    if (has('plan_form_care')) break;
    await t.drag(list.first, const Offset(0, -300));
    await pumpFor(t, const Duration(milliseconds: 300));
  }
  if (has('plan_form_error')) {
    final e = find.byKey(const Key('plan_form_error')).first;
    final w = t.widget(e);
    log('M2 form_error widget=${w.runtimeType} ${w is Text ? w.data : ''}');
    // Oeffentlich nur der Name der Meldung, nie ihr Text mit Werten.
    final l = AppLocalizations.of(t.element(find.byType(Scaffold).last));
    final names = {
      l.planFormErrorDistance: 'planFormErrorDistance',
      l.planFormErrorTime: 'planFormErrorTime',
      l.planFormErrorDatePast: 'planFormErrorDatePast',
      l.planFormErrorRunDays: 'planFormErrorRunDays',
      l.planFormErrorMaxSession: 'planFormErrorMaxSession',
      l.planFormErrorWeekly: 'planFormErrorWeekly',
      l.planFormErrorStand: 'planFormErrorStand',
      l.planFormErrorInvalid: 'planFormErrorInvalid',
      l.planFormAssessFailed: 'planFormAssessFailed',
      l.planFormSaveRejected: 'planFormSaveRejected',
      l.planFormSaveFailed: 'planFormSaveFailed',
    };
    logPub(
      'M2 form_error key=${w is Text ? names[w.data] ?? 'unbekannt' : w.runtimeType}',
    );
  }
  expect(has('plan_form_error'), isFalse, reason: 'Formular meldet Fehler');
  await waitFor(t, () => has('plan_form_save'), 'Speichern-Knopf');
  await tapKey(t, 'plan_form_save');
  if (has('plan_form_care')) {
    await tapDialog(t, 'plan_form_care_confirm');
  }
  await waitFor(t, () => has('plan_goal_saved'), 'Meldung Ziel gespeichert');
}

/// Scrollt das lazy Formular, bis [key] im Baum steht.
Future<void> _reveal(WidgetTester t, String key, {bool down = false}) async {
  final list = find.descendant(
    of: find.byKey(const Key('plan_form')),
    matching: find.byType(Scrollable),
  );
  for (var i = 0; i < 12 && !has(key); i++) {
    await t.drag(list.first, Offset(0, (i < 6) == down ? -300 : 300));
    await pumpFor(t, const Duration(milliseconds: 200));
  }
}

/// Taste, die auf Fuehrungs- und Werteseite doppelt vorkommt: die sichtbare tippen.
Future<void> _tapVisible(WidgetTester t, String key) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final all = find.byKey(Key(key));
    for (var i = 0; i < all.evaluate().length; i++) {
      final f = all.at(i);
      if (hittable(t, f)) {
        await t.tap(f);
        await pumpFor(t, const Duration(milliseconds: 300));
        return;
      }
    }
    if (DateTime.now().isAfter(end)) fail('keine sichtbare Taste $key');
    await pumpFor(t, const Duration(milliseconds: 200));
  }
}

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

/// Zurueck erst, wenn der Tipp die Taste trifft (nicht im Seitenuebergang).
Future<void> _back(WidgetTester t) async {
  final f = find.byType(BackButton);
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (f.evaluate().isEmpty || !hittable(t, f.last)) {
    if (DateTime.now().isAfter(end)) fail('Zurueck nicht tippbar');
    await pumpFor(t, const Duration(milliseconds: 100));
  }
  await t.tap(f.last);
  await pumpFor(t, const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M2: Plan, gefuehrte Einheit, Zusammenfassung, Anpassung',
    reportingFailures((t) async {
      final w = buildWorld();
      await startApp(t, w);
      await setupIfShown(t);
      final s = await session(t, w);
      expect(
        await t.runAsync(() => (s as GoalStorage).goals.goal()),
        isNull,
        reason: 'Test erwartet frischen Speicher ohne Ziel',
      );

      // Profil ueber die Oberflaeche.
      await tapKey(t, 'home_overview');
      await tapKey(t, 'home_profile');
      await waitFor(t, () => has('profile_save'), 'Profil');
      await _enter(t, 'profile_max', '190');
      await _enter(t, 'profile_resting', '60');
      await tapKey(t, 'profile_save');
      // Gespeichert ist es, wenn der Speicher den Wert liefert (die Seite meldet
      // nur bei Hinweisen eine Notiz).
      var prof = (await t.runAsync(s.profile.read))!;
      final pend = DateTime.now().add(const Duration(seconds: 20));
      while (prof.maxHeartRateBpm != 190 && DateTime.now().isBefore(pend)) {
        await pumpFor(t, const Duration(milliseconds: 300));
        prof = (await t.runAsync(s.profile.read))!;
      }
      expect(prof.maxHeartRateBpm, 190, reason: 'Profil gespeichert');
      expect(prof.restingHeartRateBpm, 60);
      while (!has('home_plan')) {
        if (find.byType(BackButton).evaluate().isEmpty) break;
        await _back(t);
      }
      await waitFor(t, () => has('home_plan'), 'Heute');

      // Kurz vor Mitternacht erst den Tageswechsel abwarten (hoechstens 5 min): Der Lauftag wird jetzt festgelegt,
      // die Einheit muss beim Start noch auf "heute" liegen.
      while (DateTime.now().hour == 23 && DateTime.now().minute >= 55) {
        await pumpFor(t, const Duration(seconds: 1));
      }
      // Ziel anlegen: heutiger Wochentag ist Lauftag, damit heute eine Einheit liegt.
      final today = DateTime.now().weekday;
      int wd(int add) => ((today - 1 + add) % 7) + 1;
      await tapKey(t, 'home_plan');
      await waitFor(t, () => has('plan_empty'), 'Plan leer');
      await tapKey(t, 'plan_create_goal');
      await waitFor(t, () => has('plan_form'), 'Zielformular');
      await _setDays(t, {today, wd(2), wd(4)});
      await _enter(t, 'plan_form_max_session', '45');
      // Kein Wochenstand und "keine 30 min am Stueck": Geh-Lauf-Plan mit kurzen
      // Abschnitten, damit die Fuehrung den Abschnitt wechselt.
      await _reveal(t, 'plan_form_weekly');
      if (has('plan_form_weekly')) await _enter(t, 'plan_form_weekly', '');
      final l10n = AppLocalizations.of(t.element(find.byType(Scaffold).last));
      final no = find.descendant(
        of: find.byKey(const Key('plan_form_can30')),
        matching: find.text(l10n.planFormNo),
      );
      await tapUntil(
        t,
        no,
        () =>
            t
                .widget<RamuriSegmentedToggle<ContinuousRun30>>(
                  find.byKey(const Key('plan_form_can30')),
                )
                .selected ==
            ContinuousRun30.no,
        'plan_form_can30 Nein',
      );
      await _reveal(t, 'plan_form_date_pick');
      await _pickTargetDate(t);
      await _checkAndSave(t);
      final plans = (s as PlanStorage).plans;
      var history = (await t.runAsync(plans.history))!;
      log('M2 plan_versions=${history.length}');
      expect(history, hasLength(1), reason: 'Plan entsteht');
      await waitFor(t, () => has('plan_goal_card'), 'Zielkarte');
      await tapKey(t, 'home_today');

      // Heute: Einheit starten (gefuehrt).
      final d0 = DateTime.now();
      final near = (await t.runAsync(
        () => plans.unitsBetween(
          DateTime.utc(d0.year, d0.month, d0.day - 1),
          DateTime.utc(d0.year, d0.month, d0.day + 8),
        ),
      ))!;
      // Dauer des ersten Abschnitts der heutigen Einheit: daraus folgt die Frist des Abschnittswechsels.
      var firstSegmentSeconds = 300;
      for (final u in near) {
        if (u.day.year == d0.year &&
            u.day.month == d0.month &&
            u.day.day == d0.day &&
            u.segments.isNotEmpty) {
          firstSegmentSeconds = u.segments.first.durationSeconds;
        }
        log(
          'M2 unit day=${u.day.toIso8601String().substring(0, 10)} kind=${u.kind.name} min=${u.minutes} seg=${u.segments.length}',
        );
      }
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

      // Abschnittswechsel abwarten (Echtzeit, die Einheit beginnt mit Aufwaermen/Lauf-Gehen).
      final first = txt('guided_section');
      final dl = DateTime.now().add(
        Duration(seconds: firstSegmentSeconds + 120),
      );
      while (txt('guided_section') == first) {
        if (DateTime.now().isAfter(dl)) {
          fail('kein Abschnittswechsel in ${firstSegmentSeconds + 120} s');
        }
        expect(
          has('map_consent_dialog'),
          isFalse,
          reason: 'Karten-Frage im Lauf',
        );
        await pumpFor(t, const Duration(seconds: 1));
      }
      log('M2 section_changed');

      // Beenden: kein Karten-Dialog davor oder darueber.
      await _tapVisible(t, 'run_pause');
      await _tapVisible(t, 'run_finish');
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

      // Ziel aendern (vierter Lauftag): neue Fassung mit Erklaerung (WP23).
      ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await pumpFor(t, const Duration(milliseconds: 300));
      final versions = history.length;
      await tapKey(t, 'plan_edit_goal');
      await waitFor(t, () => has('plan_form'), 'Zielformular (Aendern)');
      await _reveal(t, 'plan_form_day_${wd(1)}');
      final was = _daySelected(t, wd(1));
      await tapUntil(
        t,
        find.byKey(Key('plan_form_day_${wd(1)}')),
        () => _daySelected(t, wd(1)) != was,
        'plan_form_day_${wd(1)}',
      );
      await _checkAndSave(t);
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
      await tapKey(t, 'plan_recalculate');
      await waitFor(t, () => has('plan_recalculate_dialog'), 'Rueckfrage');
      await tapDialog(t, 'plan_recalculate_confirm');
      await waitFor(t, () => has('plan_recalculated'), 'neu berechnet');

      await _openPlanMenu(t);
      await waitFor(t, () => has('plan_menu_history'), 'Menue');
      await tapDialog(t, 'plan_menu_history');
      await waitFor(t, () => has('plan_history'), 'Verlauf der Planfassungen');
    }),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
