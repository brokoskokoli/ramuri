// E2E (lokal): Loeschfrage beim Oeffnen von Heute, wenn ein Health-Connect-Recht fehlt (SEC-0007).
// Teil 1 Debug-Quelle: Schlaf einwilligen und importieren (synthetisch). Danach echter Adapter: der Host
// erteilt/entzieht das Recht (pm grant/revoke), "HOSTACT <aktion>" ist der Marker.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_health_connect.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/features/storage/storage_start.dart';
import 'package:running_app/system_clock.dart';

import 'support/e2e_support.dart';

Future<void> shot(WidgetTester t, String name) async {
  log('SHOT $name');
  await pumpFor(t, const Duration(milliseconds: 2500));
}

Future<void> hostAct(WidgetTester t, String a) async {
  log('HOSTACT $a');
  await pumpFor(t, const Duration(seconds: 6));
}

Future<void> restart(WidgetTester t, AppDependencies d) async {
  await t.pumpWidget(const SizedBox());
  await pumpFor(t, const Duration(milliseconds: 500));
  await t.pumpWidget(RunningApp(dependencies: d));
  await pumpFor(t, const Duration(seconds: 4));
  await setupIfShown(t);
}

Future<int> count(WidgetTester t, AppDependencies d, HealthDataKind k) async {
  await waitFor(t, () => d.storageStart.state is StorageReady, 'Speicher');
  final s = (d.storageStart.state as StorageReady).session as HealthStorage;
  return (await t.runAsync(() => s.health.count(k)))!;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('HC_PHASE', defaultValue: '1');
  const answer = String.fromEnvironment('HC_ANSWER', defaultValue: 'delete');
  AppDependencies real() => AppDependencies.create(
    heartRateSensor: DebugTestSensor(const SystemClock()),
  );
  if (phase == '1') {
    testWidgets('D1 Debug-Quelle: Schlaf einwilligen und importieren', (
      t,
    ) async {
      final debug = AppDependencies.create(
        heartRateSensor: DebugTestSensor(const SystemClock()),
        healthConnect: DebugTestHealthConnect(
          now: () => const SystemClock().now(),
        ),
      );
      await restart(t, debug);
      await tapKey(t, 'home_overview');
      await tapKey(t, 'home_settings');
      await t.scrollUntilVisible(
        find.byKey(const Key('settings_health')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tapKey(t, 'settings_health');
      await waitFor(t, () => has('health_main'), 'Health-Seite');
      await tapKey(t, 'health_switch_sleep');
      await tapKey(t, 'health_continue');
      await pumpFor(t, const Duration(milliseconds: 500));
      await tapKey(t, 'health_fetch');
      await waitFor(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        'Rueckmeldung',
      );
      final n0 = await count(t, debug, HealthDataKind.sleep);
      log('HCD1 Schlaf gespeichert (Debug-Quelle): $n0');
      expect(n0, greaterThan(0));
    });
  }
  if (phase == '2') {
    testWidgets('D2 echter Adapter, Recht erteilt: keine Frage', (t) async {
      final d = real();
      await restart(t, d);
      await waitFor(t, () => has('home_start_run'), 'Heute');
      final n = await count(t, d, HealthDataKind.sleep);
      log(
        'HCD2 erteilt: Frage sichtbar=${has('health_delete_dialog')} Schlaf=$n',
      );
      expect(n, greaterThan(0), reason: 'Daten blieben ueber den Neustart');
      expect(has('health_delete_dialog'), isFalse);
      await shot(t, 'd2_today_granted');
    });
  }
  if (phase == '3') {
    testWidgets('D3 Recht entzogen: Frage beim Oeffnen von Heute', (t) async {
      final d = real();
      await restart(t, d);
      await waitFor(t, () => has('health_delete_dialog'), 'Loeschfrage');
      final n = await count(t, d, HealthDataKind.sleep);
      log('HCD3 entzogen: Frage sichtbar=true Schlaf=$n');
      await shot(t, 'd3_question');
      if (answer == 'keep') {
        await tapDialog(t, 'health_delete_keep');
        await waitFor(t, () => !has('health_delete_dialog'), 'Dialog zu');
        final k = await count(t, d, HealthDataKind.sleep);
        log('HCD3 Behalten: Schlaf=$k');
        expect(k, n);
        final d2 = real();
        await restart(t, d2);
        await pumpFor(t, const Duration(seconds: 3));
        log(
          'HCD3 Neustart nach Behalten: Frage=${has('health_delete_dialog')} Schlaf=${await count(t, d2, HealthDataKind.sleep)}',
        );
        expect(has('health_delete_dialog'), isFalse);
      } else {
        // Abbrechen laesst die Frage offen; beim naechsten Oeffnen kommt sie wieder; dann Loeschen.
        await tapDialog(t, 'health_delete_cancel');
        await waitFor(t, () => !has('health_delete_dialog'), 'Dialog zu');
        log(
          'HCD3 Abbrechen: Schlaf=${await count(t, d, HealthDataKind.sleep)}',
        );
        final d2 = real();
        await restart(t, d2);
        await waitFor(
          t,
          () => has('health_delete_dialog'),
          'Loeschfrage erneut',
        );
        log('HCD3 beim naechsten Oeffnen wieder gefragt');
        await tapDialog(t, 'health_delete_confirm');
        await waitFor(t, () => !has('health_delete_dialog'), 'Dialog zu 2');
        await pumpFor(t, const Duration(seconds: 1));
        final z = await count(t, d2, HealthDataKind.sleep);
        log('HCD3 Loeschen: Schlaf=$z');
        expect(z, 0);
      }
    });
  }
  if (phase == 'B') {
    testWidgets(
      'B Debug-Quelle: Ruhepuls, HRV, VO2max, Schlaf landen im Speicher',
      (t) async {
        final debug = AppDependencies.create(
          heartRateSensor: DebugTestSensor(const SystemClock()),
          healthConnect: DebugTestHealthConnect(
            now: () => const SystemClock().now(),
          ),
        );
        await restart(t, debug);
        await tapKey(t, 'home_overview');
        await tapKey(t, 'home_settings');
        await t.scrollUntilVisible(
          find.byKey(const Key('settings_health')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tapKey(t, 'settings_health');
        await waitFor(t, () => has('health_main'), 'Health-Seite');
        const kinds = ['resting_heart_rate', 'hrv_rmssd', 'vo2_max', 'sleep'];
        for (final k in kinds) {
          final on =
              (find.byKey(Key('health_switch_$k')).evaluate().first.widget
                      as SwitchListTile)
                  .value;
          if (!on) await tapKey(t, 'health_switch_$k');
        }
        await tapKey(t, 'health_continue');
        await pumpFor(t, const Duration(milliseconds: 500));
        await tapKey(t, 'health_fetch');
        await waitFor(
          t,
          () => find.byType(SnackBar).evaluate().isNotEmpty,
          'Rueckmeldung',
        );
        await shot(t, 'b_after_fetch');
        for (final k in [
          HealthDataKind.restingHeartRate,
          HealthDataKind.hrvRmssd,
          HealthDataKind.vo2Max,
          HealthDataKind.sleep,
        ]) {
          final n = await count(t, debug, k);
          log('HCB ${k.key} gespeichert=$n');
          expect(n, greaterThan(0), reason: k.key);
        }
        final ex = await count(t, debug, HealthDataKind.exercise);
        log('HCB exercise (nicht eingewilligt)=$ex');
      },
    );
  }
}
