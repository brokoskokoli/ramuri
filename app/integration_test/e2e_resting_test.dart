// E2E: Ruhepuls mit der Kamera messen (FR-0213, WP27) ueber die Fake-Kamera
// (DebugTestPpgCamera wie in main_debug.dart, Zeitraffer 30: 60 s Messung in
// ca. 2 s). Die Kamera-Berechtigung des Systems ist durch die Fake-Kamera
// ersetzt; im Messablauf gibt es keine Einwilligung (nur die Karte kennt eine,
// MapConsent), die App fragt nur das Kamera-Recht ueber den Kamera-Port.
// Szenario guter Puls: Ergebnis uebernehmen -> Ruhepuls im gespeicherten
// Profil. Szenario noFinger: kein Wert, nichts gespeichert. Synthetische Werte,
// Ausgabe nur Zaehler. Laeuft in der Sammlung (all_test.dart).
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';

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

Future<int?> _resting(WidgetTester t, StorageSession s) async =>
    (await t.runAsync(() => s.profile.read()))!.restingHeartRateBpm;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guter Puls: Ergebnis uebernehmen speichert den Ruhepuls', (
    t,
  ) async {
    final cam = DebugTestPpgCamera(speed: 30);
    final w = buildWorld(camera: cam);
    await _openMeasure(t, w);
    final s = await session(t, w);
    // Ausgangswert ist ein anderer als das Ergebnis (sonst waere "gespeichert" nicht belegt).
    final prior = await _resting(t, s);
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
    await tapKey(t, 'measure_adopt');
    await waitFor(t, () => !has('measure_start'), 'Messung geschlossen');
    // Das Speichern laeuft ueber echte Ein-/Ausgabe: warten, bis es ankommt.
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
    await tapKey(t, 'measure_manual');
    await waitFor(t, () => !has('measure_start'), 'Messung geschlossen');
    expect(await _resting(t, s), prior, reason: 'nichts uebernommen');
    expect(cam.torchOn, isFalse, reason: 'Kamera wieder frei');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
