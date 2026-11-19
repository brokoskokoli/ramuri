// Gemeinsame Hilfen der E2E-Tests mit Ziel und gefuehrter Einheit
// (e2e_m2_flow_test.dart, e2e_treadmill_test.dart): Profil- und Zielformular
// bedienen, sichtbare Taste tippen. Ausgabe nur Schluesselnamen und Zaehler.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'e2e_support.dart';

/// Tipp auf das Eingabefeld, Text setzen, Tastatur schliessen (sie verdeckt
/// sonst Knoepfe darunter).
Future<void> enterField(WidgetTester t, String key, String text) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.enterText(f, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(t, const Duration(milliseconds: 300));
}

bool daySelected(WidgetTester t, int weekday) =>
    t.widget<FilterChip>(find.byKey(Key('plan_form_day_$weekday'))).selected;

/// Wie [daySelected], aber `null`, wenn der Chip nicht im Baum steht (fuer
/// Bedingungen von [tapUntil], die nicht werfen duerfen).
bool? dayState(int weekday) =>
    maybeWidget<FilterChip>(find.byKey(Key('plan_form_day_$weekday')))
        ?.selected;

/// Auswahl des Umschalters "30 min am Stueck" oder `null`, wenn er nicht im
/// Baum steht.
ContinuousRun30? can30State() =>
    maybeWidget<RamuriSegmentedToggle<ContinuousRun30>>(
      find.byKey(const Key('plan_form_can30')),
    )?.selected;

/// Wochentag [add] Tage nach heute (1 = Montag .. 7 = Sonntag).
int weekdayFromToday(int add) => ((DateTime.now().weekday - 1 + add) % 7) + 1;

/// Lauftage genau auf [days] stellen.
Future<void> setRunDays(WidgetTester t, Set<int> days) async {
  for (var d = 1; d <= 7; d++) {
    final want = days.contains(d);
    if (daySelected(t, d) != want) {
      await tapUntil(
        t,
        find.byKey(Key('plan_form_day_$d')),
        () => dayState(d) == want,
        'plan_form_day_$d',
        reveal: () => revealInPlanForm(t, 'plan_form_day_$d'),
      );
    }
  }
}

/// Zieldatum gut vier Monate voraus waehlen.
Future<void> pickTargetDate(WidgetTester t) async {
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

/// Einschaetzen und speichern; meldet einen Formularfehler oeffentlich nur
/// mit dem Namen der Meldung (Praefix [prefix] des Ablaufs), nie mit Werten.
Future<void> checkAndSaveGoal(WidgetTester t, String prefix) async {
  await revealInPlanForm(t, 'plan_form_check', down: true);
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
    log(
      '$prefix form_error widget=${w.runtimeType} ${w is Text ? w.data : ''}',
    );
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
      '$prefix form_error key=${w is Text ? names[w.data] ?? 'unbekannt' : w.runtimeType}',
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
Future<void> revealInPlanForm(
  WidgetTester t,
  String key, {
  bool down = false,
}) async {
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
Future<void> tapVisible(WidgetTester t, String key) async {
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

/// Zurueck erst, wenn der Tipp die Taste trifft (nicht im Seitenuebergang).
Future<void> tapBack(WidgetTester t) async {
  final f = find.byType(BackButton);
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (f.evaluate().isEmpty || !hittable(t, f.last)) {
    if (DateTime.now().isAfter(end)) fail('Zurueck nicht tippbar');
    await pumpFor(t, const Duration(milliseconds: 100));
  }
  await t.tap(f.last);
  await pumpFor(t, const Duration(seconds: 1));
}

/// Profil (Maximal- und Ruhepuls) ueber die Oberflaeche setzen und zurueck
/// nach "Heute"; gespeichert ist es, wenn der Speicher die Werte liefert.
Future<void> enterProfile(WidgetTester t, StorageSession s) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'home_profile');
  await waitFor(t, () => has('profile_save'), 'Profil');
  await enterField(t, 'profile_max', '190');
  await enterField(t, 'profile_resting', '60');
  await tapKey(t, 'profile_save');
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
    await tapBack(t);
  }
  await waitFor(t, () => has('home_plan'), 'Heute');
}

/// Kurz vor Mitternacht den Tageswechsel abwarten (hoechstens 15 min): Der
/// Lauftag wird danach festgelegt, und die gefuehrte Einheit (ca. 6 min, Frist
/// bis 15 min) darf Mitternacht nicht ueberqueren, weil `home_today_done`
/// gegen "heute" prueft.
Future<void> waitPastLateEvening(WidgetTester t) async {
  while (DateTime.now().hour == 23 && DateTime.now().minute >= 45) {
    await pumpFor(t, const Duration(seconds: 1));
  }
}

/// Dauer des ersten Abschnitts der heutigen Einheit in Sekunden (Standard 300,
/// wenn keine Einheit mit Abschnitten heute liegt); Ausgabe nur Zaehler.
Future<int> firstSegmentSecondsToday(
  WidgetTester t,
  PlanRepository plans,
  String prefix,
) async {
  final d0 = DateTime.now();
  final near = (await t.runAsync(
    () => plans.unitsBetween(
      DateTime.utc(d0.year, d0.month, d0.day - 1),
      DateTime.utc(d0.year, d0.month, d0.day + 8),
    ),
  ))!;
  var seconds = 300;
  for (final u in near) {
    if (u.day.year == d0.year &&
        u.day.month == d0.month &&
        u.day.day == d0.day &&
        u.segments.isNotEmpty) {
      seconds = u.segments.first.durationSeconds;
    }
    log(
      '$prefix unit day=${u.day.toIso8601String().substring(0, 10)} kind=${u.kind.name} min=${u.minutes} seg=${u.segments.length}',
    );
  }
  return seconds;
}
