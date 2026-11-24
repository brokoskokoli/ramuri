// E2E: Morgenmessung (FR-0215/0217, WP33) mit Fake-Kamera (DebugTestPpgCamera,
// Zeitraffer 30) und Test-Sensor mit RR (DebugTestSensor sendRr). Ein Ablauf,
// weil die Schritte aufeinander aufbauen (Entwicklermodus, Messungen des Tages):
// 1 ohne Entwicklermodus kein Einstieg, 3 die erste Messung zeigt die
// Kamerasuche vor der Ruhephase (FR-0220, volle Ruhephase danach), 2 neun Tipps nein / zehn ja, 3 liegend und
// sitzend: beide gespeichert, aber nur die erste gueltige des Morgens zaehlt
// (eine Reihe je Geraet, K67), 3b nach gueltiger Messung im Fenster Noch einmal
// (Einstieg, andere Haltung, Ruhephase) -> zweite zaehlt nicht -> stattdessen
// verwenden -> Morgenwerte und Karte zeigen sie -> auf Morgenwerte die erste
// wieder waehlen (PAR-160K), 4 schlecht -> im Entwicklermodus trotzdem
// gespeichert (K68, unbrauchbar, zaehlt nirgends) -> Noch einmal (Einstieg,
// Ruhephase) -> gueltig (zaehlt nicht, die Reihe hat heute schon eine), 5
// ausserhalb des Fensters markiert, ohne Noch einmal
// (Fenster ueber den Einstellungsspeicher gesetzt, die Uhr der App ist die
// Systemuhr), Morgenwerte: Haltungsmarke gefuellt/hohl und Bildschirmfotos
// hell/dunkel, 5b Gurtzeile ohne bekannten Gurt (Test-Speicher ohne Geraete),
// 6 Gurt bekannt, aber getrennt: Autoverbinden beim Oeffnen („verbunden“, auch
// nach erneutem Oeffnen), Gurt-Paar gespeichert + Zaehler + Teilen-Warnung,
// 6b Kamera gegen Gurt: je Gurt-Paar eine Zeile, die von S6 mit Zuordnung (Gurt
// folgt dem Schlagplan der Fake-Kamera), Detail mit Kurve,
// 7 Ruhephase ueberspringen (Fortschritt, vermerkt), 8 Entwicklermodus aus ->
// 7b Uhrzeit der Morgen-Erinnerung ueber den Zeitwaehler (geplanter Zeitpunkt
// am Plattformkanal und im Speicher), 7c feste Uhr: Messung um 23:58 und um
// 00:02 -> zwei Ortstage, je eine zaehlende Messung (FR-0215, K67), 7d
// Diagnose-Schalter Rauschunterdrueckung aus -> Morgenmessung -> Messpaare-CSV
// mit Schalter und raw_isp je Bild -> Schalter aus (FR-0217), 8
// Entwicklermodus aus -> Einstieg weg (mit S1 die Pruefung K62 F1). Nur Zaehler
// und Marken in der Ausgabe.
// Mit E2E_SHOTS=1 sh tool/ci_e2e.sh macht der Host bei "E2E_.. SHOT <name>" ein Bildschirmfoto (shot in support/e2e_support.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adapters/adapters.dart' show reminderChannelName;
import 'package:core/core.dart';
import 'package:core/fakes/fake_storage_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/features/measure/morning_entry.dart';
import 'package:running_app/features/measure/morning_result_view.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/system_clock.dart';
import 'package:running_app/ui/ui.dart';

import 'support/e2e_support.dart';

/// Systemuhr, deren monotone Zeit der Test vorstellen kann ([jump]): die feste
/// Ruhephase der Morgenmessung (kein Ueberspringen) endet dann gleich. Die
/// Wanduhr (Fenster, Zeitstempel) bleibt echt, solange [wall] leer ist; mit
/// [wall] steht sie fest (Fall um Mitternacht). Die monotone Zeit bleibt
/// monoton und laeuft sonst in Echtzeit (die Kamera-Aufnahme prueft Abstaende
/// damit).
class _FastClock implements Clock {
  final _sw = Stopwatch()..start();
  Duration _bonus = Duration.zero;
  void jump(Duration d) => _bonus += d;

  /// Feste Wanduhr (UTC); `null` = Systemuhr.
  DateTime? wall;
  @override
  DateTime now() => wall ?? const SystemClock().now();
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

/// Mit [finder] erscheint nach dem Start zuerst die Kamerasuche (FR-0220, noch
/// kein Suchergebnis): Zeit darauf (Testuhr vorgestellt) zaehlt nicht, die
/// Ruhephase danach hat die volle Dauer von 2 min.
Future<void> toResult(WidgetTester t, {bool finder = false}) async {
  await tapKey(t, 'morning_start');
  try {
    if (finder) {
      await waitFor(
        t,
        () => has('camera_finder_apply') || has('camera_finder_default'),
        'Kamerasuche vor der Ruhephase',
        timeout: const Duration(seconds: 30),
      );
      expect(has('measure_rest_clock'), isFalse, reason: 'Ruhephase danach');
      _clk.jump(const Duration(minutes: 5));
      await pumpFor(t, const Duration(milliseconds: 300));
      await tapKey(
        t,
        has('camera_finder_apply')
            ? 'camera_finder_apply'
            : 'camera_finder_default',
      );
      await waitFor(t, () => has('measure_rest_clock'), 'Ruhephase');
      expect(
        txt('measure_rest_clock'),
        anyOf('2:00', '1:59', '1:58'),
        reason: 'volle Ruhephase nach der Kamerasuche',
      );
    }
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
Future<void> measureFromTile(
  WidgetTester t, {
  bool sitting = false,
  bool finder = false,
}) async {
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
  await toResult(t, finder: finder);
}

/// Seite „Heute“ steht: am Schluessel der Seite, nicht an „Lauf starten“ –
/// die Morgenkarte mit „Noch einmal messen“ kann den Knopf unter den
/// sichtbaren Bereich schieben, dann baut die Liste ihn nicht.
bool onToday() => has('home_screen');

Future<void> closeResultToHome(WidgetTester t) async {
  await tapKey(t, 'morning_done');
  await waitFor(t, () => has('overview_about'), 'Uebersicht');
  await back(t);
  await waitFor(t, () => onToday(), 'Heute');
}

/// Zeichnet die Aufrufe der App am Kanal der Erinnerungen auf und reicht jeden
/// unveraendert an die Plattform weiter (der Wecker wird echt gestellt). Die
/// Aufzeichnung endet mit [stopReminderCalls].
List<MethodCall> recordReminderCalls(WidgetTester t) {
  final calls = <MethodCall>[];
  final m = t.binding.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  m.setMockMessageHandler(reminderChannelName, (msg) {
    if (msg != null) calls.add(codec.decodeMethodCall(msg));
    return m.delegate.send(reminderChannelName, msg) ?? Future.value();
  });
  addTearDown(() => stopReminderCalls(t));
  return calls;
}

void stopReminderCalls(WidgetTester t) => t.binding.defaultBinaryMessenger
    .setMockMessageHandler(reminderChannelName, null);

/// Zeitpunkte (Ortszeit des Geraets) aller `scheduleMorning`-Aufrufe.
List<DateTime> scheduledMorning(List<MethodCall> calls) => [
  for (final c in calls)
    if (c.method == 'scheduleMorning')
      DateTime.fromMillisecondsSinceEpoch(
        (c.arguments as Map<Object?, Object?>)['at']! as int,
      ),
];

Future<MorningReminderSettings> reminderSettings(
  WidgetTester t,
  StorageSession s,
) async => (await t.runAsync(() => MorningReminderSettings.load(s.settings)))!;

bool reminderSwitchReady() {
  final f = find.byKey(const Key('morning_reminder_switch'));
  return f.evaluate().isNotEmpty &&
      (f.evaluate().first.widget as SwitchListTile).onChanged != null;
}

/// 7b) Morgen-Erinnerung einschalten, die Uhrzeit ueber den Zeitwaehler
/// (Eingabe per Tastatur) aendern und pruefen, dass die geplante Erinnerung
/// (Aufruf `scheduleMorning` an der Plattform) und der Speicher die neue Zeit
/// tragen; danach wieder aus (kein Wecker fuer spaetere Gruppen).
Future<void> reminderTimeViaUi(WidgetTester t, StorageSession s) async {
  final calls = recordReminderCalls(t);
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_morning_values');
  await waitFor(t, () => has('morning_legend'), 'S7b Morgenwerte');
  await waitFor(t, reminderSwitchReady, 'S7b Schalter Erinnerung bedienbar');
  final before = await reminderSettings(t, s);
  log('S7b vorher an=${before.enabled}');
  if (!before.enabled) {
    await tapKey(t, 'morning_reminder_switch');
    await waitFor(
      t,
      () => scheduledMorning(calls).isNotEmpty,
      'S7b eingeschaltet: Erinnerung geplant (scheduleMorning)',
    );
  }
  expect(
    (await reminderSettings(t, s)).enabled,
    isTrue,
    reason: 'S7b eingeschaltet gespeichert',
  );
  // Neue Zeit: sicher verschieden von der gespeicherten, vormittags (gleich
  // in 12- und 24-Stunden-Anzeige ohne AM/PM-Wechsel).
  const a = 7 * 60 + 45, b = 7 * 60 + 15;
  final target = before.minuteOfDay == a ? b : a;
  await waitFor(
    t,
    () =>
        has('morning_reminder_time') &&
        t
            .widget<ListTile>(find.byKey(const Key('morning_reminder_time')))
            .enabled,
    'S7b Zeile Uhrzeit bedienbar',
  );
  calls.clear();
  await tapKey(t, 'morning_reminder_time');
  await waitFor(
    t,
    () => find.byType(TimePickerDialog).evaluate().isNotEmpty,
    'S7b Zeitwaehler offen',
  );
  await t.tap(find.byIcon(Icons.keyboard_outlined));
  await pumpFor(t, const Duration(milliseconds: 500));
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await waitFor(
    t,
    () => fields.evaluate().length >= 2,
    'S7b Eingabefelder Stunde und Minute',
  );
  await t.enterText(fields.at(0), '${target ~/ 60}');
  await pumpFor(t, const Duration(milliseconds: 300));
  await t.enterText(fields.at(1), (target % 60).toString().padLeft(2, '0'));
  await pumpFor(t, const Duration(milliseconds: 300));
  await shot(t, 's7b_zeitwaehler');
  final ok = MaterialLocalizations.of(t.element(find.byType(TimePickerDialog)))
      .okButtonLabel;
  // Taste im Dialog: kein ensureVisible (wie tapDialog, ohne eigenen Schluessel).
  await t.tap(
    find.descendant(of: find.byType(TimePickerDialog), matching: find.text(ok)),
  );
  await pumpFor(t, const Duration(milliseconds: 300));
  await waitFor(
    t,
    () => find.byType(TimePickerDialog).evaluate().isEmpty,
    'S7b Zeitwaehler zu',
  );
  await waitFor(
    t,
    () => scheduledMorning(calls).isNotEmpty,
    'S7b neu geplant (scheduleMorning)',
  );
  final at = scheduledMorning(calls).last;
  final now = DateTime.now();
  log('S7b geplant n=${scheduledMorning(calls).length}');
  expect(
    at.hour * 60 + at.minute,
    target,
    reason: 'S7b geplante Erinnerung traegt die neue Uhrzeit',
  );
  expect(at.isAfter(now), isTrue, reason: 'S7b naechster Zeitpunkt danach');
  expect(
    at.difference(now) <= const Duration(days: 1),
    isTrue,
    reason: 'S7b naechster Zeitpunkt innerhalb eines Tages',
  );
  final saved = await reminderSettings(t, s);
  expect(saved.minuteOfDay, target, reason: 'S7b Uhrzeit gespeichert');
  expect(saved.enabled, isTrue, reason: 'S7b bleibt eingeschaltet');
  final row = find.byKey(const Key('morning_reminder_time'));
  final ctx = t.element(row);
  final shown = MaterialLocalizations.of(ctx).formatTimeOfDay(
    TimeOfDay(hour: target ~/ 60, minute: target % 60),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(ctx),
  );
  expect(
    find.descendant(of: row, matching: find.text(shown)),
    findsOneWidget,
    reason: 'S7b Zeile zeigt die neue Uhrzeit',
  );
  await shotHellDunkel(t, 's7b_erinnerung_neu', 'morning_reminder_time');
  // Wieder aus: gestrichen und gespeichert.
  calls.clear();
  await tapKey(t, 'morning_reminder_switch');
  await waitFor(
    t,
    () => calls.any((c) => c.method == 'cancelMorning'),
    'S7b aus: Erinnerung gestrichen (cancelMorning)',
  );
  expect(scheduledMorning(calls), isEmpty, reason: 'S7b aus plant nichts');
  expect(
    (await reminderSettings(t, s)).enabled,
    isFalse,
    reason: 'S7b aus gespeichert',
  );
  stopReminderCalls(t);
  await tapKey(t, 'measure_back');
  await back(t);
  await waitFor(t, () => onToday(), 'S7b Heute');
  log('S7b ok');
}

/// 7c) Feste Wanduhr: eine Messung um 23:58 und eine um 00:02 des Folgetags
/// (Ortszeit) liegen auf zwei Ortstagen; jede ist die erste ihres Tages und
/// zaehlt (FR-0215, K67). Die Tage liegen weit zurueck und haben noch keine
/// Messung (die Morgentabelle kann Zeilen frueherer Gruppen haben).
Future<void> midnight(
  WidgetTester t,
  StorageSession s,
  World w,
  MorningWindow restore,
) async {
  final clock = w.deps.clock;
  final before = await stored(t, s);
  final used = before.map(morningLocalDay).toSet();
  final nowU = clock.now();
  final nowL = nowU.toUtc().add(clock.utcOffsetAt(nowU));
  var day = DateTime.utc(nowL.year, nowL.month, nowL.day - 400);
  DateTime next(DateTime d) => DateTime.utc(d.year, d.month, d.day + 1);
  while (used.contains(day) || used.contains(next(day))) {
    day = DateTime.utc(day.year, day.month, day.day - 1);
  }
  final atLate = DateTime(day.year, day.month, day.day, 23, 58).toUtc();
  final atEarly = DateTime(day.year, day.month, day.day + 1, 0, 2).toUtc();
  // Ganzer Tag als Fenster: beide Zeitpunkte liegen darin.
  await t.runAsync(
    () => SettingsMorningWindowStore(
      s.settings,
      clock,
    ).set(const MorningWindow(0, 24)),
  );
  try {
    // Der ganze Fall bleibt in der Uebersicht: „Heute“ wird erst mit der
    // Systemuhr wieder geoeffnet.
    await tapKey(t, 'home_overview');
    await waitFor(t, () => has('overview_about'), 'S7c Uebersicht');
    _clk.wall = atLate;
    await measureFromOverview(t, 'S7c 23:58');
    expect(has('morning_done'), isTrue, reason: 'S7c 23:58 gueltig');
    expect(
      has('morning_note_outside'),
      isFalse,
      reason: 'S7c 23:58 im Fenster',
    );
    expect(
      has('morning_note_not_counted'),
      isFalse,
      reason: 'S7c 23:58 zaehlt (erste des Ortstags)',
    );
    await storedCount(t, s, before.length + 1);
    await shot(t, 's7c_ergebnis_2358');
    await closeResultToOverview(t, 'S7c 23:58');

    _clk.wall = atEarly;
    await measureFromOverview(t, 'S7c 00:02');
    expect(has('morning_done'), isTrue, reason: 'S7c 00:02 gueltig');
    expect(
      has('morning_note_outside'),
      isFalse,
      reason: 'S7c 00:02 im Fenster',
    );
    expect(
      has('morning_note_not_counted'),
      isFalse,
      reason: 'S7c 00:02 zaehlt (neuer Ortstag, FR-0215)',
    );
    await shot(t, 's7c_ergebnis_0002');
    final after = await storedCount(t, s, before.length + 2);
    expect(after.length, before.length + 2, reason: 'S7c zwei gespeichert');
    await closeResultToOverview(t, 'S7c 00:02');

    final mine = [
      for (final m in after)
        if (morningLocalDay(m) == day || morningLocalDay(m) == next(day)) m,
    ];
    final onLate = mine.where((m) => morningLocalDay(m) == day).toList();
    final onEarly = mine.where((m) => morningLocalDay(m) == next(day)).toList();
    log('S7c tag1=${onLate.length} tag2=${onEarly.length}');
    expect(onLate.length, 1, reason: 'S7c Ortstag 1: genau eine Messung');
    expect(onEarly.length, 1, reason: 'S7c Ortstag 2: genau eine Messung');
    expect(
      onLate.single.measuredAt.isAtSameMomentAs(atLate),
      isTrue,
      reason: 'S7c Zeitpunkt 23:58 (feste Uhr)',
    );
    expect(
      onEarly.single.measuredAt.isAtSameMomentAs(atEarly),
      isTrue,
      reason: 'S7c Zeitpunkt 00:02 (feste Uhr)',
    );
    final countLate = morningCountingToday(
      after,
      nowUtc: atLate,
      utcOffset: clock.utcOffsetAt(atLate),
    );
    final countEarly = morningCountingToday(
      after,
      nowUtc: atEarly,
      utcOffset: clock.utcOffsetAt(atEarly),
    );
    expect(countLate.length, 1, reason: 'S7c Ortstag 1 zaehlt eine');
    expect(countEarly.length, 1, reason: 'S7c Ortstag 2 zaehlt eine');
    expect(
      countLate.single.measuredAt.isAtSameMomentAs(
        countEarly.single.measuredAt,
      ),
      isFalse,
      reason: 'S7c je Ortstag eine eigene Messung',
    );
    log('S7c ok');
  } finally {
    _clk.wall = null;
    await t.runAsync(
      () => SettingsMorningWindowStore(s.settings, clock).set(restore),
    );
  }
  await back(t);
  await waitFor(t, () => onToday(), 'S7c Heute (Systemuhr)');
}

/// Von der Uebersicht ueber den Eintrag Morgenmessung bis zum Ergebnis.
Future<void> measureFromOverview(WidgetTester t, String what) async {
  await tapKey(t, 'overview_morning');
  await waitFor(t, () => has('morning_start'), '$what Einstieg');
  log('$what einstieg');
  await toResult(t);
  log('$what ergebnis');
}

/// Ergebnis schliessen; zurueck in der Uebersicht.
Future<void> closeResultToOverview(WidgetTester t, String what) async {
  await tapKey(t, 'morning_done');
  await waitFor(t, () => has('overview_about'), '$what Uebersicht');
  log('$what zurueck');
}

/// 7d) Diagnose der Kamera-Bildverarbeitung (FR-0217): In den
/// Entwicklereinstellungen „Rauschunterdrueckung aus“ an, eine Morgenmessung,
/// dann die Messpaare-CSV (derselbe Aufbau wie beim Teilen): die neue Messung
/// traegt `diag_noise_reduction_off` = 1, `raw_isp_frames` > 0 und je Bild eine
/// `raw_isp`-Zeile. Danach den Schalter wieder aus. Startet und endet in den
/// Entwicklereinstellungen. Nur Zaehler und Marken ins Log.
Future<void> cameraDiagnostics(
  WidgetTester t,
  StorageSession s,
  World w,
) async {
  const key = 'dev_ppg_diag_noise_reduction_off';
  // Die Entwicklereinstellungen sind eine lazy Liste: erst hinscrollen.
  Future<void> reveal() => t.scrollUntilVisible(
    find.byKey(const Key(key)),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  final store = SettingsPpgCameraDiagnosticsStore(s.settings, w.deps.clock);
  Future<Set<PpgCameraDiagnostic>> read() async =>
      (await t.runAsync(store.read))!;
  expect(await read(), isEmpty, reason: 'S7d Vorgabe: alle Schalter aus');
  await reveal();
  SwitchListTile tile() => t.widget<SwitchListTile>(find.byKey(const Key(key)));
  // Der Abschnitt entsteht erst beim Hinscrollen; bis die Schalter gelesen
  // sind, ist der Schalter gesperrt und ein Tipp wirkungslos.
  await waitFor(t, () => tile().onChanged != null, 'S7d Schalter bedienbar');
  await tapKey(t, key);
  await waitFor(t, () => tile().value, 'S7d Schalter an');
  expect(await read(), {
    PpgCameraDiagnostic.noiseReductionOff,
  }, reason: 'S7d Schalter gespeichert');
  await back(t); // Entwicklereinstellungen -> Uebersicht
  final before = (await stored(t, s)).length;
  await measureFromOverview(t, 'S7d');
  final l = await storedCount(t, s, before + 1);
  expect(l.length, before + 1, reason: 'S7d gespeichert');
  await closeResultToOverview(t, 'S7d');

  final morning = (s as MorningStorage).morning;
  final csv = await t.runAsync(() async {
    final entries = await morning.list();
    entries.sort((a, b) => a.value.measuredAt.compareTo(b.value.measuredAt));
    final id = '${entries.last.id}';
    final file = await buildMorningPairsCsvFile(
      morning,
      now: w.deps.clock.now(),
    );
    return (id: id, text: utf8.decode(file.bytes!));
  });
  // Spalten: format_version, morning_id, row_type, key, seq, sub, time, value.
  // Die Werte enthalten kein Komma (Felder in `value` mit Semikolon getrennt).
  final rows = [
    for (final line in const LineSplitter().convert(csv!.text).skip(1))
      line.split(','),
  ].where((c) => c.length > 7 && c[1] == csv.id).toList();
  String? meta(String k) {
    for (final c in rows) {
      if (c[2] == 'meta' && c[3] == k) return c[7];
    }
    return null;
  }

  final nFrames = rows.where((c) => c[2] == 'raw_frame').length;
  final nIsp = rows.where((c) => c[2] == 'raw_isp').length;
  final ispFrames = int.tryParse(meta('raw_isp_frames') ?? '') ?? -1;
  log(
    'S7d csv version=${rows.isEmpty ? '-' : rows.first[0]} '
    'diag_nr=${meta('diag_noise_reduction_off')} '
    'raw_frame=$nFrames raw_isp=$nIsp raw_isp_frames=$ispFrames',
  );
  expect(rows.first[0], '$morningPairsCsvFormatVersion');
  expect(
    meta('diag_noise_reduction_off'),
    '1',
    reason: 'S7d Schalter mit der Messung gespeichert',
  );
  expect(
    meta('diag_edge_off'),
    '0',
    reason: 'S7d nicht angeforderter Schalter',
  );
  expect(ispFrames, greaterThan(0), reason: 'S7d raw_isp_frames > 0');
  expect(nIsp, ispFrames, reason: 'S7d raw_isp_frames = raw_isp-Zeilen');
  expect(nIsp, nFrames, reason: 'S7d je Bild eine raw_isp-Zeile');

  await tapKey(t, 'overview_developer');
  await waitFor(
    t,
    () => has('about_dev_switch'),
    'S7d Entwicklereinstellungen',
  );
  await reveal();
  // Neu aufgebaut: erst tippen, wenn der gespeicherte Stand (an) gelesen ist.
  await waitFor(
    t,
    () => tile().onChanged != null && tile().value,
    'S7d Schalter gelesen',
  );
  await tapKey(t, key);
  await waitFor(t, () => !tile().value, 'S7d Schalter aus');
  expect(await read(), isEmpty, reason: 'S7d Schalter wieder aus');
  // Fuer S8 wieder nach oben zum Schalter Entwicklermodus.
  await t.scrollUntilVisible(
    find.byKey(const Key('about_dev_switch')),
    -300,
    scrollable: find.byType(Scrollable).first,
  );
  log('S7d ok');
}

/// Ms-Schluessel einer Zeile der Morgenwerte.
String _ms(MorningMeasurement m) => '${m.measuredAt.millisecondsSinceEpoch}';

/// Die Zeile von [m] auf „Morgenwerte“ nennt den Text [text].
bool rowSays(MorningMeasurement m, String text) => find
    .descendant(
      of: find.byKey(Key('morning_row_${_ms(m)}')),
      matching: find.text(text),
    )
    .evaluate()
    .isNotEmpty;

/// „zaehlt“ in der Fassung der Haltung von [m].
String countsText(AppLocalizations l10n, MorningMeasurement m) =>
    m.posture == RestingPosture.lying
    ? l10n.morningRowCounts
    : l10n.morningRowCountsSitting;

/// 3b) Gueltige Messung im Fenster liegt als Ergebnis vor: „Noch einmal
/// messen“ fuehrt ueber den Einstieg (Haltung gewechselt) mit Ruhephase zu
/// einer zweiten Messung, die nicht zaehlt; „Diese Messung stattdessen
/// verwenden“ macht sie zur gueltigen des Tages (PAR-160K). Morgenwerte und
/// Karte zeigen sie; auf „Morgenwerte“ wird die vorherige wieder gewaehlt.
/// [n] ist die Zahl der gespeicherten Messungen vor dem Schritt.
Future<void> repeatAndChoose(
  WidgetTester t,
  StorageSession s,
  World w,
  int n,
) async {
  final clock = w.deps.clock;
  List<MorningMeasurement> countingNow(List<MorningMeasurement> l) {
    final now = clock.now();
    return morningCountingToday(
      l,
      nowUtc: now,
      utcOffset: clock.utcOffsetAt(now),
    );
  }

  expect(
    has('morning_again'),
    isTrue,
    reason: 'S3b gueltig im Fenster: Noch einmal angeboten',
  );
  await tapKey(t, 'morning_again');
  await waitFor(t, () => has('morning_start'), 'S3b Einstieg nach Noch einmal');
  // Die gezaehlte Messung des Geraets: die zweite bekommt die andere Haltung,
  // damit die Karte sie eindeutig nennt (Zeit und Haltung).
  final before = await stored(t, s);
  final last =
      (before.toList()..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)))
          .last;
  final first = countingNow(before).singleWhere(
    (m) =>
        m.deviceManufacturer == last.deviceManufacturer &&
        m.deviceModel == last.deviceModel,
  );
  await tapKey(
    t,
    first.posture == RestingPosture.lying
        ? 'morning_posture_sitting'
        : 'morning_posture_lying',
  );
  await pumpFor(t, const Duration(milliseconds: 300));
  await toResult(t); // Start, Ruhephase (Testuhr), Ergebnis
  expect(has('morning_done'), isTrue, reason: 'S3b zweite gueltig');
  expect(
    has('morning_note_not_counted'),
    isTrue,
    reason: 'S3b zweite zaehlt nicht',
  );
  final l = await storedCount(t, s, n + 1);
  expect(l.length, n + 1, reason: 'S3b zweite gespeichert');
  final second =
      (l.toList()..sort((a, b) => a.measuredAt.compareTo(b.measuredAt))).last;
  expect(second.posture == first.posture, isFalse, reason: 'S3b Haltung');
  await shot(t, 's3b_ergebnis_zaehlt_nicht');
  await tapKey(t, 'morning_use_instead');
  await waitFor(
    t,
    () => !has('morning_note_not_counted') && !has('morning_use_instead'),
    'S3b zweite gewaehlt (Hinweis weg)',
  );
  var now = countingNow(await stored(t, s));
  expect(
    now.any((m) => _ms(m) == _ms(second)) &&
        !now.any((m) => _ms(m) == _ms(first)),
    isTrue,
    reason: 'S3b gespeichert: zweite zaehlt, erste nicht',
  );
  await shot(t, 's3b_ergebnis_gewaehlt');
  await closeResultToHome(t);

  // Karte auf Heute nennt die zweite (Zeit und Haltung).
  await entryLoaded(t, MorningCard, 'S3b Heute');
  final ctx = t.element(find.byKey(const Key('morning_card')));
  final l10n = AppLocalizations.of(ctx);
  final locale = Localizations.localeOf(ctx).toString();
  await waitFor(
    t,
    () => txt('morning_card_when') == morningWhenLabel(l10n, locale, second),
    'S3b Karte zeigt die zweite',
  );
  await shot(t, 's3b_heute_karte');

  // Morgenwerte: zweite zaehlt, erste „zaehlt nicht …“; erste wieder waehlen.
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_morning_values');
  await waitFor(t, () => has('morning_legend'), 'S3b Morgenwerte');
  await waitFor(
    t,
    () =>
        rowSays(second, countsText(l10n, second)) &&
        rowSays(first, l10n.morningRowLater),
    'S3b Morgenwerte: zweite zaehlt, erste zaehlt nicht',
  );
  expect(
    has('morning_choose_${_ms(first)}'),
    isTrue,
    reason: 'S3b erste waehlbar',
  );
  expect(
    has('morning_choose_${_ms(second)}'),
    isFalse,
    reason: 'S3b zaehlende nicht waehlbar',
  );
  await shot(t, 's3b_morgenwerte_gewaehlt');
  await tapKey(t, 'morning_choose_${_ms(first)}');
  await tapDialog(t, 'morning_choose_confirm');
  await waitFor(
    t,
    () =>
        rowSays(first, countsText(l10n, first)) &&
        rowSays(second, l10n.morningRowLater),
    'S3b Morgenwerte: erste wieder gewaehlt',
  );
  now = countingNow(await stored(t, s));
  expect(
    now.any((m) => _ms(m) == _ms(first)) &&
        !now.any((m) => _ms(m) == _ms(second)),
    isTrue,
    reason: 'S3b gespeichert: erste zaehlt wieder',
  );
  await tapKey(t, 'measure_back');
  await back(t);
  await waitFor(t, () => onToday(), 'S3b Heute');
  await entryLoaded(t, MorningCard, 'S3b Heute zurueck');
  await waitFor(
    t,
    () => txt('morning_card_when') == morningWhenLabel(l10n, locale, first),
    'S3b Karte zeigt wieder die erste',
  );
  log('S3b ok');
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
    // Die Sammlung teilt den Speicher: ohne Suchergebnis beginnen (FR-0220).
    await t.runAsync(() async {
      final choice = SettingsPpgCameraChoiceStore(s.settings, w.deps.clock);
      await choice.setAuto(null);
      await choice.setManual(null);
    });
    log(
      'S0 Fenster=${(await t.runAsync(() => SettingsMorningWindowStore(s.settings, w.deps.clock).read()))!.format()}',
    );

    step('MORNING S1 ohne_entwicklermodus');
    // 1) ohne Entwicklermodus: weder Karte noch Eintrag. Das Fehlen gilt erst,
    // wenn Heute steht und der Einstieg seinen Zustand geladen hat.
    await waitFor(t, () => has('home_start_run'), 'S1 Heute (home_start_run)');
    await entryLoaded(t, MorningCard, 'S1 Heute');
    expect(has('morning_card'), isFalse, reason: 'S1 keine Karte');
    await shotHellDunkel(t, 's1_heute_ohne', 'home_screen');
    await tapKey(t, 'home_overview');
    await waitFor(t, () => has('overview_about'), 'S1 Uebersicht');
    await entryLoaded(t, MorningTile, 'S1 Uebersicht');
    expect(has('overview_morning'), isFalse, reason: 'S1 kein Eintrag');
    expect(has('overview_morning_values'), isFalse, reason: 'S1 kein Verlauf');
    expect(has('overview_developer'), isFalse, reason: 'S1 keine Entw.-Seite');
    await shotHellDunkel(t, 's1_uebersicht_ohne', 'overview_about');
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
    await shotHellDunkel(t, 's2_ueber_an', 'about_dev_link');
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
    await waitFor(t, () => onToday(), 'Heute');
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
    // Erste Kamera-Messung ohne Suchergebnis: Kamerasuche vor der Ruhephase.
    await measureFromTile(t, finder: true);
    expect(
      await t.runAsync(
        SettingsPpgCameraChoiceStore(s.settings, w.deps.clock).readAuto,
      ),
      isNotNull,
      reason: 'S3 Suchergebnis gespeichert',
    );
    expect(has('morning_done'), isTrue, reason: 'S3 liegend gut');
    // Gueltig im Fenster: Noch einmal messen wird angeboten (FR-0215).
    expect(has('morning_again'), isTrue, reason: 'S3 liegend Noch einmal');
    log(
      'S3 liegend note_not_counted=${has('morning_note_not_counted')} outside=${has('morning_note_outside')}',
    );
    await shotHellDunkel(t, 's3_ergebnis_liegend', 'morning_done');
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

    step('MORNING S3b noch_einmal_stattdessen');
    // 3b) Vom Ergebnis der sitzenden: Noch einmal (Ruhephase), stattdessen
    // verwenden, auf Morgenwerte zurueckwaehlen; endet auf Heute.
    await repeatAndChoose(t, s, w, base + 2);
    await shotHellDunkel(t, 's3_heute_karte', 'home_screen');

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
    await shotHellDunkel(t, 's4_ergebnis_schlecht', 'morning_again');
    // Entwicklermodus (S2): die unbrauchbare Messung wird gespeichert (K68),
    // zaehlt aber nirgends.
    final afterBad = await storedCount(t, s, base + 4);
    expect(afterBad.length, base + 4, reason: 'S4 schlechte gespeichert (K68)');
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
    // Noch einmal fuehrt ueber den Einstieg; Start beginnt die Ruhephase.
    await waitFor(
      t,
      () => has('morning_start'),
      'S4 Einstieg nach Noch einmal',
    );
    await toResult(t);
    expect(has('morning_done'), isTrue, reason: 'S4 gueltig');
    expect(
      has('morning_note_not_counted'),
      isTrue,
      reason: 'S4 gueltige zaehlt nicht, die Reihe hat heute schon eine',
    );
    l = await storedCount(t, s, base + 5);
    expect(l.length, base + 5, reason: 'S4 gueltige gespeichert');
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
    expect(
      has('morning_again'),
      isFalse,
      reason: 'S5 ausserhalb des Fensters kein Noch einmal',
    );
    await shot(t, 's5_ergebnis_ausserhalb');
    l = await storedCount(t, s, base + 6);
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
    await shotHellDunkel(t, 's3_morgenwerte_marken', 'morning_legend');
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
    // selbst (Autoverbinden, WP37 C2), ohne dass der Test verbindet. Der Gurt
    // sendet die Schlagabstaende der Fake-Kamera (RR-Art passend zur Kamera),
    // damit S6b die Zuordnung findet.
    w.sensor.sendRr = true;
    w.sensor.rrFollowsPpgCamera = cam;
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
    l = await storedCount(t, s, base + 7);
    expect(l.length, base + 7, reason: 'S6 gespeichert');
    final pairs = await t.runAsync(
      () => countMorningPairs((s as MorningStorage).morning),
    );
    log('S6 paare mit=${pairs!.withBelt} ohne=${pairs.without}');
    expect(pairs.withBelt, base0!.withBelt + 1, reason: 'S6 ein Gurt-Paar');
    // Zwei in S3, eine in S3b, unbrauchbar und gueltige in S4, eine in S5.
    expect(pairs.without, base0.without + 6);
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

    step('MORNING S6b kamera_gegen_gurt');
    // 6b) Kamera gegen Gurt (FR-0217): je Morgen mit Gurt-RR eine Zeile, das
    // Detail oeffnet sich. Nur Anzahl und Zuordnung (ja/nein) ins Log, keine
    // Werte. Der Gurt folgt in S6 dem Schlagplan der Fake-Kamera, daher
    // verlangt die Zeile von S6 (die neueste, oben) eine Zuordnung (RMSSD
    // Kamera und Gurt) und das Detail die Kurve.
    final compareRows = find.byWidgetPredicate(
      (wd) =>
          wd.key is ValueKey<String> &&
          (wd.key! as ValueKey<String>).value.startsWith('dev_compare_row_'),
    );
    await t.scrollUntilVisible(
      find.byKey(const Key('dev_compare')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await waitFor(
      t,
      () => compareRows.evaluate().isNotEmpty,
      'S6b Zeilen Kamera gegen Gurt',
    );
    expect(
      compareRows.evaluate().length,
      pairs.withBelt,
      reason: 'S6b je Gurt-Paar eine Zeile',
    );
    final l10n6 = AppLocalizations.of(t.element(compareRows.first));
    final rmssdPrefix = l10n6
        .devCompareRmssd('\u0001', '\u0002')
        .split('\u0001')
        .first;
    final rowTexts = t
        .widgetList<Text>(
          find.descendant(of: compareRows.first, matching: find.byType(Text)),
        )
        .map((e) => e.data ?? '')
        .toList();
    final matched = rowTexts.any((x) => x.startsWith(rmssdPrefix));
    final noMatch = rowTexts.contains(l10n6.devCompareNoMatch);
    log(
      'S6b zeilen=${compareRows.evaluate().length} zuordnung=$matched keine=$noMatch',
    );
    expect(matched, isTrue, reason: 'S6b Zeile von S6 mit Zuordnung');
    expect(noMatch, isFalse, reason: 'S6b Zeile von S6 nicht ohne Zuordnung');
    await t.tap(compareRows.first);
    await waitFor(
      t,
      () => has('dev_compare_detail_rmssd_camera'),
      'S6b Detail Kamera gegen Gurt',
    );
    expect(
      has('dev_compare_chart'),
      isTrue,
      reason: 'S6b Kurve im Detail (Zuordnung)',
    );
    await shot(t, 's6b_vergleich_detail');
    await back(t); // Detail -> Entwicklereinstellungen
    await waitFor(
      t,
      () => has('about_dev_switch') || has('dev_compare'),
      'S6b zurueck',
    );
    // Ab S7 wieder die Standard-RR-Art des Test-Gurts.
    w.sensor.rrFollowsPpgCamera = null;

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

    step('MORNING S7b erinnerung_zeit');
    await reminderTimeViaUi(t, s);

    step('MORNING S7c mitternacht');
    await midnight(t, s, w, inWindow);

    await tapKey(t, 'home_overview');
    await waitFor(t, () => has('overview_developer'), 'S7 Uebersicht');
    await tapKey(t, 'overview_developer');
    await waitFor(
      t,
      () => has('about_dev_switch'),
      'S7 Entwicklereinstellungen',
    );

    step('MORNING S7d kamera_diagnose');
    await cameraDiagnostics(t, s, w);

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
    await waitFor(t, () => onToday(), 'Heute');
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
