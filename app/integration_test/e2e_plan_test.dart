// E2E: Plan ueber die Oberflaeche anlegen, anpassen und neu berechnen; Warnsignal
// melden, bestaetigen und aufheben (FR-0203). Gepruft wird gegen den
// gespeicherten Zustand (Ziel, Planfassungen, Warnsignal) und sichtbare Keys,
// nicht gegen Bilder. Laeuft in der Sammlung (all_test.dart). Synthetische Daten,
// Ausgabe nur Zaehler.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/system_clock.dart';

import 'support/e2e_support.dart';

/// Tipp auf das Eingabefeld, Text setzen, Tastatur schliessen (sie verdeckt
/// sonst Knoepfe darunter).
Future<void> _enter(WidgetTester t, String key, String text) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.enterText(f, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(t, const Duration(milliseconds: 300));
}

bool _daySelected(WidgetTester t, int weekday) =>
    t.widget<FilterChip>(find.byKey(Key('plan_form_day_$weekday'))).selected;

/// Lauftage genau auf [days] stellen (aus dem Profil koennen welche vorbelegt sein).
Future<void> _setDays(WidgetTester t, Set<int> days) async {
  for (var d = 1; d <= 7; d++) {
    if (_daySelected(t, d) != days.contains(d)) {
      await tapKey(t, 'plan_form_day_$d');
    }
  }
}

/// Datumsdialog: vier Monate weiter, Tag 15, OK.
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

/// Pruefen (Einschaetzung) und speichern; verlangt der Plan den Hinweis zur
/// Vorsicht (Geh-Lauf-Plan), wird er bestaetigt.
Future<void> _checkAndSave(WidgetTester t) async {
  await tapKey(t, 'plan_form_check');
  // Das Formular ist eine lazy ListView: Speichern-Knopf und Fehler stehen erst
  // im Baum, wenn nach unten gescrollt wurde. Bis dahin pruefen und scrollen.
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
  expect(has('plan_form_error'), isFalse, reason: 'Formular meldet Fehler');
  await waitFor(t, () => has('plan_form_save'), 'Speichern-Knopf');
  expect(has('plan_form_assessment'), isTrue);
  await tapKey(t, 'plan_form_save');
  if (has('plan_form_care')) {
    await tapDialog(t, 'plan_form_care_confirm');
  }
  await waitFor(t, () => has('plan_goal_saved'), 'Meldung Ziel gespeichert');
}

Future<void> _openPlan(WidgetTester t) async {
  await tapKey(t, 'home_plan');
  await waitFor(
    t,
    () => has('plan_empty') || has('plan_goal_card'),
    'Plan-Seite',
  );
}

Future<void> _snackGone(WidgetTester t) async {
  ScaffoldMessenger.of(t.element(find.byType(Scaffold).first)).clearSnackBars();
  await pumpFor(t, const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Plan anlegen, anpassen, neu berechnen', (t) async {
    final w = buildWorld();
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    expect(
      await t.runAsync(() => (s as GoalStorage).goals.goal()),
      isNull,
      reason: 'Test erwartet frischen Speicher ohne Ziel',
    );

    await _openPlan(t);
    expect(has('plan_empty'), isTrue);
    await tapKey(t, 'plan_create_goal');
    await waitFor(t, () => has('plan_form'), 'Zielformular');
    await _setDays(t, {2, 4, 6});
    await _enter(t, 'plan_form_max_session', '45');
    // Je nach Stand (eigene Laeufe oder Profil) fehlt das Wochenfeld.
    if (has('plan_form_weekly')) await _enter(t, 'plan_form_weekly', '120');
    await _pickTargetDate(t);
    await _checkAndSave(t);

    var plans = (s as PlanStorage).plans;
    final goal = (await t.runAsync(() => (s as GoalStorage).goals.goal()))!;
    log('PLAN goal_days=${goal.runDays.length}');
    expect(goal.type, GoalType.distance);
    expect(goal.runDays, {2, 4, 6});
    expect(goal.maxSessionSeconds, 45 * 60);
    var history = (await t.runAsync(plans.history))!;
    expect(history, hasLength(1), reason: 'erste Planfassung');
    await waitFor(t, () => has('plan_goal_card'), 'Zielkarte');

    // Anpassen: Montag als vierter Lauftag, das Ziel aendert sich, neue Fassung.
    await _snackGone(t);
    await tapKey(t, 'plan_edit_goal');
    await waitFor(t, () => has('plan_form'), 'Zielformular (Aendern)');
    await tapKey(t, 'plan_form_day_1');
    await _checkAndSave(t);
    final edited = (await t.runAsync(() => (s as GoalStorage).goals.goal()))!;
    expect(edited.runDays, {1, 2, 4, 6});
    history = (await t.runAsync(plans.history))!;
    expect(history, hasLength(2));
    expect(history.last.trigger, PlanTrigger.goalChange);

    // Neu berechnen: erst Abbrechen (nichts aendert sich), dann bestaetigen.
    await _snackGone(t);
    await tapKey(t, 'plan_recalculate');
    await waitFor(t, () => has('plan_recalculate_dialog'), 'Rueckfrage');
    await tapDialog(t, 'plan_recalculate_cancel');
    await waitFor(
      t,
      () => !has('plan_recalculate_dialog'),
      'Rueckfrage geschlossen',
    );
    expect((await t.runAsync(plans.history))!, hasLength(2));
    // Der aktuelle Plan bleibt bei "Neu berechnen" unveraendert (keine neue
    // Fassung, gleiche Einheiten); die Meldung sagt "neu berechnet", nicht Fehler.
    Future<String> fingerprint() async => planUnitsFingerprint(
      await plans.unitsBetween(DateTime.utc(2000), planFarFuture),
    );
    final unitsBefore = (await t.runAsync(fingerprint))!;
    await tapKey(t, 'plan_recalculate');
    await waitFor(t, () => has('plan_recalculate_dialog'), 'Rueckfrage');
    await tapDialog(t, 'plan_recalculate_confirm');
    await waitFor(t, () => has('plan_recalculated'), 'Meldung neu berechnet');
    final l10n = AppLocalizations.of(t.element(find.byType(Scaffold).last));
    expect(
      find.descendant(
        of: find.byKey(const Key('plan_recalculated')),
        matching: find.text(l10n.planRecalculateDone),
      ),
      findsOneWidget,
      reason: 'Meldung "neu berechnet", nicht Fehler',
    );
    expect((await t.runAsync(plans.history))!, hasLength(2));
    expect(await t.runAsync(fingerprint), unitsBefore);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('Warnsignal melden, bestaetigen, aufheben', (t) async {
    final w = buildWorld();
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    final plans = (s as PlanStorage).plans;
    final store = (s as WarningStorage).warning;
    // Ohne Plan aus dem vorigen Test: Ziel direkt anlegen.
    if (await t.runAsync(() => (s as GoalStorage).goals.goal()) == null) {
      final c = PlanController(session: s, clock: const SystemClock());
      final today = calendarDay(const SystemClock().now());
      await t.runAsync(
        () => c.saveGoal(
          TrainingGoal(
            type: GoalType.distance,
            distance: GoalDistance.tenKilometers,
            targetDate: today.add(const Duration(days: 140)),
            runDays: const {2, 4, 6},
            maxSessionSeconds: 7200,
            weeklyCapSeconds: 240 * 60.0,
            createdAt: today,
            hardSessionEnabled: false,
            canRun30: ContinuousRun30.yes,
          ),
        ),
      );
      c.dispose();
    }
    await _openPlan(t);
    await waitFor(t, () => has('plan_goal_card'), 'Plan mit Ziel');
    expect(has('plan_warning_banner'), isFalse);
    expect(await t.runAsync(store.read), isNull);
    final versions = (await t.runAsync(plans.history))!.length;

    // Melden, dann in der Rueckfrage abbrechen: nichts aendert sich.
    await tapKey(t, 'plan_menu');
    await waitFor(t, () => has('plan_menu_report'), 'Menue');
    await tapDialog(t, 'plan_menu_report');
    await waitFor(t, () => has('plan_warning_dialog'), 'Rueckfrage Melden');
    await tapDialog(t, 'plan_warning_cancel');
    await waitFor(t, () => !has('plan_warning_dialog'), 'Rueckfrage zu');
    expect(await t.runAsync(store.read), isNull);
    expect((await t.runAsync(plans.history))!, hasLength(versions));
    expect(has('plan_warning_banner'), isFalse);

    // Melden und bestaetigen: Warnsignal gespeichert, Banner, neue Fassung.
    await tapKey(t, 'plan_menu');
    await waitFor(t, () => has('plan_menu_report'), 'Menue');
    await tapDialog(t, 'plan_menu_report');
    await waitFor(t, () => has('plan_warning_dialog'), 'Rueckfrage Melden');
    await tapDialog(t, 'plan_warning_confirm');
    await waitFor(t, () => has('plan_warning_banner'), 'Banner');
    final reported = await t.runAsync(store.read);
    expect(reported, isNotNull, reason: 'Warnsignal gespeichert');
    expect((await t.runAsync(plans.history))!.length, greaterThan(versions));
    // Im Menue steht "melden" bei aktivem Warnsignal nicht mehr.
    await tapKey(t, 'plan_menu');
    await waitFor(t, () => has('plan_menu_feedback'), 'Menue');
    expect(has('plan_menu_report'), isFalse);
    // Menue per Tipp neben das Menue schliessen.
    await t.tapAt(const Offset(5, 5));
    await waitFor(t, () => !has('plan_menu_feedback'), 'Menue zu');

    // Aufheben: Banner weg, Warnsignal geloescht.
    await tapKey(t, 'plan_warning_lift');
    await waitFor(t, () => !has('plan_warning_banner'), 'Banner weg');
    expect(await t.runAsync(store.read), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
