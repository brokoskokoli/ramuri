// E2E: Health-Connect-Import (WP32) mit der Debug-Quelle (DebugTestHealthConnect, synthetische Daten) in der
// echten App mit echtem Speicher. Szenarien in Reihenfolge, jedes baut auf dem Stand des vorigen auf:
//  1 Einwilligung fuer zwei Arten (Training, VO2max), Rechte, "Jetzt abrufen": nur diese Arten gespeichert
//  2 Quelle sichtbar im Verlauf (importierte Einheit) und auf Fortschritt (VO2max-Vergleichskarte)
//  3 Training uebernehmen: Belastung vorher unveraendert, danach einmal gezaehlt, zweites Uebernehmen nicht moeglich
//  4 Datenart widerrufen -> Loeschfrage -> Loeschen leert nur diese Art (Abbrechen schaltet wieder ein)
//  6 "Health Connect installieren": Zustand updateRequired mit Knopf, Rest der App normal
// Mit --dart-define=HC_REAL=true statt dessen Szenario 5: echter Adapter, echter Berechtigungsdialog des Systems
// ohne Daten (der Host drueckt Zurueck, siehe Marker E2E_..._SHOT_real_dialog).
// Ausgabe nur Zaehler und Schluessel, keine Werte. Bildschirmfotos: Marker "SHOT <name>" (der Host fotografiert).
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_health_connect.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/features/health/health_connect_screen.dart'
    show HealthKindTexts;
import 'package:running_app/features/storage/storage_start.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/system_clock.dart';

import 'support/e2e_support.dart';

const _real = bool.fromEnvironment('HC_REAL');

/// Marker fuer das Bildschirmfoto des Hosts; die Seite bleibt kurz stehen.
AppDependencies _deps(HealthConnectPort? hc) => AppDependencies.create(
  heartRateSensor: DebugTestSensor(const SystemClock()),
  healthConnect: hc,
);

Future<HealthImportStore> _store(WidgetTester t, AppDependencies d) async {
  await waitFor(
    t,
    () => d.storageStart.state is StorageReady,
    'Speicher bereit',
  );
  final s = (d.storageStart.state as StorageReady).session;
  return (s as HealthStorage).health;
}

Future<StorageSession> _session(WidgetTester t, AppDependencies d) async {
  await waitFor(
    t,
    () => d.storageStart.state is StorageReady,
    'Speicher bereit',
  );
  return (d.storageStart.state as StorageReady).session;
}

Future<Map<HealthDataKind, int>> _counts(
  WidgetTester t,
  HealthImportStore s,
) async => (await t.runAsync(() async {
  return {for (final k in HealthDataKind.values) k: await s.count(k)};
}))!;

String _fmt(Map<HealthDataKind, int> c) =>
    c.entries.map((e) => '${e.key.key}=${e.value}').join(' ');

Future<void> _start(WidgetTester t, AppDependencies d) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(RunningApp(dependencies: d));
  await pumpFor(t, const Duration(seconds: 3));
  await setupIfShown(t);
}

Future<void> _openHealth(WidgetTester t) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'home_settings');
  await waitFor(
    t,
    () => !has('home_settings'),
    'Einstellungen offen (home_settings verdeckt)',
  );
  // Die Karte liegt weit unten in der Liste (wird erst beim Scrollen gebaut).
  await t.scrollUntilVisible(
    find.byKey(const Key('settings_health')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await pumpFor(t, const Duration(milliseconds: 300));
  await tapKey(t, 'settings_health');
  await waitFor(
    t,
    () =>
        has('health_main') ||
        has('health_unavailable_install') ||
        has('health_unavailable_unsupported'),
    'Health-Connect-Seite',
  );
}

bool _on(String kind) {
  final f = find.byKey(Key('health_switch_$kind'));
  return (f.evaluate().first.widget as SwitchListTile).value;
}

/// Wie [_on], wirft aber nicht, solange der Schalter fehlt (Bedingung fuer
/// [waitFor]): fehlt er, gilt [value] als nicht erreicht.
bool _switchIs(String kind, bool value) =>
    maybeWidget<SwitchListTile>(find.byKey(Key('health_switch_$kind')))
        ?.value ==
    value;

/// Texte der Seite Health Connect (fuer Hinweise und Rueckmeldungen).
AppLocalizations _l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byKey(const Key('health_main'))));

/// Ob gerade eine Rueckmeldung (SnackBar) mit genau [text] steht.
bool _snack(String text) => find
    .descendant(of: find.byType(SnackBar), matching: find.text(text))
    .evaluate()
    .isNotEmpty;

/// Anzahl Belastungseinheiten (Laeufe und Nachtraege) laut Belastungsdienst.
Future<int> _loadUnits(WidgetTester t, AppDependencies d) async {
  final session = await _session(t, d);
  const clock = SystemClock();
  final calc = ValueCalculationService(session: session, clock: clock);
  final service = TrainingLoadService(
    session: session,
    clock: clock,
    calculation: calc,
    recalculation: RecalculationService(
      session: session,
      clock: clock,
      calculation: calc,
    ),
  );
  final r = (await t.runAsync(service.load))!;
  return r.series.days.fold<int>(0, (a, day) => a + day.unitCount);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (_real) {
    _realScenario();
    return;
  }

  final hc = DebugTestHealthConnect(now: () => const SystemClock().now());
  final d = _deps(hc);

  test(
    '0 Debug-Quelle: jeder Einzelwert hat eine Einheit (Speicher verlangt sie)',
    () async {
      step('HC0 einheiten');
      final raw = DebugTestHealthConnect(now: () => const SystemClock().now());
      for (final k in [
        HealthDataKind.hrvRmssd,
        HealthDataKind.restingHeartRate,
        HealthDataKind.vo2Max,
      ]) {
        await raw.requestPermissions({k});
        final from = DateTime.now().subtract(const Duration(days: 30));
        final page = await raw.readPage(
          kind: k,
          from: from,
          to: DateTime.now().add(const Duration(days: 1)),
        );
        final noUnit = page.records.where((r) => r.unit == null).length;
        log('HC0 ${k.key} Saetze=${page.records.length} ohne Einheit=$noUnit');
        expect(
          noUnit,
          0,
          reason: '${k.key}: Einheit fehlt, upsertValues wirft',
        );
      }
    },
  );

  testWidgets('1 Einwilligung fuer zwei Arten und Jetzt abrufen', (t) async {
    step('HC1 start');
    log('HC1 Ausgangszustand: frische Installation, Einrichtung uebersprungen');
    await _start(t, d);
    final store = await _store(t, d);
    final before = await _counts(t, store);
    log('HC1 vorher ${_fmt(before)}');
    expect(before.values.every((v) => v == 0), isTrue);
    await _openHealth(t);
    expect(has('health_main'), isTrue);
    step('HC1 schalter');
    // Ausgangslage: nichts eingeschaltet, Weiter-Knopf gesperrt.
    for (final k in HealthDataKind.values) {
      expect(_on(k.key), isFalse, reason: 'Schalter ${k.key} anfangs aus');
    }
    await shot(t, 'health_page_initial', pause: true);
    await tapKey(t, 'health_switch_exercise');
    await tapKey(t, 'health_switch_vo2_max');
    await waitFor(
      t,
      () => _on('exercise') && _on('vo2_max'),
      'Schalter health_switch_exercise und health_switch_vo2_max an',
    );
    expect(await hc.grantedKinds(), isEmpty);
    step('HC1 einwilligen');
    // Vor dem Tipp fehlen die Rechte (Hinweis unter health_continue), danach
    // verschwindet der Hinweis: Wirkung des Tipps.
    final rightsMissing = find.textContaining(_l10n(t).healthRightsMissing);
    expect(
      rightsMissing,
      findsOneWidget,
      reason: 'Hinweis fehlende Rechte vor health_continue',
    );
    await tapKey(t, 'health_continue');
    await waitFor(
      t,
      () => has('health_main') && rightsMissing.evaluate().isEmpty,
      'Rechte erteilt nach health_continue (Hinweis weg, health_main)',
    );
    final granted = await t.runAsync(hc.grantedKinds);
    log('HC1 Rechte ${granted!.map((k) => k.key).toList()..sort()}');
    expect(granted, {HealthDataKind.exercise, HealthDataKind.vo2Max});
    step('HC1 abrufen');
    await tapKey(t, 'health_fetch');
    await waitFor(
      t,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      'Rueckmeldung nach Abruf',
    );
    await shot(t, 'health_page_after_fetch', pause: true);
    final after = await _counts(t, store);
    log('HC1 nachher ${_fmt(after)}');
    expect(after[HealthDataKind.exercise], 1);
    expect(after[HealthDataKind.vo2Max], 1);
    for (final k in HealthDataKind.values) {
      if (k == HealthDataKind.exercise || k == HealthDataKind.vo2Max) continue;
      expect(
        after[k],
        0,
        reason: '${k.key} nicht eingewilligt, nichts gespeichert',
      );
    }
    final never = AppLocalizations.of(
      t.element(find.byKey(const Key('health_last'))),
    ).healthLastNever;
    expect(txt('health_last'), isNot(never), reason: 'letzter Abruf gesetzt');
    log('HC1 letzter Abruf gesetzt');
  });

  testWidgets('2 Quelle sichtbar im Verlauf und auf Fortschritt', (t) async {
    step('HC2 verlauf');
    await _start(t, d);
    await tapKey(t, 'home_history');
    await waitFor(t, () => has('history_title'), 'Verlauf (history_title)');
    // Läufe früherer Gruppen der Sammlung stehen davor: erst zur Einheit scrollen (Liste baut lazy).
    await t.scrollUntilVisible(
      find.byKey(const Key('health_exercise_debug-exercise-0')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await waitFor(
      t,
      () => has('health_exercise_debug-exercise-0'),
      'importierte Einheit im Verlauf',
    );
    expect(
      txt('health_exercise_source_debug-exercise-0'),
      contains('debug.app.a'),
    );
    expect(has('health_exercise_taken_debug-exercise-0'), isFalse);
    await shot(t, 'history_imported', pause: true);
    step('HC2 fortschritt');
    await tapKey(t, 'home_statistics');
    await waitFor(t, () => has('health_vo2_card'), 'VO2max-Vergleichskarte');
    expect(has('health_vo2_row_debug.app.a'), isTrue);
    expect(txt('health_vo2_source_debug.app.a'), contains('debug.app.a'));
    // Nicht eingewilligte Quelle b liefert keinen VO2max-Wert (nur a im Fake), keine zweite Zeile.
    expect(has('health_vo2_row_debug.app.b'), isFalse);
    await t.ensureVisible(find.byKey(const Key('health_vo2_card')));
    await pumpFor(t, const Duration(milliseconds: 300));
    await shot(t, 'progress_vo2_comparison', pause: true);
    log('HC2 Quelle im Verlauf und Vergleichskarte sichtbar');
  });

  testWidgets('3 Training uebernehmen zaehlt einmal', (t) async {
    step('HC3 start');
    await _start(t, d);
    final session = await _session(t, d);
    final units0 = await _loadUnits(t, d);
    final manual0 = (await t.runAsync(() => session.manualTrainings.list()))!
        .length;
    log('HC3 vorher Einheiten=$units0 Nachtraege=$manual0');
    await tapKey(t, 'home_history');
    await waitFor(
      t,
      () => has('health_exercise_debug-exercise-0'),
      'importierte Einheit',
    );
    step('HC3 detail');
    await tapKey(t, 'health_exercise_debug-exercise-0');
    await waitFor(t, () => has('health_take'), 'Detail mit Uebernehmen');
    expect(has('health_detail_origin'), isTrue);
    expect(
      has('health_detail_pulse_none'),
      isTrue,
      reason: 'Puls nicht eingewilligt',
    );
    await shot(t, 'exercise_detail', pause: true);
    expect(
      await _loadUnits(t, d),
      units0,
      reason: 'Belastung vor Uebernahme unveraendert',
    );
    step('HC3 uebernehmen');
    await tapKey(t, 'health_take');
    await waitFor(t, () => has('manual_save'), 'Nachtrag-Formular');
    // Dauer ist vorausgefuellt (40 min), RPE fragt die App.
    final minutes =
        (find.byKey(const Key('manual_minutes')).evaluate().first.widget
                as TextField)
            .controller!
            .text;
    log('HC3 vorausgefuellte Dauer=$minutes');
    expect(minutes, '40');
    expect(has('manual_rpe_error'), isFalse, reason: 'vor manual_save');
    await waitFor(
      t,
      () => has('manual_rpe_error'),
      'ohne RPE kein Speichern (manual_rpe_error)',
    );
    expect(
      (await t.runAsync(() => session.manualTrainings.list()))!.length,
      manual0,
    );
    await tapKey(t, 'manual_rpe_5');
    await tapKey(t, 'manual_save');
    await waitFor(
      t,
      () => has('health_taken') && !has('manual_save'),
      'uebernommen angezeigt',
    );
    expect(
      has('health_take'),
      isFalse,
      reason: 'zweites Uebernehmen nicht moeglich',
    );
    await shot(t, 'exercise_detail_taken', pause: true);
    final manual1 = (await t.runAsync(() => session.manualTrainings.list()))!
        .length;
    final units1 = await _loadUnits(t, d);
    log('HC3 nachher Einheiten=$units1 Nachtraege=$manual1');
    expect(manual1, manual0 + 1);
    expect(units1, units0 + 1, reason: 'genau einmal gezaehlt');
    step('HC3 verlauf');
    // Zurueck: Verlauf zeigt "uebernommen" an der Einheit, genau ein Nachtrag mit dieser Quelle.
    await back(t);
    await waitFor(
      t,
      () => has('health_exercise_taken_debug-exercise-0'),
      'uebernommen im Verlauf (health_exercise_taken_debug-exercise-0)',
    );
    // Wiederholter Import aendert nichts an der Zaehlung (gleiche ID wird ueberschrieben).
    await tapKey(t, 'home_today');
    await waitFor(t, () => has('home_start_run'), 'Heute (home_start_run)');
    expect(await _loadUnits(t, d), units1);
  });

  testWidgets('4 Widerruf mit Loeschfrage leert nur diese Art', (t) async {
    step('HC4 start');
    await _start(t, d);
    final store = await _store(t, d);
    final before = await _counts(t, store);
    log('HC4 vorher ${_fmt(before)}');
    await _openHealth(t);
    expect(
      _on('exercise') && _on('vo2_max'),
      isTrue,
      reason: 'Einwilligung blieb ueber den Neustart',
    );
    step('HC4 abbrechen');
    // Abbrechen: schaltet wieder ein, nichts geloescht.
    await tapKey(t, 'health_switch_vo2_max');
    await waitFor(t, () => has('health_delete_dialog'), 'Loeschfrage');
    await shot(t, 'delete_dialog', pause: true);
    await tapDialog(t, 'health_delete_cancel');
    await waitFor(
      t,
      () => _switchIs('vo2_max', true),
      'Abbrechen schaltet wieder ein (health_switch_vo2_max an)',
    );
    expect(await _counts(t, store), before);
    step('HC4 loeschen');
    // Widerruf und Loeschen.
    await tapKey(t, 'health_switch_vo2_max');
    await waitFor(t, () => has('health_delete_dialog'), 'Loeschfrage 2');
    expect(_on('vo2_max'), isFalse);
    // Die Rueckmeldung erscheint erst, wenn das Loeschen gespeichert ist.
    final l10n = _l10n(t);
    final deleted = l10n.healthDeletedSnack(
      HealthKindTexts.of(l10n, HealthDataKind.vo2Max).plural,
    );
    await tapDialog(t, 'health_delete_confirm');
    await waitFor(
      t,
      () => _snack(deleted),
      'Rueckmeldung geloescht nach health_delete_confirm',
    );
    final after = await _counts(t, store);
    log('HC4 nachher ${_fmt(after)}');
    expect(after[HealthDataKind.vo2Max], 0);
    expect(after[HealthDataKind.exercise], before[HealthDataKind.exercise]);
    expect(_on('exercise'), isTrue);
    expect(_on('vo2_max'), isFalse);
    await shot(t, 'health_page_after_delete', pause: true);
    step('HC4 fortschritt');
    // Die Uebernahme als Training bleibt (eigene Daten), Vergleichskarte weg.
    await back(t);
    await back(t);
    await back(t);
    await waitFor(
      t,
      () => has('progress_week_title'),
      'Fortschritt (progress_week_title)',
    );
    // Die Vergleichskarte laedt ihre Daten nach dem Aufbau der Seite (eigener
    // FutureBuilder ohne Marke fuer das Ladeende): feste Pause bleibt, damit
    // eine zu Unrecht gezeigte Karte Zeit zum Erscheinen hat.
    await pumpFor(t, const Duration(seconds: 2));
    expect(
      has('health_vo2_card'),
      isFalse,
      reason: 'Karte ohne Daten unsichtbar',
    );
    step('HC4 behalten');
    // Behalten-Pfad: Widerruf der Einheiten mit "Behalten" loescht nichts.
    await tapKey(t, 'home_today');
    await _openHealth(t);
    await tapKey(t, 'health_switch_exercise');
    await waitFor(t, () => has('health_delete_dialog'), 'Loeschfrage 3');
    final l10nKeep = _l10n(t);
    final keptText = l10nKeep.healthKeptSnack(
      HealthKindTexts.of(l10nKeep, HealthDataKind.exercise).plural,
    );
    await tapDialog(t, 'health_delete_keep');
    await waitFor(
      t,
      () => _snack(keptText),
      'Rueckmeldung behalten nach health_delete_keep',
    );
    final kept = await _counts(t, store);
    log('HC4 behalten ${_fmt(kept)}');
    expect(kept[HealthDataKind.exercise], before[HealthDataKind.exercise]);
    expect(_on('exercise'), isFalse);
  });

  testWidgets('6 Health Connect installieren: updateRequired', (t) async {
    step('HC6 start');
    final fake = DebugTestHealthConnect(
      now: () => const SystemClock().now(),
      status: HealthSdkStatus.updateRequired,
    );
    await _start(t, _deps(fake));
    await _openHealth(t);
    expect(has('health_unavailable_install'), isTrue);
    expect(has('health_install'), isTrue);
    await shot(t, 'unavailable_install', pause: true);
    step('HC6 installieren');
    expect(fake.installOpened, 0);
    await tapKey(t, 'health_install');
    await waitFor(
      t,
      () => fake.installOpened > 0,
      'Installieren geoeffnet nach health_install',
    );
    expect(fake.installOpened, 1);
    await tapKey(t, 'health_without');
    // Ohne Health Connect zurueck auf die Einstellungen (dort war
    // settings_health verdeckt).
    await waitFor(
      t,
      () => has('settings_health') && !has('health_without'),
      'Einstellungen nach health_without (settings_health)',
    );
    step('HC6 rest_der_app');
    // Rest der App normal.
    await back(t);
    await back(t);
    await tapKey(t, 'home_today');
    await waitFor(t, () => has('home_start_run'), 'Heute (home_start_run)');
    await tapKey(t, 'home_history');
    await waitFor(t, () => has('history_title'), 'Verlauf (history_title)');
    expect(find.byType(ErrorWidget), findsNothing);
    log('HC6 installieren-Variante ohne Absturz, Heute und Verlauf offen');
  });
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this.seen);
  final List<AppLifecycleState> seen;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => seen.add(state);
}

void _realScenario() {
  testWidgets('5 echter Berechtigungsdialog ohne Daten', (t) async {
    step('HC5 start');
    final d = _deps(null);
    log('HC5 echter Adapter (Plattformkanal), keine Debug-Quelle');
    await _start(t, d);
    final store = await _store(t, d);
    await _openHealth(t);
    final available = has('health_main');
    log('HC5 Seite=${available ? 'main' : 'unavailable'}');
    if (!available) {
      step('HC6 echter_adapter_ohne_hc');
      // Echter Adapter ohne Health Connect (API 31: Paket fehlt): Installieren-Seite, Knopf ohne Absturz.
      log(
        'HC6 echter Adapter: install=${has('health_unavailable_install')} unsupported=${has('health_unavailable_unsupported')}',
      );
      await shot(t, 'real_unavailable', pause: true);
      if (has('health_install')) {
        await tapKey(t, 'health_install');
        await pumpFor(t, const Duration(seconds: 3));
        log(
          'HC6 Installieren getippt, App noch da: ${has('health_without') || has('health_install')}',
        );
        await shot(t, 'real_unavailable_after_install', pause: true);
      }
      if (has('health_without')) await tapKey(t, 'health_without');
      for (var i = 0; i < 4 && !has('home_today'); i++) {
        await back(t);
      }
      await tapKey(t, 'home_today');
      await waitFor(t, () => has('home_start_run'), 'Heute (home_start_run)');
      await tapKey(t, 'home_history');
      await waitFor(t, () => has('history_title'), 'Verlauf (history_title)');
      expect(find.byType(ErrorWidget), findsNothing);
      log('HC6 Rest der App normal (Heute, Verlauf)');
      return;
    }
    step('HC5 dialog');
    await tapKey(t, 'health_switch_sleep');
    await shot(t, 'real_before_dialog', pause: true);
    final seen = <AppLifecycleState>[];
    final observer = _Lifecycle(seen);
    WidgetsBinding.instance.addObserver(observer);
    await tapKey(t, 'health_continue');
    // Der Host sieht den Marker, fotografiert den Systemdialog und drueckt Zurueck.
    log('SHOT real_dialog');
    await pumpFor(t, const Duration(seconds: 20));
    WidgetsBinding.instance.removeObserver(observer);
    log('HC5 Lebenszyklus ${seen.map((e) => e.name).toList()}');
    // Ein Systemdialog (eigene Activity) schickt die App in inactive/paused.
    // (kurzes inactive allein zaehlt nicht: so sieht auch ein gescheiterter Start aus.)
    final dialogShown = seen.any(
      (e) => e == AppLifecycleState.paused || e == AppLifecycleState.hidden,
    );
    expect(has('health_main'), isTrue, reason: 'App nach Abbruch des Dialogs');
    expect(
      dialogShown,
      isTrue,
      reason: 'Berechtigungsdialog von Health Connect erschien nicht',
    );
    expect(find.byType(ErrorWidget), findsNothing);
    step('HC5 nach_abbruch');
    final c = await _counts(t, store);
    log('HC5 nach Abbruch ${_fmt(c)}');
    expect(
      c.values.every((v) => v == 0),
      isTrue,
      reason: 'ohne Daten nichts gespeichert',
    );
    await shot(t, 'real_after_dialog', pause: true);
    expect(find.byType(SnackBar), findsNothing, reason: 'vor health_fetch');
    await tapKey(t, 'health_fetch');
    // Wirkung: Rueckmeldung zum Abruf; die Seite bleibt bedienbar.
    await waitFor(
      t,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      'Rueckmeldung nach health_fetch',
    );
    expect(has('health_main'), isTrue);
    expect(find.byType(ErrorWidget), findsNothing);
    await shot(t, 'real_after_fetch', pause: true);
    log('HC5 Abruf ohne Recht ohne Absturz');
  });
}
