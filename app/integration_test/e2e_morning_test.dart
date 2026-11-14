// E2E: Morgenmessung (FR-0215/0217, WP33) mit Fake-Kamera (DebugTestPpgCamera,
// Zeitraffer 30) und Test-Sensor mit RR (DebugTestSensor sendRr). Ein Ablauf,
// weil die Schritte aufeinander aufbauen (Entwicklermodus, Messungen des Tages):
// 1 ohne Entwicklermodus kein Einstieg, 2 neun Tipps nein / zehn ja, 3 liegend und
// sitzend zaehlen beide, 4 schlecht -> Noch einmal -> gueltig, 5 ausserhalb des
// Fensters markiert (Fenster ueber den Einstellungsspeicher gesetzt, die Uhr der
// App ist die Systemuhr), 6 Gurt-Paar gespeichert + Zaehler + Teilen-Warnung,
// 8 Entwicklermodus aus -> Einstieg weg. Nur Zaehler und Marken in der Ausgabe.
// Der Host (E2E_SHOTS=1) kann bei "E2E_.. SHOT <name>" ein Bildschirmfoto machen.
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/system_clock.dart';
import 'package:running_app/ui/ui.dart';

import 'support/e2e_support.dart';

/// Systemuhr, deren monotone Zeit der Test vorstellen kann ([jump]): die feste
/// Ruhephase der Morgenmessung (kein Ueberspringen) endet dann gleich. Die
/// Wanduhr (Fenster, Zeitstempel) bleibt echt, die monotone Zeit bleibt monoton
/// und laeuft sonst in Echtzeit (die Kamera-Aufnahme prueft Abstaende damit).
class _FastClock implements Clock {
  final _sw = Stopwatch()..start();
  Duration _bonus = Duration.zero;
  void jump(Duration d) => _bonus += d;
  @override
  DateTime now() => const SystemClock().now();
  @override
  Duration monotonic() => _sw.elapsed + _bonus;
  @override
  Duration utcOffsetAt(DateTime at) => const SystemClock().utcOffsetAt(at);
}

late _FastClock _clk;

/// Dieselbe Verdrahtung wie [buildWorld], nur mit schneller monotoner Uhr.
World buildFastWorld(DebugTestPpgCamera cam) {
  _clk = _FastClock();
  final b = buildWorld(camera: cam);
  final d = b.deps;
  return World(
    AppDependencies(
      storageStart: d.storageStart,
      clock: _clk,
      permissions: d.permissions,
      runPorts: d.runPorts,
      heartRateSensor: d.heartRateSensor,
      ppgCamera: d.ppgCamera,
      sensors: d.sensors,
      offload: d.offload,
      fileHandoff: d.fileHandoff,
      archiveExport: d.archiveExport,
      archiveRestore: d.archiveRestore,
      archiveVerify: d.archiveVerify,
      mapCache: d.mapCache,
      map: d.map,
      reminders: d.reminders,
      reminderDebug: d.reminderDebug,
    ),
    b.sensor,
  );
}

/// Marke fuer das Bildschirmfoto des Hosts; die Seite bleibt kurz stehen.
Future<void> shot(WidgetTester t, String name) async {
  log('SHOT $name');
  await pumpFor(t, const Duration(milliseconds: 2500));
}

Future<List<MorningMeasurement>> stored(
  WidgetTester t,
  StorageSession s,
) async => (await t.runAsync(
  () async => [
    for (final e in await (s as MorningStorage).morning.list()) e.value,
  ],
))!;

/// Wartet (echte Zeit), bis die Zahl der gespeicherten Morgenmessungen [n] ist.
Future<List<MorningMeasurement>> storedCount(
  WidgetTester t,
  StorageSession s,
  int n,
) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  var l = await stored(t, s);
  while (l.length != n && DateTime.now().isBefore(end)) {
    await pumpFor(t, const Duration(milliseconds: 300));
    l = await stored(t, s);
  }
  return l;
}

/// Ergebnis steht fest: bei „Noch einmal“ oder „Erneut speichern“, sonst wenn
/// „Fertig“ bedienbar ist. Waehrend des Speicherns ist „Fertig“ schon da, aber
/// ohne Aktion (onPressed null); die Haltung des Ergebnisses ist dann offen.
bool resultSettled() {
  if (has('morning_again') || has('morning_save_retry')) return true;
  final f = find.byKey(const Key('morning_done'));
  if (f.evaluate().isEmpty) return false;
  final w = f.evaluate().first.widget;
  return w is RamuriPrimaryButton && w.onPressed != null;
}

Future<void> toResult(WidgetTester t) async {
  await tapKey(t, 'morning_start');
  try {
    await waitFor(t, () => has('measure_rest_clock'), 'Ruhephase');
    _clk.jump(const Duration(minutes: 30));
    await waitFor(
      t,
      resultSettled,
      'Ergebnis der Morgenmessung',
      timeout: const Duration(seconds: 60),
    );
  } catch (_) {
    log(
      'FAIL rest=${has('measure_rest_clock')} cancel=${has('measure_cancel')} result_title=${has('morning_result_title')}',
    );
    await shot(t, 'fail_toresult');
    rethrow;
  }
}

/// Ueber Heute -> Uebersicht -> Eintrag Morgenmessung; am Ende liegt das Ergebnis.
Future<void> measureFromTile(WidgetTester t, {bool sitting = false}) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_morning');
  await waitFor(t, () => has('morning_start'), 'Einstieg Morgenmessung');
  if (sitting) {
    await t.tap(find.text('Sitzend'));
    await pumpFor(t, const Duration(milliseconds: 300));
  }
  await toResult(t);
}

Future<void> closeResultToHome(WidgetTester t) async {
  await tapKey(t, 'morning_done');
  await waitFor(t, () => has('overview_about'), 'Uebersicht');
  await back(t);
  await waitFor(t, () => has('home_start_run'), 'Heute');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Morgenmessung: Entwicklermodus, Messungen, Gurt-Paar, Ausschalten', (
    t,
  ) async {
    final cam = DebugTestPpgCamera(speed: 30);
    final w = buildFastWorld(cam);
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    log(
      'S0 Fenster=${(await t.runAsync(() => SettingsMorningWindowStore(s.settings, w.deps.clock).read()))!.format()}',
    );

    // 1) ohne Entwicklermodus: weder Karte noch Eintrag.
    await pumpFor(t, const Duration(seconds: 2));
    expect(has('morning_card'), isFalse, reason: 'S1 keine Karte');
    await shot(t, 's1_heute_ohne');
    await tapKey(t, 'home_overview');
    expect(has('overview_morning'), isFalse, reason: 'S1 kein Eintrag');
    expect(has('overview_morning_values'), isFalse, reason: 'S1 kein Verlauf');
    await shot(t, 's1_uebersicht_ohne');
    log('S1 ok');

    // 2) neun Tipps nicht, zehn ja.
    await tapKey(t, 'overview_about');
    await waitFor(t, () => has('about_version'), 'Ueber');
    for (var i = 0; i < 9; i++) {
      await t.tap(find.byKey(const Key('about_version')));
      await pumpFor(t, const Duration(milliseconds: 120));
    }
    expect(has('about_dev_badge'), isFalse, reason: 'S2 nach 9 Tipps aus');
    expect(has('about_dev_section'), isFalse);
    await shot(t, 's2_ueber_9tipps');
    await back(t);
    await tapKey(t, 'overview_about'); // Zaehlung gilt nur je Seitenbesuch
    await waitFor(t, () => has('about_version'), 'Ueber neu');
    for (var i = 0; i < 9; i++) {
      await t.tap(find.byKey(const Key('about_version')));
      await pumpFor(t, const Duration(milliseconds: 120));
    }
    expect(
      has('about_dev_badge'),
      isFalse,
      reason: 'S2 neuer Besuch zaehlt neu',
    );
    await t.tap(find.byKey(const Key('about_version')));
    await waitFor(t, () => has('about_dev_badge'), 'Entwicklermodus an');
    await pumpFor(t, const Duration(milliseconds: 500));
    expect(has('about_dev_section'), isTrue);
    expect(
      (await t.runAsync(
        () => SettingsDeveloperModeStore(s.settings, w.deps.clock).read(),
      )),
      isTrue,
    );
    await shot(t, 's2_ueber_an_hell');
    log('S2 ok');
    await back(t);
    // Uebersicht: der Eintrag erscheint beim Zurueckkehren, ohne erneutes Oeffnen.
    await waitFor(
      t,
      () => has('overview_morning'),
      'Eintrag in der Uebersicht nach Rueckkehr',
      timeout: const Duration(seconds: 10),
    );
    await back(t);
    await pumpFor(t, const Duration(seconds: 1));
    log('S2 karte_sofort=${has('morning_card')}');
    await waitFor(t, () => has('home_start_run'), 'Heute');
    await shot(t, 's2_heute_an');
    expect(has('morning_card'), isTrue, reason: 'S2 Karte erscheint');

    // Liegt die Systemuhr nicht im Vorgabefenster (4 bis 11 Uhr), wird das Fenster
    // fuer die Faelle 3 bis 6 um die Systemzeit gelegt (Uhr der App = Systemuhr).
    final nowU = w.deps.clock.now();
    final off = w.deps.clock.utcOffsetAt(nowU);
    final hNow = nowU.add(off).hour;
    var inWindow = MorningWindow.standard;
    if (!inWindow.contains(nowU, off)) {
      inWindow = MorningWindow(
        hNow > 0 ? hNow - 1 : 0,
        hNow < 22 ? hNow + 2 : 24,
      );
      await t.runAsync(
        () =>
            SettingsMorningWindowStore(s.settings, w.deps.clock).set(inWindow),
      );
    }
    log(
      'S3 fenster=${inWindow.format()} vorgabe=${inWindow == MorningWindow.standard}',
    );

    // 3) liegend gut, dann sitzend gut am selben Morgen.
    await measureFromTile(t);
    expect(has('morning_again'), isFalse, reason: 'S3 liegend gut');
    log(
      'S3 liegend note_not_counted=${has('morning_note_not_counted')} outside=${has('morning_note_outside')}',
    );
    await shot(t, 's3_ergebnis_liegend');
    var l = await storedCount(t, s, 1);
    expect(l.length, 1, reason: 'S3 eine gespeichert');
    await closeResultToHome(t);
    await measureFromTile(t, sitting: true);
    log(
      'S3 sitzend note_not_counted=${has('morning_note_not_counted')} outside=${has('morning_note_outside')}',
    );
    await shot(t, 's3_ergebnis_sitzend');
    l = await storedCount(t, s, 2);
    expect(l.length, 2, reason: 'S3 zwei gespeichert');
    expect(
      l.map((e) => e.posture).toSet().length,
      2,
      reason: 'beide Haltungen',
    );
    final now = w.deps.clock.now();
    final today = morningCountingToday(
      l,
      nowUtc: now,
      utcOffset: w.deps.clock.utcOffsetAt(now),
    );
    log(
      'S3 zaehlt_heute=${today.length} ausserhalb=${l.where((e) => e.outsideWindow).length}',
    );
    expect(today.length, 2, reason: 'S3 beide zaehlen');
    await closeResultToHome(t);
    await shot(t, 's3_heute_karte');

    // 4) schlechte Qualitaet -> Noch einmal -> gueltig; die schlechte wird nicht gespeichert.
    cam.scenario = DebugPpgScenario.weakSignal;
    await measureFromTile(t);
    log(
      'S4 schlecht done=${has('morning_done')} again=${has('morning_again')} retry=${has('morning_save_retry')} title=${txt('morning_result_title')}',
    );
    expect(
      has('morning_again'),
      isTrue,
      reason: 'S4 schlecht bietet Noch einmal',
    );
    expect(has('morning_done'), isFalse);
    await shot(t, 's4_ergebnis_schlecht');
    expect(
      (await stored(t, s)).length,
      2,
      reason: 'S4 schlechte nicht gespeichert',
    );
    cam.scenario = DebugPpgScenario.goodPulse;
    await tapKey(t, 'morning_again');
    // Noch einmal startet gleich die Messung, ohne neue Ruhephase.
    await pumpFor(t, const Duration(milliseconds: 500));
    log(
      'S4 nach_again rest=${has('measure_rest_clock')} start=${has('morning_start')}',
    );
    await waitFor(t, () => !has('morning_again'), 'Ergebnis 1 verlassen');
    await waitFor(
      t,
      resultSettled,
      'Ergebnis 2',
      timeout: const Duration(seconds: 60),
    );
    expect(has('morning_done'), isTrue, reason: 'S4 gueltig');
    l = await storedCount(t, s, 3);
    expect(l.length, 3, reason: 'S4 gueltige gespeichert');
    await shot(t, 's4_ergebnis_gueltig');
    await closeResultToHome(t);
    log('S4 ok');

    // 5) ausserhalb des Fensters (Fenster ueber den Speicher verlegt, Systemuhr).
    final away = hNow < 12
        ? MorningWindow(hNow + 1, 24)
        : MorningWindow(0, hNow);
    await t.runAsync(
      () => SettingsMorningWindowStore(s.settings, w.deps.clock).set(away),
    );
    await measureFromTile(t);
    expect(
      has('morning_note_outside'),
      isTrue,
      reason: 'S5 Markierung ausserhalb',
    );
    await shot(t, 's5_ergebnis_ausserhalb');
    l = await storedCount(t, s, 4);
    expect(
      l.where((e) => e.outsideWindow).length,
      1,
      reason: 'S5 genau eine ausserhalb',
    );
    await closeResultToHome(t);
    await t.runAsync(
      () => SettingsMorningWindowStore(s.settings, w.deps.clock).set(inWindow),
    );
    log('S5 ok');

    // Morgenwerte (Verlauf) hell/dunkel Sicht.
    await tapKey(t, 'home_overview');
    await tapKey(t, 'overview_morning_values');
    await waitFor(
      t,
      () => has('morning_posture') || has('morning_trend_empty'),
      'Morgenwerte',
    );
    await shot(t, 's3_morgenwerte');
    await tapKey(t, 'measure_back');
    await back(t);

    // 6) Gurt mit RR: Paar gespeichert, Zaehler, Teilen mit Warnung.
    w.sensor.sendRr = true;
    await connect(t, ['fake-gurt-1'], 'fake-gurt-1');
    await tapKey(t, 'home_overview');
    await tapKey(t, 'overview_morning');
    await waitFor(t, () => has('morning_start'), 'Einstieg mit Gurt');
    log('S6 gurt_hinweis=${has('morning_belt_hint')}');
    await shot(t, 's6_einstieg_gurt');
    await toResult(t);
    await shot(t, 's6_ergebnis_gurt');
    l = await storedCount(t, s, 5);
    expect(l.length, 5, reason: 'S6 gespeichert');
    final pairs = await t.runAsync(
      () => countMorningPairs((s as MorningStorage).morning),
    );
    log('S6 paare mit=${pairs!.withBelt} ohne=${pairs.without}');
    expect(pairs.withBelt, 1, reason: 'S6 ein Gurt-Paar');
    expect(pairs.without, 4);
    await closeResultToHome(t);
    await tapKey(t, 'home_overview');
    await tapKey(t, 'overview_about');
    await waitFor(t, () => has('about_pairs_count'), 'Zaehler');
    await pumpFor(t, const Duration(milliseconds: 600));
    log('S6 zaehler_text_laenge=${txt('about_pairs_count').length}');
    await shot(t, 's6_ueber_paare');
    await tapKey(t, 'about_pairs_share');
    await waitFor(t, () => has('about_pairs_dialog'), 'Warnung');
    await shot(t, 's6_warnung');
    await tapDialog(t, 'about_pairs_confirm');
    log('S6 SHARE_TAPPED');
    // Die Datei liegt im Exportordner, sobald das Teilen angestossen ist.
    final dir = await t.runAsync(() => w.deps.fileHandoff.exportDirectory());
    log('S6 exportDir=${dir != null}');
    expect(dir, isNotNull, reason: 'S6 Exportordner');
    await waitFor(
      t,
      () =>
          Directory(dir!).existsSync() &&
          Directory(dir)
              .listSync()
              .any((e) => e.path.contains('running-morgenpaare')),
      'Messpaare-Datei im Exportordner',
      timeout: const Duration(seconds: 20),
    );
    await shot(t, 's6_nach_teilen');

    // 8) Entwicklermodus aus: Einstieg weg.
    await tapKey(t, 'about_dev_switch');
    await waitFor(
      t,
      () => !has('about_dev_section'),
      'Entwicklerabschnitt weg',
    );
    await shot(t, 's8_ueber_aus');
    expect(
      (await t.runAsync(
        () => SettingsDeveloperModeStore(s.settings, w.deps.clock).read(),
      )),
      isFalse,
    );
    await back(t);
    await back(t);
    await pumpFor(t, const Duration(seconds: 1));
    await tapKey(t, 'home_overview');
    await pumpFor(t, const Duration(seconds: 1));
    log('S8 eintrag=${has('overview_morning')}');
    await back(t);
    await pumpFor(t, const Duration(seconds: 1));
    log('S8 karte=${has('morning_card')}');
    await shot(t, 's8_heute_aus');
    expect(has('morning_card'), isFalse, reason: 'S8 Karte weg');
    await tapKey(t, 'home_overview');
    await pumpFor(t, const Duration(milliseconds: 800));
    expect(has('overview_morning'), isFalse, reason: 'S8 Eintrag weg');
    log('S8 ok');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
