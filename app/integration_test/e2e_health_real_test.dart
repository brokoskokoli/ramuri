// E2E (lokal, nicht fuer all_test): echter Adapter ohne Debug-Quelle, echter Berechtigungsdialog von Health Connect.
// --dart-define=HC_MODE=cancel|grant. Der Host (adb) beantwortet den Systemdialog, Marker "SHOT <name>".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/system_clock.dart';
import 'package:core/core.dart';
import 'package:running_app/features/storage/storage_start.dart';

import 'support/e2e_support.dart';

const _mode = String.fromEnvironment('HC_MODE', defaultValue: 'cancel');

Future<void> shot(WidgetTester t, String name) async {
  log('SHOT $name');
  await pumpFor(t, const Duration(milliseconds: 2500));
}

bool _on(String kind) =>
    (find.byKey(Key('health_switch_$kind')).evaluate().first.widget
            as SwitchListTile)
        .value;

String _states() => HealthDataKind.values
    .map((k) => '${k.key}=${_on(k.key) ? 1 : 0}')
    .join(' ');

bool _missingText() =>
    find.textContaining('noch nicht alles freigegeben').evaluate().isNotEmpty ||
    find.textContaining('not everything').evaluate().isNotEmpty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('A echter Dialog $_mode', (t) async {
    final d = AppDependencies.create(
      heartRateSensor: DebugTestSensor(const SystemClock()),
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(RunningApp(dependencies: d));
    await pumpFor(t, const Duration(seconds: 3));
    await setupIfShown(t);
    await waitFor(t, () => d.storageStart.state is StorageReady, 'Speicher');
    final s = (d.storageStart.state as StorageReady).session as HealthStorage;
    await tapKey(t, 'home_overview');
    await tapKey(t, 'home_settings');
    await t.scrollUntilVisible(
      find.byKey(const Key('settings_health')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFor(t, const Duration(milliseconds: 300));
    await tapKey(t, 'settings_health');
    await waitFor(t, () => has('health_main'), 'Health-Seite');
    log('HCA Start Schalter ${_states()}');
    if (!_on('sleep')) await tapKey(t, 'health_switch_sleep');
    if (!_on('resting_heart_rate')) {
      await tapKey(t, 'health_switch_resting_heart_rate');
    }
    log('HCA vor Dialog Schalter ${_states()} fehlt-Text=${_missingText()}');
    await shot(t, 'before_dialog');
    final seen = <AppLifecycleState>[];
    final obs = _Obs(seen);
    WidgetsBinding.instance.addObserver(obs);
    await tapKey(t, 'health_continue');
    log('SHOT dialog');
    // Bis der Dialog (eigene Activity) kam und die App wieder im Vordergrund ist, hoechstens 150 s.
    for (var i = 0; i < 300; i++) {
      await pumpFor(t, const Duration(milliseconds: 500));
      if (seen.contains(AppLifecycleState.paused) &&
          seen.last == AppLifecycleState.resumed) {
        break;
      }
    }
    await pumpFor(t, const Duration(seconds: 2));
    WidgetsBinding.instance.removeObserver(obs);
    log('HCA Lebenszyklus ${seen.map((e) => e.name).toList()}');
    log('HCA nach Dialog Schalter ${_states()} fehlt-Text=${_missingText()}');
    expect(has('health_main'), isTrue);
    expect(find.byType(ErrorWidget), findsNothing);
    await shot(t, 'after_dialog');
    await tapKey(t, 'health_fetch');
    await pumpFor(t, const Duration(seconds: 4));
    final counts = (await t.runAsync(
      () async => {
        for (final k in HealthDataKind.values) k.key: await s.health.count(k),
      },
    ))!;
    log(
      'HCA nach Abruf Zaehler $counts last=${txt('health_last').isEmpty ? 'leer' : 'gesetzt'}',
    );
    expect(has('health_main'), isTrue);
    expect(find.byType(ErrorWidget), findsNothing);
    await shot(t, 'after_fetch');
    log('HCA Ende');
  });
}

class _Obs with WidgetsBindingObserver {
  _Obs(this.seen);
  final List<AppLifecycleState> seen;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => seen.add(state);
}
