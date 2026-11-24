// E2E: Ruhepuls mit der Kamera messen (FR-0213, WP27) ueber die Fake-Kamera
// (DebugTestPpgCamera wie in main_debug.dart, Zeitraffer 30: 60 s Messung in
// ca. 2 s). Die Kamera-Berechtigung des Systems ist durch die Fake-Kamera
// ersetzt; im Messablauf gibt es keine Einwilligung (nur die Karte kennt eine,
// MapConsent), die App fragt nur das Kamera-Recht ueber den Kamera-Port.
// Szenario guter Puls: Ergebnis uebernehmen -> Ruhepuls im gespeicherten
// Profil. Szenario noFinger: kein Wert, nichts gespeichert. Kamerawahl
// (FR-0220): Entwicklermodus an, auf Ueber die zweite Debug-Kamera waehlen;
// die Standardkamera spielt schwaches Signal, die zweite guten Puls, also
// belegt ein Ergebnis die zweite Kamera. Kamerasuche (FR-0220, PAR-228):
// in den Entwicklereinstellungen "Kamera suchen"; die Standardkamera zeigt
// keinen Finger, die zweite den Finger, also ist die zweite empfohlen;
// "Uebernehmen" speichert sie als Suchergebnis, und eine Messung ohne
// Entwicklermodus startet sie. Synthetische Werte,
// Ausgabe nur Zaehler. Laeuft in der Sammlung (all_test.dart).
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/camera_finder_screen.dart';

import 'support/e2e_support.dart';

Future<void> _openMeasure(WidgetTester t, World w) async {
  await startApp(t, w);
  await setupIfShown(t);
  await tapKey(t, 'home_overview');
  await tapKey(t, 'home_profile');
  await waitFor(t, () => has('profile_resting_measure'), 'Profil mit Messung');
  await tapKey(t, 'profile_resting_measure');
  await waitFor(t, () => has('measure_start'), 'Messung bereit');
  await tapKey(t, 'measure_mode_now');
  await tapKey(t, 'measure_start');
}

/// Entwicklermodus ueber zehn Tipps auf die Version (falls noch aus) und die
/// Entwicklereinstellungen oeffnen.
Future<void> _openDeveloperSettings(WidgetTester t) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_about');
  await waitFor(t, () => has('about_version'), 'Ueber');
  if (!has('about_dev_badge')) {
    for (var i = 0; i < 10; i++) {
      await t.tap(find.byKey(const Key('about_version')));
      await pumpFor(t, const Duration(milliseconds: 120));
    }
  }
  await waitFor(t, () => has('about_dev_badge'), 'Entwicklermodus an');
  await back(t); // Ueber -> Uebersicht
  await waitFor(t, () => has('overview_developer'), 'Eintrag Entwickler');
  await tapKey(t, 'overview_developer');
}

/// In den Entwicklereinstellungen die Kamera [camera] waehlen; danach zurueck
/// zur Uebersicht.
Future<void> _chooseCamera(WidgetTester t, String camera) async {
  await _openDeveloperSettings(t);
  await waitFor(
    t,
    () => has('about_ppg_camera_$camera'),
    'Kamera $camera in den Entwicklereinstellungen',
  );
  await tapKey(t, 'about_ppg_camera_$camera');
  // Die Auswahl zeigt sich erst, wenn sie gespeichert ist.
  await waitFor(
    t,
    () => find
        .byWidgetPredicate(
          (w) => w is RadioGroup<String> && w.groupValue == camera,
        )
        .evaluate()
        .isNotEmpty,
    'Kamera gewaehlt (about_ppg_camera_$camera)',
  );
  await back(t);
}

Future<int?> _resting(WidgetTester t, StorageSession s) async =>
    (await t.runAsync(() => s.profile.read()))!.restingHeartRateBpm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guter Puls: Ergebnis uebernehmen speichert den Ruhepuls', (
    t,
  ) async {
    step('RESTING_GUT start');
    final cam = DebugTestPpgCamera(speed: 30);
    final w = buildWorld(camera: cam);
    await _openMeasure(t, w);
    final s = await session(t, w);
    step('RESTING_GUT messung');
    // Ausgangswert ist ein anderer als das Ergebnis (sonst waere "gespeichert" nicht belegt).
    final prior = await _resting(t, s);
    expect(
      prior == null || prior < 60 || prior > 80,
      isTrue,
      reason: 'Ausgangswert liegt ausserhalb des erwarteten Ergebnisses',
    );
    await waitFor(
      t,
      () => has('measure_adopt') || has('measure_retry'),
      'Ergebnis der Messung',
      timeout: const Duration(seconds: 60),
    );
    expect(
      has('measure_adopt'),
      isTrue,
      reason: 'guter Puls liefert einen Wert',
    );
    expect(has('measure_result_bpm'), isTrue);
    expect(
      await _resting(t, s),
      prior,
      reason: 'vor Uebernahme nichts gespeichert',
    );
    step('RESTING_GUT uebernehmen');
    await tapKey(t, 'measure_adopt');
    await waitFor(t, () => !has('measure_start'), 'Messung geschlossen');
    // Das Speichern laeuft ueber echte Ein-/Ausgabe: warten, bis es ankommt.
    step('RESTING_GUT gespeichert_pruefen');
    final end = DateTime.now().add(const Duration(seconds: 30));
    var saved = await _resting(t, s);
    while (saved == prior && DateTime.now().isBefore(end)) {
      await pumpFor(t, const Duration(milliseconds: 300));
      saved = await _resting(t, s);
    }
    log('RESTING saved=${saved != null}');
    expect(saved, isNotNull);
    // Die Fake-Kamera spielt ca. 70/min ein (Schlag alle 0,85 s).
    expect(saved!, inInclusiveRange(60, 80));
    expect(cam.torchOn, isFalse, reason: 'Kamera wieder frei');
    // Die Rueckmeldung (SnackBar) muss ablaufen, bevor der Baum abgebaut wird:
    // sonst loest ihr Zeitgeber nach dem Test aus (Scaffold nicht mehr eingebunden).
    await waitFor(
      t,
      () => find.byType(SnackBar).evaluate().isEmpty,
      'Rueckmeldung abgelaufen',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('kein Finger: kein Wert, nichts gespeichert', (t) async {
    step('RESTING_KEIN_FINGER start');
    final cam = DebugTestPpgCamera(
      speed: 30,
      scenario: DebugPpgScenario.noFinger,
    );
    final w = buildWorld(camera: cam);
    await _openMeasure(t, w);
    final s = await session(t, w);
    final prior = await _resting(t, s);
    await waitFor(
      t,
      () => has('measure_reason') || has('measure_adopt'),
      'Ergebnis der Messung',
      timeout: const Duration(seconds: 60),
    );
    expect(has('measure_adopt'), isFalse, reason: 'ohne Finger kein Wert');
    expect(has('measure_manual'), isTrue, reason: 'Eingabe von Hand angeboten');
    step('RESTING_KEIN_FINGER von_hand');
    await tapKey(t, 'measure_manual');
    await waitFor(t, () => !has('measure_start'), 'Messung geschlossen');
    expect(await _resting(t, s), prior, reason: 'nichts uebernommen');
    expect(cam.torchOn, isFalse, reason: 'Kamera wieder frei');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('Kamerawahl: zweite Kamera auf Ueber gewaehlt, Messung mit ihr', (
    t,
  ) async {
    final cam = DebugTestPpgCamera(
      speed: 30,
      scenario: DebugPpgScenario.weakSignal,
    );
    step('RESTING_KAMERAWAHL start');
    const second = PpgCameraRef('0', '2');
    expect(cam.scenarioOf(second), DebugPpgScenario.goodPulse);
    final w = buildWorld(camera: cam);
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    final choice = SettingsPpgCameraChoiceStore(s.settings, w.deps.clock);
    final mode = SettingsDeveloperModeStore(s.settings, w.deps.clock);
    final wasOn = await t.runAsync(mode.read);
    try {
      step('RESTING_KAMERAWAHL kamera_waehlen');
      await _chooseCamera(t, '0/2');
      expect(await t.runAsync(choice.readManual), second);
      step('RESTING_KAMERAWAHL messung');
      await tapKey(t, 'home_profile');
      await waitFor(
        t,
        () => has('profile_resting_measure'),
        'Profil mit Messung',
      );
      await tapKey(t, 'profile_resting_measure');
      await waitFor(t, () => has('measure_start'), 'Messung bereit');
      await tapKey(t, 'measure_mode_now');
      await tapKey(t, 'measure_start');
      await waitFor(
        t,
        () =>
            has('measure_adopt') ||
            has('measure_retry') ||
            has('measure_reason'),
        'Ergebnis der Messung',
        timeout: const Duration(seconds: 60),
      );
      log('RESTING camera started=${cam.startedCameras.length}');
      expect(cam.startedCameras, [second], reason: 'nur die gewaehlte Kamera');
      expect(
        has('measure_adopt'),
        isTrue,
        reason: 'zweite Kamera (guter Puls) liefert einen Wert',
      );
      step('RESTING_KAMERAWAHL verwerfen');
      await tapKey(t, 'measure_discard');
      await waitFor(t, () => !has('measure_start'), 'Messung geschlossen');
      expect(cam.torchOn, isFalse, reason: 'Kamera wieder frei');
    } finally {
      // Die Sammlung teilt den Speicher: Wahl und Modus zuruecksetzen.
      await t.runAsync(() async {
        await choice.setManual(null);
        await mode.set(wasOn ?? false);
      });
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
    'Kamerasuche: zweite Kamera empfohlen, uebernommen, Messung mit ihr',
    (t) async {
      // Standardkamera ohne Finger (grau, kein Wert), zweite mit Finger und
      // gutem Puls: nur die zweite kann empfohlen sein und einen Wert liefern.
      final cam = DebugTestPpgCamera(
        speed: 30,
        scenario: DebugPpgScenario.noFinger,
      );
      step('RESTING_KAMERASUCHE start');
      const second = PpgCameraRef('0', '2');
      expect(cam.scenarioOf(second), DebugPpgScenario.goodPulse);
      final w = buildWorld(camera: cam);
      await startApp(t, w);
      await setupIfShown(t);
      final s = await session(t, w);
      final choice = SettingsPpgCameraChoiceStore(s.settings, w.deps.clock);
      final mode = SettingsDeveloperModeStore(s.settings, w.deps.clock);
      final wasOn = await t.runAsync(mode.read);
      try {
        step('RESTING_KAMERASUCHE suchen');
        await _openDeveloperSettings(t);
        await tapKey(t, 'about_ppg_camera_find');
        await waitFor(
          t,
          () => find
              .byKey(CameraFinderScreen.recommendedKey(second))
              .evaluate()
              .isNotEmpty,
          'zweite Kamera empfohlen',
          timeout: const Duration(seconds: 30),
        );
        expect(
          find
              .byKey(CameraFinderScreen.recommendedKey(const PpgCameraRef('0')))
              .evaluate(),
          isEmpty,
          reason: 'Standardkamera ohne Finger nicht empfohlen',
        );
        expect(cam.previewOn, isTrue, reason: 'Vorschau laeuft');
        step('RESTING_KAMERASUCHE uebernehmen');
        await tapKey(t, 'camera_finder_apply');
        await waitFor(
          t,
          () => !has('camera_finder_apply') && has('about_ppg_camera_find'),
          'zurueck in den Entwicklereinstellungen',
        );
        expect(cam.previewOn, isFalse, reason: 'Vorschau gestoppt');
        expect(cam.torchOn, isFalse, reason: 'Taschenlampe aus');
        expect(await t.runAsync(choice.readAuto), second);
        expect(
          await t.runAsync(choice.readManual),
          isNull,
          reason: 'Uebernehmen setzt keine feste Wahl',
        );
        step('RESTING_KAMERASUCHE entwicklermodus_aus');
        await t.runAsync(() => mode.set(false));
        await back(t); // Entwicklereinstellungen -> Uebersicht
        step('RESTING_KAMERASUCHE messung');
        await tapKey(t, 'home_profile');
        await waitFor(
          t,
          () => has('profile_resting_measure'),
          'Profil mit Messung',
        );
        await tapKey(t, 'profile_resting_measure');
        await waitFor(t, () => has('measure_start'), 'Messung bereit');
        await tapKey(t, 'measure_mode_now');
        await tapKey(t, 'measure_start');
        await waitFor(
          t,
          () =>
              has('measure_adopt') ||
              has('measure_retry') ||
              has('measure_reason'),
          'Ergebnis der Messung',
          timeout: const Duration(seconds: 60),
        );
        log('RESTING camera started=${cam.startedCameras.length}');
        expect(cam.startedCameras, [
          second,
        ], reason: 'Suchergebnis gilt ohne Entwicklermodus');
        expect(
          has('measure_adopt'),
          isTrue,
          reason: 'zweite Kamera (guter Puls) liefert einen Wert',
        );
        step('RESTING_KAMERASUCHE verwerfen');
        await tapKey(t, 'measure_discard');
        await waitFor(t, () => !has('measure_start'), 'Messung geschlossen');
        expect(cam.torchOn, isFalse, reason: 'Kamera wieder frei');
      } finally {
        // Die Sammlung teilt den Speicher: Wahl und Modus zuruecksetzen.
        await t.runAsync(() async {
          await choice.setAuto(null);
          await choice.setManual(null);
          await mode.set(wasOn ?? false);
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
