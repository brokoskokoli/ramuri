// Gemeinsame Hilfen der Lauf-Integrationstests (Emulator, Test-Sensor).
// Der Test-Sensor (DebugTestSensor) ersetzt nur den Pulsgurt; Rechte, Speicher
// und Aufzeichnung sind echt. Das GPS liefert tool/ci_e2e.sh (adb emu geo fix).
// Ausgabe: Zeilen "E2E_<zeit> ...", nur Marken und Zaehler, keine Messwerte;
// oeffentlich nur "PUB_<zeit> ..." (logPub, step) ohne Werte.
import 'package:core/core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/features/storage/storage_start.dart';
import 'package:running_app/system_clock.dart';

/// Kanarienwert (0x1357): nur vom Test gesendetes RR-Paket, so ist belegt, dass
/// genau dieses Paket gespeichert wurde.
const canaryRr = 4951;

void log(String s) {
  // ignore: avoid_print
  print('E2E_${DateTime.now().toIso8601String().substring(11, 23)} $s');
}

/// Zeile fuer das oeffentliche CI-Log: Praefix "PUB_" statt "E2E_" (tool/ci_e2e.sh
/// filtert nur E2E_). Nur Schluesselnamen und Zustandsmarken, nie Werte
/// (SEC-0001..0010).
void logPub(String s) {
  // ignore: avoid_print
  print('PUB_${DateTime.now().toIso8601String().substring(11, 23)} $s');
}

/// Schrittmarke fuer das oeffentliche CI-Log: Zeile `PUB_<zeit> SCHRITT <name>`.
/// So zeigt ein roter Lauf, bis zu welchem Abschnitt der Test kam. [name] ist
/// eine feste Zeichenkette aus dem Test (Abschnitt- oder Schluesselname), nie aus
/// Daten gebildet; test/e2e_step_test.dart prueft, dass jeder Aufruf ein Literal
/// ohne Interpolation uebergibt (SEC-0001..0010). Werte gehoeren in [log].
void step(String name) => logPub('SCHRITT $name');

/// Ob der Host Bildschirmfotos macht (`E2E_SHOTS=1 sh tool/ci_e2e.sh` reicht
/// `--dart-define=E2E_SHOTS=true` an jede Stufe weiter).
const e2eShots = bool.fromEnvironment('E2E_SHOTS');

/// Marke `SHOT <name>` fuer das Bildschirmfoto des Hosts (Zeile `E2E_`, also
/// nicht im oeffentlichen Log). [name] nur aus `[a-z0-9_-]`, sonst verwirft der
/// Host die Marke. Mit [pause] bleibt die Seite 2,5 s stehen, damit das Foto
/// sie zeigt; Standard: nur, wenn der Host Fotos macht ([e2eShots]).
Future<void> shot(WidgetTester t, String name, {bool pause = e2eShots}) async {
  log('SHOT $name');
  if (pause) await pumpFor(t, const Duration(milliseconds: 2500));
}

/// Helligkeit des Themas, das am Widget mit [key] gilt, oder `null`, solange
/// es nicht im Baum steht (Bedingung fuer [waitFor], wirft nicht).
Brightness? themeAt(WidgetTester t, String key) {
  final e = find.byKey(Key(key)).evaluate();
  return e.isEmpty ? null : Theme.of(e.first).brightness;
}

/// Fotopaar dunkel und hell: schaltet die Systemhelligkeit der Testumgebung
/// auf dunkel, wartet ([waitFor], Frist [timeout]), bis das Thema am Widget
/// [key] dunkel ist, und setzt die Marke `<name>_dunkel`; danach dasselbe hell
/// mit `<name>_hell`. [key] gehoert zur Seite selbst (z. B. Scaffold), nicht
/// zu einem Teil mit eigenem festen Thema (Karte `RamuriCardTone.panel` ist
/// immer dunkel), sonst wird hell nie erreicht. Am Ende gilt wieder die Systemhelligkeit
/// (`clearPlatformBrightnessTestValue`), auch wenn das Warten scheitert, damit
/// ein roter Schritt die folgenden nicht dunkel weiterlaufen laesst. [pause]
/// wie bei [shot]: ohne [e2eShots] kommen keine Pausen dazu, nur das Warten
/// auf das Thema.
Future<void> shotHellDunkel(
  WidgetTester t,
  String name,
  String key, {
  Duration timeout = const Duration(seconds: 40),
  bool pause = e2eShots,
}) async {
  try {
    for (final (b, suffix) in [
      (Brightness.dark, 'dunkel'),
      (Brightness.light, 'hell'),
    ]) {
      t.platformDispatcher.platformBrightnessTestValue = b;
      await waitFor(
        t,
        () => themeAt(t, key) == b,
        'Thema $suffix ($key)',
        timeout: timeout,
      );
      await shot(t, '${name}_$suffix', pause: pause);
    }
  } finally {
    t.platformDispatcher.clearPlatformBrightnessTestValue();
  }
}

/// Meldung eines Testfehlers ohne Werte: bei `expect` nur der Grund (`reason:`),
/// den der matcher ohne Präfix als erste nicht eingerückte Zeile nach
/// Expected/Actual/Which schreibt (diese drei können Werte tragen und fehlen),
/// sonst der Text von `fail(...)` (nur Schlüssel und Zeiten); andere Fehler nur
/// mit ihrem Typ.
String publicFailure(Object e) {
  if (e is! TestFailure) return e.runtimeType.toString();
  final m = e.message ?? '';
  if (!m.startsWith('Expected:')) return m.split('\n').first;
  // Echtes Format (matcher): "Expected: ..", "  Actual: ..", "   Which: ..",
  // Fortsetzungszeilen eingerueckt, danach der Grund ohne Praefix.
  final grund = m
      .split('\n')
      .where(
        (z) =>
            z.trim().isNotEmpty &&
            !z.startsWith(' ') &&
            !z.startsWith('Expected: '),
      )
      .firstOrNull;
  return 'expect: ${grund ?? 'ohne Grund'}';
}

/// Fuehrt [body] aus und schreibt bei einem Fehler dessen Meldung ohne Werte
/// ins oeffentliche Log (sonst verdeckt der Abbau-Fehler am Testende sie).
Future<void> Function(WidgetTester) reportingFailures(
  Future<void> Function(WidgetTester) body,
) => (t) async {
  try {
    await body(t);
  } catch (e) {
    logPub('FEHLER ${publicFailure(e)}');
    rethrow;
  }
};

class World {
  World(this.deps, this.sensor);
  final AppDependencies deps;
  final DebugTestSensor sensor;
}

World buildWorld({PpgCamera? camera, Clock clock = const SystemClock()}) {
  final sensor = DebugTestSensor(const SystemClock());
  return World(
    AppDependencies.create(
      heartRateSensor: sensor,
      ppgCamera: camera,
      clock: clock,
    ),
    sensor,
  );
}

/// Pumpt in echter Zeit (Sensor, GPS und Speicher laufen ausserhalb der
/// Testuhr).
Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Wartet bis [cond] gilt und scheitert sonst mit [what] (kein stilles Weiter).
Future<void> waitFor(
  WidgetTester t,
  bool Function() cond,
  String what, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      fail('nach ${timeout.inSeconds} s nicht erreicht: $what');
    }
    await pumpFor(t, const Duration(milliseconds: 200));
  }
}

bool has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

String txt(String key) {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) return '<fehlt>';
  final w = f.evaluate().first.widget;
  return w is Text ? (w.data ?? '<rich>') : w.runtimeType.toString();
}

/// Frist, in der eine Taste nach dem Tipp aus dem Baum verschwinden muss
/// ([tapDialog], [back]) bzw. vor dem Tipp erscheinen und treffbar werden muss.
const _tapFrist = Duration(seconds: 5);

/// Wartet (Abfrage alle 100 ms, keine feste Pause), bis [gone] gilt; sonst
/// endet der Test mit [meldung]. [what] ist ein Schluesselname fuer das Log.
Future<void> _waitGone(
  WidgetTester t,
  bool Function() gone,
  String what,
  String meldung,
) async {
  final end = DateTime.now().add(_tapFrist);
  while (!gone()) {
    if (DateTime.now().isAfter(end)) {
      logPub('tap_bleibt what=$what');
      fail(meldung);
    }
    await pumpFor(t, const Duration(milliseconds: 100));
  }
}

/// Wartet, bis [f] etwas findet; sonst endet der Test mit [meldung].
Future<void> _waitPresent(WidgetTester t, Finder f, String meldung) async {
  final end = DateTime.now().add(_tapFrist);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail(meldung);
    await pumpFor(t, const Duration(milliseconds: 100));
  }
}

/// Taste in einem Dialog oder Menue, die ihn schliesst: kein ensureVisible (es
/// scrollt sonst die Seite dahinter). Wartet vor dem Tipp, bis die Taste im
/// Baum steht und der Tipp sie trifft (ein Menue geht noch auf: ein Tipp
/// daneben schloesse es ohne Auswahl), und danach, bis genau diese Taste nicht
/// mehr im Baum steht (Dialog bzw. Menue zu); sonst
/// `Dialog-Taste <key> bleibt`. Keine feste Pause. Bleibt ein Dialog bewusst offen:
/// [tapKey]/[tapUntil] mit eigener Bedingung.
Future<void> tapDialog(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await _waitPresent(t, f, 'Dialog-Taste $key fehlt');
  final end = DateTime.now().add(_tapFrist);
  while (!hittable(t, f.first)) {
    if (DateTime.now().isAfter(end)) {
      fail('Tipp trifft Dialog-Taste $key nicht');
    }
    await pumpFor(t, const Duration(milliseconds: 100));
  }
  final ziel = f.evaluate().first;
  await t.tap(f.first);
  await _waitGone(t, () => !ziel.mounted, key, 'Dialog-Taste $key bleibt');
}

/// Ob ein Tipp in die Mitte von [f] dieses Element traefe (nicht verdeckt, die
/// Seite nicht mehr im Uebergang). Findet [f] kein Element (lazy Liste hat das
/// Ziel gerade nicht gebaut), gilt es als nicht treffbar: `false`, kein Wurf.
bool hittable(WidgetTester t, Finder f) {
  final found = f.evaluate();
  if (found.isEmpty) return false;
  final target = found.first.renderObject;
  final hit = HitTestResult();
  t.binding.hitTestInView(hit, t.getCenter(f.first), t.view.viewId);
  return hit.path.any((e) => e.target == target);
}

/// Erstes Widget unter [f] oder `null`, wenn es nicht im Baum steht (lazy
/// Listen bauen Eintraege ausserhalb des Sichtbereichs nicht). Fuer
/// Bedingungen, die nicht werfen duerfen.
T? maybeWidget<T extends Widget>(Finder f) {
  final e = f.evaluate();
  return e.isEmpty ? null : e.first.widget as T;
}

/// Wartet ([waitFor]), bis [f] etwas findet, und liefert das erste Element
/// (z. B. fuer `AppLocalizations.of`); sonst endet der Test mit
/// `nach … s nicht erreicht: <what>`. Fuer Zugriffe nach einem Seitenwechsel
/// oder Scrollen, bevor das Ziel sicher gebaut ist. Keine feste Pause.
Future<Element> elementWhen(
  WidgetTester t,
  Finder f,
  String what, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  await waitFor(t, () => f.evaluate().isNotEmpty, what, timeout: timeout);
  return f.evaluate().first;
}

/// Wie [elementWhen], liefert aber das Widget vom Typ [T].
Future<T> widgetWhen<T extends Widget>(
  WidgetTester t,
  Finder f,
  String what, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  await waitFor(t, () => maybeWidget<T>(f) != null, what, timeout: timeout);
  return maybeWidget<T>(f)!;
}

String _imBaum(Finder f) => f.evaluate().isEmpty ? 'nein' : 'ja';

/// Tipp auf [target] (ein Element unterhalb der Taste [key]): erst auf Ruhe und
/// Treffer warten, danach bis zu einer Frist auf [done] warten; gilt es nicht,
/// einmal erneut tippen und sonst mit klarer Meldung scheitern. Kein festes
/// Zeitpolster.
///
/// [done] darf nicht werfen (fehlt das Widget, gilt sie als nicht erfuellt;
/// siehe [maybeWidget]); eine werfende Bedingung zaehlt ebenfalls als nicht
/// erfuellt. Faellt [target] aus dem Baum (lazy Liste verschoben), bringt
/// [reveal] es vor dem erneuten Pruefen zurueck in den Sichtbereich.
Future<void> tapUntil(
  WidgetTester t,
  Finder target,
  bool Function() done,
  String what, {
  Future<void> Function()? reveal,
}) async {
  bool check() {
    try {
      return done();
    } on StateError {
      return false;
    }
  }

  Future<void> bringBack() async {
    if (target.evaluate().isNotEmpty) return;
    if (reveal != null) {
      await reveal();
    } else {
      await pumpFor(t, const Duration(milliseconds: 100));
    }
  }

  for (var versuch = 1; versuch <= 2; versuch++) {
    if (target.evaluate().isEmpty) {
      logPub('tap_ziel_fehlt what=$what versuch=$versuch');
      await bringBack();
      if (target.evaluate().isEmpty) fail('Taste fehlt: $what');
      // Erst ein Tipp kann wirken; vielleicht hat schon der erste gewirkt.
      if (check()) return;
    }
    await t.ensureVisible(target);
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!hittable(t, target)) {
      if (DateTime.now().isAfter(end)) {
        logPub('tap_miss what=$what versuch=$versuch');
        break;
      }
      if (target.evaluate().isEmpty) {
        // Nach ensureVisible aus dem gebauten Bereich gefallen (Liste
        // verschoben, Tastatur zu): zurueckholen und erneut einblenden.
        logPub('tap_ziel_fehlt what=$what versuch=$versuch');
        await bringBack();
        if (target.evaluate().isEmpty) fail('Taste fehlt: $what');
        await t.ensureVisible(target);
        continue;
      }
      await pumpFor(t, const Duration(milliseconds: 100));
    }
    logPub('tap_vor what=$what versuch=$versuch im_baum=${_imBaum(target)}');
    if (hittable(t, target)) await t.tap(target);
    // Auf die Wirkung warten (bis zur Frist), erst dann erneut tippen: Ein
    // zweiter Tipp wuerde eine verspaetete Wirkung (Umschalter) zuruecknehmen.
    final wirkungEnde = DateTime.now().add(const Duration(seconds: 3));
    var gemeldet = false;
    do {
      await pumpFor(t, const Duration(milliseconds: 100));
      if (target.evaluate().isEmpty) {
        if (!gemeldet) {
          logPub('tap_nach what=$what versuch=$versuch im_baum=nein');
          gemeldet = true;
        }
        await bringBack();
      }
    } while (!check() && DateTime.now().isBefore(wirkungEnde));
    if (!gemeldet) {
      logPub('tap_nach what=$what versuch=$versuch im_baum=${_imBaum(target)}');
    }
    if (check()) return;
    logPub('tap_ohne_wirkung what=$what versuch=$versuch');
  }
  fail('Tipp ohne Wirkung: $what');
}

/// Wartet in echter Zeit (Frist 20 s), bis die Systemtastatur geschlossen ist
/// (`viewInsets.bottom == 0`), vor einem Tipp auf die Taste [key] unter einem
/// Eingabefeld. Die Tastatur schliesst ausserhalb der Testuhr und kann laenger
/// offen bleiben als die Frist von [tapKey]. War sie offen, steht genau eine
/// Zeile `tastatur_offen what=<key>` im oeffentlichen Log (nur der
/// Schluesselname, keine Hoehe, keine Eingabewerte).
Future<void> waitKeyboardClosed(WidgetTester t, String key) async {
  if (_keyboardClosed(t)) return;
  logPub('tastatur_offen what=$key');
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!_keyboardClosed(t)) {
    if (DateTime.now().isAfter(end)) fail('Tastatur bleibt offen vor $key');
    await pumpFor(t, const Duration(milliseconds: 100));
  }
}

bool _keyboardClosed(WidgetTester t) => t.view.viewInsets.bottom == 0;

/// Tipp auf die Taste [key]: wartet vorher, bis sie im Baum steht und der Tipp
/// sie trifft; danach folgt nur ein Frame, keine feste Pause. Die Wirkung
/// prueft der Aufrufer mit [waitFor] oder nimmt gleich [tapUntil].
Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await _waitPresent(t, f, 'Taste $key fehlt');
  await t.ensureVisible(f);
  // Waehrend eines Seitenwechsels liegt die Taste noch verschoben; erst tippen,
  // wenn der Tipp sie trifft (echte Bedingung, sonst Rot mit Schluessel).
  final end = DateTime.now().add(const Duration(seconds: 5));
  var fehlte = false;
  while (!hittable(t, f)) {
    if (DateTime.now().isAfter(end)) fail('Tipp trifft $key nicht');
    // Ausserhalb eines Laufs (Zusammenfassung, Verlauf) kommt die Karten-Frage
    // asynchron (Seite sichtbar -> Einwilligung lesen -> Dialog) und kann sich
    // vor die Taste legen: wegklicken statt Rot.
    await _noConsent(t);
    await pumpFor(t, const Duration(milliseconds: 100));
    // Faellt die Taste aus dem Baum (lazy Liste), gilt sie als nicht
    // treffbar; steht sie wieder im Baum, erneut einblenden.
    if (f.evaluate().isEmpty) {
      if (!fehlte) logPub('tap_ziel_fehlt what=$key versuch=1');
      fehlte = true;
    } else if (fehlte) {
      fehlte = false;
      await t.ensureVisible(f);
    }
  }
  await t.tap(f);
  await t.pump();
}

Future<void> startApp(WidgetTester t, World w) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(RunningApp(dependencies: w.deps));
  await pumpFor(t, const Duration(seconds: 3));
}

/// Offene Speichersitzung der App (wartet, bis der Speicher bereit ist).
Future<StorageSession> session(WidgetTester t, World w) async {
  await waitFor(
    t,
    () => w.deps.storageStart.state is StorageReady,
    'Speicher bereit',
  );
  return (w.deps.storageStart.state as StorageReady).session;
}

/// Ersteinrichtung ueberspringen, falls sie erscheint.
Future<void> setupIfShown(WidgetTester t) async {
  await waitFor(
    t,
    () => has('welcome_start') || has('setup_skip') || has('home_screen'),
    'Willkommen, Einrichtung oder Heute',
  );
  if (has('welcome_start')) {
    await tapKey(t, 'welcome_start');
  }
  await waitFor(
    t,
    () => has('setup_skip') || has('home_screen'),
    'Einrichtung oder Heute',
  );
  if (has('setup_skip')) {
    await tapKey(t, 'setup_skip');
  }
  // Am Schluessel der Seite: „Lauf starten“ kann unter einer hohen Karte
  // ausserhalb des gebauten Bereichs der Liste liegen.
  await waitFor(t, () => has('home_screen'), 'Heute');
}

/// Tipp auf den obersten Zurueck-Knopf: wartet vorher, bis er im Baum steht
/// und getroffen wird (Seitenwechsel), merkt ihn sich und wartet danach, bis
/// genau dieser Knopf nicht mehr im Baum steht (Seite zu, Uebergang beendet);
/// sonst `Zurück ohne Wirkung`. Keine feste Pause.
Future<void> back(WidgetTester t) async {
  final f = find.byType(BackButton);
  await _waitPresent(t, f, 'Zurück-Knopf fehlt');
  final end = DateTime.now().add(_tapFrist);
  while (!hittable(t, f.last)) {
    if (DateTime.now().isAfter(end)) fail('Tipp trifft Zurück nicht');
    await pumpFor(t, const Duration(milliseconds: 100));
  }
  final ziel = f.last.evaluate().first;
  await t.tap(f.last);
  await _waitGone(t, () => !ziel.mounted, 'back', 'Zurück ohne Wirkung');
}

/// Verbindet Fake-Geraete ueber die Sensorseite.
Future<void> connect(WidgetTester t, List<String> ids, String prefer) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_sensors');
  await tapKey(t, 'sensors_scan');
  await waitFor(t, () => has('sensor_${ids.first}'), 'Fake-Geraet gefunden');
  for (final id in ids) {
    await tapKey(t, 'sensor_connect_$id');
    await waitFor(t, () => has('sensor_bpm_$id'), 'Pulswert von $id');
  }
  if (ids.length > 1) await tapKey(t, 'sensor_prefer_$prefer');
  await back(t);
  await back(t);
}

/// Erste Frist fuer „GPS gut“ (start_gps_good) nach dem Oeffnen der
/// Start-Seite; danach oeffnet [startRun] die Seite einmal neu.
const gpsErsteFrist = Duration(seconds: 30);

/// Zweite Frist nach dem Neuoeffnen. Gesamt [gpsErsteFrist] + diese = 90 s,
/// innerhalb des Zeitlimits jeder Stufe mit Laufstart (grenze_s in
/// tool/ci_e2e.sh, mindestens 300 s).
const gpsZweiteFrist = Duration(seconds: 60);

/// Bekannte Schluessel der Start-Seite zu Sperre und GPS-Zustand
/// (run_flow_screen.dart): laufende Startpruefung („Pruefe …“), Sperrtexte,
/// ihre Tasten und die GPS-Anzeige.
final startPageKeys = <String>[
  'run_checking',
  for (final b in StartBlock.values) 'run_block_${b.name}',
  'run_block_ask',
  'run_block_location_settings',
  'run_block_settings',
  'run_block_recheck',
  'start_gps_good',
  'start_gps_searching',
  'start_gps_blocked',
];

/// Die davon gerade sichtbaren (im Baum), in fester Reihenfolge; nur
/// Schluesselnamen, keine Werte.
List<String> visibleStartKeys() => [
  for (final k in startPageKeys)
    if (has(k)) k,
];

/// Oeffnet die Start-Seite von Heute aus und waehlt die Laufart GPS.
Future<void> _openStartPage(WidgetTester t) async {
  await tapKey(t, 'home_start_run');
  await waitFor(
    t,
    () => has('run_start_ready') || has('treadmill_mode'),
    'Start-Seite',
  );
  // Die Laufart bleibt gespeichert (FR-0196); nach einem Laufband-Lauf
  // frueherer Gruppen der Sammlung steht sie auf Band: GPS waehlen.
  bool gps() =>
      maybeWidget<SegmentedButton<RunMode>>(
        find.byKey(const Key('treadmill_mode')),
      )?.selected.contains(RunMode.gps) ??
      true;
  if (!gps()) {
    await tapUntil(
      t,
      find.byKey(const Key('treadmill_mode_gps')),
      gps,
      'Laufart GPS',
    );
  }
  await waitFor(t, () => has('run_start_ready'), 'Start-Seite bereit');
}

/// Wartet bis [frist] auf start_gps_good; tippt dabei „Erneut pruefen“, wenn
/// sichtbar. Ergebnis: erreicht.
Future<bool> _gpsGoodWithin(WidgetTester t, Duration frist) async {
  final end = DateTime.now().add(frist);
  while (!has('start_gps_good')) {
    if (DateTime.now().isAfter(end)) return false;
    if (has('run_block_recheck')) {
      await tapKey(t, 'run_block_recheck');
    }
    await pumpFor(t, const Duration(seconds: 1));
  }
  return true;
}

/// Wartet auf der offenen Start-Seite auf „GPS gut“. Nach [erste] ohne Erfolg
/// verlaesst sie die Seite einmal (Zurueck) und oeffnet sie neu, damit die
/// Seite den Standortstrom neu abonniert; danach bis [zweite]. Scheitert auch
/// das, nennt die Meldung, ob die Startpruefung noch laeuft (run_checking),
/// und die sichtbaren Schluessel aus [startPageKeys] (Recht, Sperre, Suche),
/// nie Standortwerte.
Future<void> _waitGpsGood(
  WidgetTester t,
  Duration erste,
  Duration zweite,
) async {
  if (await _gpsGoodWithin(t, erste)) return;
  logPub('gps_neu_oeffnen sichtbar=${visibleStartKeys().join(',')}');
  await back(t);
  await _openStartPage(t);
  if (await _gpsGoodWithin(t, zweite)) return;
  final sichtbar = visibleStartKeys();
  final pruefung = sichtbar.contains('run_checking') ? 'laeuft' : 'fertig';
  fail(
    'GPS gut nicht erreicht (Emulator-Fix); Startpruefung $pruefung; '
    'sichtbar: ${sichtbar.isEmpty ? 'keiner' : sichtbar.join(', ')}',
  );
}

/// Startet von Heute aus einen GPS-Lauf: Start-Seite, Warten auf „GPS gut“
/// (Fristen [gpsErste] und [gpsZweite], siehe [_waitGpsGood]; kuerzer nur im
/// Selbsttest test/e2e_gps_wait_test.dart), dann Start bis zur Laufseite.
Future<void> startRun(
  WidgetTester t, {
  Duration gpsErste = gpsErsteFrist,
  Duration gpsZweite = gpsZweiteFrist,
}) async {
  await _openStartPage(t);
  // Das Recht setzt tool/ci_e2e.sh von aussen (pm grant) kurz nach dem
  // Installieren; die Start-Seite prueft es beim Oeffnen. Kam der Grant
  // spaeter, laesst "Erneut pruefen" (run_block_recheck) die App ihn sehen.
  await _waitGpsGood(t, gpsErste, gpsZweite);
  await tapKey(t, 'run_start_ready');
  await waitFor(t, () => has('run_time'), 'Laufseite');
}

Future<void> _noConsent(WidgetTester t) async {
  if (has('map_consent_dialog')) {
    await tapDialog(t, 'map_consent_not_now');
  }
}

Future<void> finishRun(WidgetTester t) async {
  // Auf der Lauf-Seite fragt die Karte waehrend des Laufs nicht (kein Dialog vor Pause, Beenden, Bestaetigen).
  await tapKey(t, 'run_pause');
  await tapKey(t, 'run_finish');
  await waitFor(t, () => has('run_finish_confirm'), 'Beenden-Dialog');
  await tapDialog(t, 'run_finish_confirm');
  await waitFor(t, () => has('run_done_status'), 'Laufende angezeigt');
}

/// Zaehler eines gespeicherten Laufs (keine Werte).
class RunCounts {
  RunCounts(
    this.state,
    this.positions,
    this.heartRates,
    this.rrPackets,
    this.canary,
  );
  final RunState state;
  final int positions;
  final int heartRates;
  final int rrPackets;
  final int canary;
}

/// Zaehler aller Laeufe, neueste zuerst nach Id.
Future<List<RunCounts>> countRuns(WidgetTester t, World w) async {
  final s = await session(t, w);
  return (await t.runAsync(() async {
    final out = <RunCounts>[];
    final runs = [...await s.runs.list()]..sort((a, b) => b.id.compareTo(a.id));
    for (final r in runs) {
      final raw = await s.rawData.read(r.id);
      var canary = 0;
      for (final p in raw.rrPackets) {
        canary += p.value.intervals.where((v) => v == canaryRr).length;
      }
      out.add(
        RunCounts(
          r.state,
          raw.positions.length,
          raw.heartRates.length,
          raw.rrPackets.length,
          canary,
        ),
      );
    }
    return out;
  }))!;
}

/// Wie [countRuns], wartet aber (echte Zeit), bis der neueste Lauf als beendet
/// gespeichert ist: Das Laufende-Bild erscheint vor dem Schreiben in die
/// Datenbank.
Future<List<RunCounts>> countRunsFinished(WidgetTester t, World w) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    final runs = await countRuns(t, w);
    if (runs.isNotEmpty && runs.first.state == RunState.finished) return runs;
    if (DateTime.now().isAfter(end)) return runs;
    await pumpFor(t, const Duration(milliseconds: 500));
  }
}
