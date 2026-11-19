// E2E: Morgenmessung (FR-0215/0217, WP33) mit Fake-Kamera (DebugTestPpgCamera,
// Zeitraffer 30) und Test-Sensor mit RR (DebugTestSensor sendRr). Ein Ablauf,
// weil die Schritte aufeinander aufbauen (Entwicklermodus, Messungen des Tages):
// 1 ohne Entwicklermodus kein Einstieg, 2 neun Tipps nein / zehn ja, 3 liegend und
// sitzend: beide gespeichert, aber nur die erste gueltige des Morgens zaehlt
// (eine Reihe je Geraet, K67), 4 schlecht -> im Entwicklermodus trotzdem
// gespeichert (K68, unbrauchbar, zaehlt nirgends) -> Noch einmal -> gueltig (zaehlt
// nicht, die Reihe hat heute schon eine), 5 ausserhalb des Fensters markiert
// (Fenster ueber den Einstellungsspeicher gesetzt, die Uhr der App ist die
// Systemuhr), Morgenwerte: Haltungsmarke gefuellt/hohl und Bildschirmfotos
// hell/dunkel, 5b Gurtzeile ohne bekannten Gurt (Test-Speicher ohne Geraete),
// 6 Gurt bekannt, aber getrennt: Autoverbinden beim Oeffnen („verbunden“, auch
// nach erneutem Oeffnen), Gurt-Paar gespeichert + Zaehler + Teilen-Warnung,
// 7 Ruhephase ueberspringen (Fortschritt, vermerkt), 8 Entwicklermodus aus ->
// Einstieg weg (mit S1 die Pruefung K62 F1). Nur Zaehler und Marken in der
// Ausgabe.
// Der Host (--dart-define=E2E_SHOTS=true) kann bei "E2E_.. SHOT <name>" ein Bildschirmfoto machen.
import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/features/measure/morning_entry.dart';
import 'package:running_app/l10n/app_localizations.dart';
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
  return buildWorld(camera: cam, clock: _clk);
}

/// Bildschirmfotos nur, wenn der Host sie mit --dart-define=E2E_SHOTS=true
/// verlangt; sonst keine Pause.
const _shots = bool.fromEnvironment('E2E_SHOTS');

/// Marke fuer das Bildschirmfoto des Hosts; die Seite bleibt kurz stehen.
Future<void> shot(WidgetTester t, String name) async {
  log('SHOT $name');
  if (_shots) await pumpFor(t, const Duration(milliseconds: 2500));
}

/// Wartet, bis der Morgen-Einstieg unter [owner] ([MorningCard] auf Heute,
/// [MorningTile] in der Uebersicht) seinen Zustand fertig geladen hat: die
/// Zukunft seines FutureBuilder ist erfuellt und das Bild danach gebaut. Erst
/// dann belegt das Fehlen von Karte oder Eintrag etwas (statt fester Pause).
Future<void> entryLoaded(WidgetTester t, Type owner, String what) async {
  final fb = find.descendant(
    of: find.byType(owner),
    matching: find.byWidgetPredicate(
      (w) => w is FutureBuilder<MorningEntryState?>,
    ),
  );
  await waitFor(t, () => fb.evaluate().isNotEmpty, '$what: Einstieg gebaut');
  final future = (fb.evaluate().first.widget as FutureBuilder).future;
  var done = future == null;
  if (future != null) {
    unawaited(
      future.then<void>((_) => done = true, onError: (Object _) => done = true),
    );
  }
  await waitFor(t, () => done, '$what: Einstieg geladen');
  await t.pump();
}

/// Helligkeit des Themas, das auf der Seite mit [key] gilt.
Brightness themeAt(WidgetTester t, String key) =>
    Theme.of(t.element(find.byKey(Key(key)))).brightness;

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
    await tapKey(t, 'morning_posture_sitting');
    final sittingNote = AppLocalizations.of(
      t.element(find.byKey(const Key('morning_pose_note'))),
    ).morningPoseNoteSitting;
    await waitFor(
      t,
      () => txt('morning_pose_note') == sittingNote,
      'Haltung sitzend gewaehlt (morning_pose_note)',
    );
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
    step('MORNING S0 start');
    final w = buildFastWorld(cam);
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    log(
      'S0 Fenster=${(await t.runAsync(() => SettingsMorningWindowStore(s.settings, w.deps.clock).read()))!.format()}',
    );

    step('MORNING S1 ohne_entwicklermodus');
    // 1) ohne Entwicklermodus: weder Karte noch Eintrag. Das Fehlen gilt erst,
    // wenn Heute steht und der Einstieg seinen Zustand geladen hat.
    await waitFor(t, () => has('home_start_run'), 'S1 Heute (home_start_run)');
    await entryLoaded(t, MorningCard, 'S1 Heute');
    expect(has('morning_card'), isFalse, reason: 'S1 keine Karte');
    await shot(t, 's1_heute_ohne');
    await tapKey(t, 'home_overview');
    await waitFor(t, () => has('overview_about'), 'S1 Uebersicht');
    await entryLoaded(t, MorningTile, 'S1 Uebersicht');
    expect(has('overview_morning'), isFalse, reason: 'S1 kein Eintrag');
    expect(has('overview_morning_values'), isFalse, reason: 'S1 kein Verlauf');
    expect(has('overview_developer'), isFalse, reason: 'S1 keine Entw.-Seite');
    await shot(t, 's1_uebersicht_ohne');
    log('S1 ok');

    step('MORNING S2 entwicklermodus_an');
    // 2) neun Tipps nicht, zehn ja.
    await tapKey(t, 'overview_about');
    await waitFor(t, () => has('about_version'), 'Ueber');
    for (var i = 0; i < 9; i++) {
      await t.tap(find.byKey(const Key('about_version')));
      await pumpFor(t, const Duration(milliseconds: 120));
    }
    // Neun Tipps sind gezaehlt, wenn der Hinweis „noch 1 Tipp“ steht.
    final oneLeft = AppLocalizations.of(
      t.element(find.byKey(const Key('about_version'))),
    ).devTapsLeft(1);
    bool toastOneLeft() => find
        .descendant(
          of: find.byKey(const Key('about_toast')),
          matching: find.text(oneLeft),
        )
        .evaluate()
        .isNotEmpty;
    await waitFor(t, toastOneLeft, 'S2 neun Tipps gezaehlt (about_toast)');
    expect(has('about_dev_badge'), isFalse, reason: 'S2 nach 9 Tipps aus');
    expect(has('about_dev_link'), isFalse);
    await shot(t, 's2_ueber_9tipps');
    await back(t);
    await tapKey(t, 'overview_about'); // Zaehlung gilt nur je Seitenbesuch
    await waitFor(t, () => has('about_version'), 'Ueber neu');
    for (var i = 0; i < 9; i++) {
      await t.tap(find.byKey(const Key('about_version')));
      await pumpFor(t, const Duration(milliseconds: 120));
    }
    await waitFor(t, toastOneLeft, 'S2 neuer Besuch neun Tipps (about_toast)');
    expect(
      has('about_dev_badge'),
      isFalse,
      reason: 'S2 neuer Besuch zaehlt neu',
    );
    await t.tap(find.byKey(const Key('about_version')));
    await waitFor(t, () => has('about_dev_badge'), 'Entwicklermodus an');
    await waitFor(
      t,
      () => has('about_dev_link'),
      'S2 Verweis Entwicklereinstellungen (about_dev_link)',
    );
    // Auf „Über“ selbst gibt es keinen Entwicklerabschnitt mehr.
    expect(
      has('about_dev_section'),
      isFalse,
      reason: 'S2 Ueber ohne Abschnitt',
    );
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
    await waitFor(
      t,
      () => has('overview_developer'),
      'S2 Entwicklereinstellungen in der Uebersicht (overview_developer)',
      timeout: const Duration(seconds: 10),
    );
    await back(t);
    await waitFor(t, () => has('home_start_run'), 'Heute');
    log('S2 karte_sofort=${has('morning_card')}');
    await waitFor(
      t,
      () => has('morning_card'),
      'S2 Karte erscheint (morning_card)',
      timeout: const Duration(seconds: 10),
    );
    await shot(t, 's2_heute_an');

    step('MORNING S3 fenster');
    // Das Fenster liegt fuer die Faelle 3 bis 6 immer um der Systemzeit (die Uhr
    // der App ist die Systemuhr), auch wenn das Vorgabefenster passen wuerde: ein
    // Lauf ueber eine Stundengrenze bleibt so im Fenster.
    final nowU = w.deps.clock.now();
    final off = w.deps.clock.utcOffsetAt(nowU);
    final hNow = nowU.add(off).hour;
    final inWindow = MorningWindow(
      hNow > 0 ? hNow - 1 : 0,
      hNow < 22 ? hNow + 2 : 24,
    );
    await t.runAsync(
      () => SettingsMorningWindowStore(s.settings, w.deps.clock).set(inWindow),
    );
    log('S3 fenster=${inWindow.format()}');
    // Die Morgentabelle kann schon Zeilen haben: alles relativ zur Ausgangszahl.
    final baseList = await stored(t, s);
    final base = baseList.length;
    final base0 = await t.runAsync(
      () => countMorningPairs((s as MorningStorage).morning),
    );
    final nowB = w.deps.clock.now();
    final baseToday = morningCountingToday(
      await stored(t, s),
      nowUtc: nowB,
      utcOffset: w.deps.clock.utcOffsetAt(nowB),
    ).length;
    final baseOutside = (await stored(
      t,
      s,
    )).where((e) => e.outsideWindow).length;
    // Vorzustand VOR dem Schritt gelesen: zaehlt heute schon eine Messung (Tabelle
    // nicht leer, mit einer Emulator-Kamera gibt es nur ein Geraet), zaehlt auch die
    // liegende nicht; sonst genau eine.
    final gain = baseToday == 0 ? 1 : 0;
    log('S3 ausgang=$base zaehlt_heute_vorher=$baseToday gain=$gain');

    step('MORNING S3 liegend_sitzend');
    // 3) liegend gut, dann sitzend gut am selben Morgen. Eine Reihe je Geraet
    // (K67): nur die erste gueltige des Morgens zaehlt, die zweite wird
    // gespeichert und als „zaehlt nicht“ vermerkt. Hatte das Geraet heute schon
    // eine zaehlende Messung (Tabelle nicht leer), zaehlt auch die liegende nicht.
    await measureFromTile(t);
    expect(has('morning_again'), isFalse, reason: 'S3 liegend gut');
    log(
      'S3 liegend note_not_counted=${has('morning_note_not_counted')} outside=${has('morning_note_outside')}',
    );
    await shot(t, 's3_ergebnis_liegend');
    var l = await storedCount(t, s, base + 1);
    expect(l.length, base + 1, reason: 'S3 eine gespeichert');
    expect(
      has('morning_note_not_counted'),
      gain == 0,
      reason: 'S3 liegend: erste gueltige des Morgens zaehlt',
    );
    await closeResultToHome(t);
    await measureFromTile(t, sitting: true);
    log(
      'S3 sitzend note_not_counted=${has('morning_note_not_counted')} outside=${has('morning_note_outside')}',
    );
    expect(
      has('morning_note_not_counted'),
      isTrue,
      reason: 'S3 sitzend zaehlt nicht (K67, eine Reihe je Geraet)',
    );
    await shot(t, 's3_ergebnis_sitzend');
    l = await storedCount(t, s, base + 2);
    expect(l.length, base + 2, reason: 'S3 zwei gespeichert');
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
    expect(
      today.length,
      baseToday + gain,
      reason: 'S3 nur die erste gueltige des Morgens zaehlt (K67)',
    );
    await closeResultToHome(t);
    await shot(t, 's3_heute_karte');

    step('MORNING S4 schlecht_dann_gueltig');
    // 4) schlechte Qualitaet -> Noch einmal -> gueltig; die schlechte wird im
    // Entwicklermodus gespeichert (K68), zaehlt aber nirgends.
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
    // Entwicklermodus (S2): die unbrauchbare Messung wird gespeichert (K68),
    // zaehlt aber nirgends.
    final afterBad = await storedCount(t, s, base + 3);
    expect(afterBad.length, base + 3, reason: 'S4 schlechte gespeichert (K68)');
    expect(
      afterBad.where((e) => !e.isUsable).length,
      1,
      reason: 'S4 genau eine unbrauchbare',
    );
    final nowS4 = w.deps.clock.now();
    expect(
      morningCountingToday(
        afterBad,
        nowUtc: nowS4,
        utcOffset: w.deps.clock.utcOffsetAt(nowS4),
      ).length,
      baseToday + gain,
      reason: 'S4 unbrauchbare zaehlt nicht',
    );
    cam.scenario = DebugPpgScenario.goodPulse;
    await tapKey(t, 'morning_again');
    // Noch einmal startet gleich die Messung, ohne neue Ruhephase.
    await waitFor(t, () => !has('morning_again'), 'Ergebnis 1 verlassen');
    log(
      'S4 nach_again rest=${has('measure_rest_clock')} start=${has('morning_start')}',
    );
    await waitFor(
      t,
      resultSettled,
      'Ergebnis 2',
      timeout: const Duration(seconds: 60),
    );
    expect(has('morning_done'), isTrue, reason: 'S4 gueltig');
    expect(
      has('morning_note_not_counted'),
      isTrue,
      reason: 'S4 gueltige zaehlt nicht, die Reihe hat heute schon eine',
    );
    l = await storedCount(t, s, base + 4);
    expect(l.length, base + 4, reason: 'S4 gueltige gespeichert');
    await shot(t, 's4_ergebnis_gueltig');
    await closeResultToHome(t);
    log('S4 ok');

    step('MORNING S5 ausserhalb_fenster');
    // 5) ausserhalb des Fensters (Fenster ueber den Speicher verlegt, Systemuhr).
    final away = hNow < 12
        ? MorningWindow(hNow + 2, 24)
        : MorningWindow(0, hNow - 1);
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
    l = await storedCount(t, s, base + 5);
    expect(
      l.where((e) => e.outsideWindow).length,
      baseOutside + 1,
      reason: 'S5 genau eine ausserhalb',
    );
    await closeResultToHome(t);
    await t.runAsync(
      () => SettingsMorningWindowStore(s.settings, w.deps.clock).set(inWindow),
    );
    log('S5 ok');

    step('MORNING morgenwerte');
    // Morgenwerte (Verlauf) hell/dunkel Sicht.
    await tapKey(t, 'home_overview');
    await tapKey(t, 'overview_morning_values');
    await waitFor(t, () => has('morning_legend'), 'Morgenwerte');
    await shot(t, 's3_morgenwerte');
    // Haltungsmarke: liegend gefuellt, sitzend hohl; die Zeile nennt die Haltung
    // im Semantics-Label (K67). Nur Werte dieses Laufs (synthetische Kamera).
    final sem = t.ensureSemantics();
    var lyingRows = 0, sittingRows = 0;
    final labels = <RestingPosture, Set<String>>{
      RestingPosture.lying: {},
      RestingPosture.sitting: {},
    };
    for (final m in await stored(t, s)) {
      final row = find.byKey(
        Key('morning_row_${m.measuredAt.millisecondsSinceEpoch}'),
      );
      if (row.evaluate().isEmpty) continue;
      final c = RamuriColors.of(t.element(row));
      final dot = t
          .widgetList<Container>(
            find.descendant(of: row, matching: find.byType(Container)),
          )
          .map((e) => e.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.shape == BoxShape.circle);
      final filled = dot.color != c.surface;
      expect(
        filled,
        m.posture == RestingPosture.lying && m.isUsable,
        reason:
            'Morgenwerte: Marke gefuellt nur bei liegend (unbrauchbar: hohl)',
      );
      labels[m.posture]!.add(t.getSemantics(row).label);
      if (m.posture == RestingPosture.lying) {
        lyingRows++;
      } else {
        sittingRows++;
      }
    }
    log('Morgenwerte marken liegend=$lyingRows sitzend=$sittingRows');
    expect(lyingRows, greaterThan(0), reason: 'Morgenwerte liegend sichtbar');
    expect(sittingRows, greaterThan(0), reason: 'Morgenwerte sitzend sichtbar');
    expect(
      labels[RestingPosture.lying]!.intersection(
        labels[RestingPosture.sitting]!,
      ),
      isEmpty,
      reason: 'Semantics-Label nennt die Haltung',
    );
    sem.dispose();
    // Bildschirmfotos dunkel und hell (Systemhelligkeit der Testumgebung).
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await waitFor(
      t,
      () => themeAt(t, 'morning_legend') == Brightness.dark,
      'Morgenwerte dunkel (morning_legend)',
    );
    await shot(t, 's3_morgenwerte_marken_dunkel');
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await waitFor(
      t,
      () => themeAt(t, 'morning_legend') == Brightness.light,
      'Morgenwerte hell (morning_legend)',
    );
    await shot(t, 's3_morgenwerte_marken_hell');
    t.platformDispatcher.clearPlatformBrightnessTestValue();
    await tapKey(t, 'measure_back');
    await back(t);

    step('MORNING S5b ohne_gurt');
    // 5b) Gurtzeile ohne bekannten Gurt. Frueher laufende Gruppen der Sammlung
    // (Lauf) haben einen Gurt verbunden und bekannt gemacht, und die App kann
    // einzelne bekannte Geraete nicht entfernen. Deshalb bekommt der
    // Sensor-Manager hier einen leeren Test-Speicher (attachStore, die
    // oeffentliche Schnittstelle der App); er trennt dabei alle Geraete ohne
    // Eintrag. Der echte Speicher bleibt unberuehrt und wird nach S6 wieder
    // angebunden. Kein bedingtes Ueberspringen.
    final sensors = w.deps.sensors;
    final realDevices = s.devices;
    final testDevices = FakeKnownDeviceStore(FakeStorageData());
    log(
      'S5b vorher bekannt=${sensors.knownEntries.length} verbunden=${sensors.connectedIds.length}',
    );
    await t.runAsync(() => sensors.attachStore(testDevices));
    await waitFor(
      t,
      () => sensors.knownEntries.isEmpty && sensors.connectedIds.isEmpty,
      'S5b Test-Speicher angebunden, kein Geraet bekannt oder verbunden',
    );
    expect(sensors.knownEntries, isEmpty, reason: 'S5b kein Geraet bekannt');
    expect(sensors.connectedIds, isEmpty, reason: 'S5b kein Geraet verbunden');
    log(
      'S5b ausgang bekannt=${sensors.knownEntries.length} verbunden=${sensors.connectedIds.length}',
    );
    await tapKey(t, 'home_overview');
    await tapKey(t, 'overview_morning');
    await waitFor(t, () => has('morning_start'), 'Einstieg ohne Gurt');
    expect(has('morning_gurt_pick'), isTrue, reason: 'S5b Gurt verbinden');
    expect(has('morning_gurt_note'), isTrue, reason: 'S5b Hinweis ohne Gurt');
    final noBelt = AppLocalizations.of(
      t.element(find.byKey(const Key('morning_gurt_text'))),
    ).morningGurtNone;
    expect(txt('morning_gurt_text'), noBelt, reason: 'S5b kein Gurt');
    log('S5b geprueft kein_gurt=true');
    await shot(t, 's5b_einstieg_ohne_gurt');
    await tapKey(t, 'morning_gurt_pick');
    await waitFor(t, () => has('sensors_scan'), 'Geraeteauswahl');
    await back(t);
    await waitFor(t, () => has('morning_start'), 'zurueck im Einstieg');
    await tapKey(t, 'measure_back');
    await back(t);

    step('MORNING S6 gurt_paar');
    // 6) Gurt mit RR: Paar gespeichert, Zaehler, Teilen mit Warnung. Der Gurt
    // ist bekannt, aber getrennt; das Oeffnen des Einstiegs verbindet ihn
    // selbst (Autoverbinden, WP37 C2), ohne dass der Test verbindet.
    w.sensor.sendRr = true;
    await t.runAsync(
      () => testDevices.upsert(
        'fake-gurt-1',
        displayName: DebugTestSensor.devices['fake-gurt-1'],
        at: DateTime.now().toUtc(),
      ),
    );
    await t.runAsync(sensors.reloadKnown);
    expect(sensors.knownEntries.length, 1, reason: 'S6 Gurt bekannt');
    expect(sensors.connectedIds, isEmpty, reason: 'S6 Gurt getrennt');
    log('S6 vorher bekannt=1 verbunden=0');
    await tapKey(t, 'home_overview');
    await tapKey(t, 'overview_morning');
    await waitFor(t, () => has('morning_start'), 'Einstieg mit Gurt');
    final noBeltText = noBelt;
    await waitFor(
      t,
      () =>
          sensors.connectedIds.contains('fake-gurt-1') &&
          has('morning_gurt_text') &&
          txt('morning_gurt_text') != noBeltText,
      'S6 Autoverbinden beim Oeffnen',
    );
    log('S6 autoverbunden=${sensors.connectedIds.length}');
    // Echter Speicher wieder angebunden; der Gurt wird dort bekannt gemacht,
    // damit er verbunden bleibt (Zustand wie nach der Gruppe Lauf).
    await t.runAsync(
      () => realDevices.upsert(
        'fake-gurt-1',
        displayName: DebugTestSensor.devices['fake-gurt-1'],
        at: DateTime.now().toUtc(),
      ),
    );
    await t.runAsync(() => sensors.attachStore(realDevices));
    expect(
      sensors.connectedIds,
      contains('fake-gurt-1'),
      reason: 'S6 nach Wiederanbinden verbunden',
    );
    // (a) Bekannter, verbundener Gurt: ohne Rueckfrage „verbunden: ...“; nach
    // Schliessen und erneutem Oeffnen des Einstiegs unveraendert.
    for (var i = 0; i < 2; i++) {
      await waitFor(
        t,
        () =>
            has('morning_gurt_text') && txt('morning_gurt_text') != noBeltText,
        'Gurtzeile verbunden',
      );
      expect(has('morning_gurt_pick'), isFalse, reason: 'S6 keine Rueckfrage');
      expect(has('morning_gurt_note'), isFalse, reason: 'S6 kein Hinweis');
      log(
        'S6 gurtzeile verbunden=${w.deps.sensors.connectedIds.length} oeffnung=$i',
      );
      if (i == 0) {
        await tapKey(t, 'measure_back');
        await tapKey(t, 'overview_morning');
        await waitFor(t, () => has('morning_start'), 'Einstieg neu geoeffnet');
      }
    }
    log('S6 gurt_hinweis=${has('morning_belt_hint')}');
    await shot(t, 's6_einstieg_gurt');
    await toResult(t);
    await shot(t, 's6_ergebnis_gurt');
    l = await storedCount(t, s, base + 6);
    expect(l.length, base + 6, reason: 'S6 gespeichert');
    final pairs = await t.runAsync(
      () => countMorningPairs((s as MorningStorage).morning),
    );
    log('S6 paare mit=${pairs!.withBelt} ohne=${pairs.without}');
    expect(pairs.withBelt, base0!.withBelt + 1, reason: 'S6 ein Gurt-Paar');
    // Zwei in S3, unbrauchbar und gueltige in S4, eine in S5.
    expect(pairs.without, base0.without + 5);
    await closeResultToHome(t);
    await tapKey(t, 'home_overview');
    await waitFor(t, () => has('overview_developer'), 'S6 Uebersicht');
    await tapKey(t, 'overview_developer');
    await waitFor(
      t,
      () => has('about_pairs_count') && txt('about_pairs_count').isNotEmpty,
      'Zaehler geladen (about_pairs_count)',
    );
    log('S6 zaehler_text_laenge=${txt('about_pairs_count').length}');
    await shot(t, 's6_entwickler_paare');
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

    step('MORNING S7 ruhephase_ueberspringen');
    // 7) Ruhephase ueberspringen: die Messung startet sofort, der Fortschritt
    // zeigt „Gutes Signal“, das Ergebnis kommt, der Vermerk ist gespeichert.
    // Zeitraffer langsamer, damit der Fortschritt sichtbar bleibt.
    await back(t); // Entwicklereinstellungen -> Uebersicht
    final countBefore7 = (await stored(t, s)).length;
    cam.speed = 10;
    await tapKey(t, 'overview_morning');
    await waitFor(t, () => has('morning_start'), 'S7 Einstieg');
    await tapKey(t, 'morning_start');
    await waitFor(t, () => has('measure_rest_clock'), 'S7 Ruhephase');
    await tapKey(t, 'morning_skip_rest');
    await waitFor(
      t,
      () => !has('measure_rest_clock') && has('measure_progress_label'),
      'S7 Messung sofort',
      timeout: const Duration(seconds: 10),
    );
    final l10n7 = AppLocalizations.of(
      t.element(find.byKey(const Key('measure_progress_label'))),
    );
    final goodPrefix = l10n7
        .morningProgressGood('\u0001', '\u0002')
        .split('\u0001')
        .first;
    await waitFor(
      t,
      () =>
          has('measure_progress_label') &&
          txt('measure_progress_label').startsWith(goodPrefix),
      'S7 Fortschritt gutes Signal',
      timeout: const Duration(seconds: 60),
    );
    await shot(t, 's7_gutes_signal');
    await waitFor(
      t,
      resultSettled,
      'S7 Ergebnis',
      timeout: const Duration(seconds: 60),
    );
    cam.speed = 30;
    l = await storedCount(t, s, countBefore7 + 1);
    expect(l.length, countBefore7 + 1, reason: 'S7 gespeichert');
    final skipped =
        (l.toList()..sort((a, b) => a.measuredAt.compareTo(b.measuredAt))).last;
    expect(
      skipped.restSkippedAfterS,
      isNotNull,
      reason: 'S7 Vermerk Ruhephase uebersprungen gespeichert',
    );
    log('S7 vermerk_nach_s=${skipped.restSkippedAfterS!.toStringAsFixed(1)}');
    await closeResultToHome(t);
    await tapKey(t, 'home_overview');
    await waitFor(t, () => has('overview_developer'), 'S7 Uebersicht');
    await tapKey(t, 'overview_developer');
    await waitFor(
      t,
      () => has('about_dev_switch'),
      'S7 Entwicklereinstellungen',
    );

    step('MORNING S8 entwicklermodus_aus');
    // 8) Entwicklermodus aus: Seite zu, Eintraege weg.
    await tapKey(t, 'about_dev_switch');
    await waitFor(
      t,
      () => !has('about_dev_switch') && has('overview_about'),
      'S8 Entwicklereinstellungen geschlossen',
    );
    await waitFor(
      t,
      () => !has('overview_developer'),
      'S8 Eintrag Entwicklereinstellungen weg',
    );
    await shot(t, 's8_uebersicht_aus');
    expect(
      (await t.runAsync(
        () => SettingsDeveloperModeStore(s.settings, w.deps.clock).read(),
      )),
      isFalse,
    );
    await back(t);
    await waitFor(t, () => has('home_start_run'), 'Heute');
    await waitFor(t, () => !has('morning_card'), 'Karte weg');
    await shot(t, 's8_heute_aus');
    await tapKey(t, 'home_overview');
    await waitFor(t, () => has('overview_about'), 'Uebersicht');
    // Negativpruefung: der Entwicklermodus wird beim Laden der Uebersicht
    // gelesen; das Fehlen gilt erst, wenn der Einstieg fertig geladen hat.
    await entryLoaded(t, MorningTile, 'S8 Uebersicht');
    expect(has('overview_morning'), isFalse, reason: 'S8 Eintrag weg');
    log('S8 ok');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
