// E2E: Laufband-Lauf (FR-0196): Bandmodus waehlen, Start-Werte eingeben,
// laufen, Geschwindigkeit ueber den Knopf aendern, pausieren, beenden. Geprueft
// wird der gespeicherte Zustand: ein neuer, beendeter Lauf im Bandmodus mit den
// eingegebenen Bandwerten und ohne GPS-Positionen. Kein GPS noetig. Synthetische
// Werte, Ausgabe nur Zaehler. Laeuft in der Sammlung (all_test.dart).
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/ui/ui.dart';

import 'support/e2e_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Laufband-Lauf starten, Werte eingeben, speichern', (t) async {
    final w = buildWorld();
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    final before = (await t.runAsync(() => s.runs.list()))!.length;

    await tapKey(t, 'home_start_run');
    await waitFor(t, () => has('treadmill_mode_belt'), 'Bandwahl');
    await tapKey(t, 'treadmill_mode_belt');
    await waitFor(t, () => has('treadmill_start_speed'), 'Geschwindigkeit');
    // Ohne Geschwindigkeit ist Los gesperrt.
    expect(t.widget<RamuriStartButton>(_goFinder).onPressed, isNull);
    await t.enterText(find.byKey(const Key('treadmill_start_speed')), '10.5');
    await t.enterText(find.byKey(const Key('treadmill_start_incline')), '1.5');
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpFor(t, const Duration(milliseconds: 300));
    await tapKey(t, 'run_start_ready');
    await waitFor(
      t,
      () => has('run_time') || has('treadmill_denied'),
      'Laufseite oder Rechtehinweis',
    );
    expect(has('treadmill_denied'), isFalse, reason: 'Bewegungsrecht fehlt');
    expect(has('treadmill_speed'), isTrue);
    // Anzeige je nach Sprache mit Komma oder Punkt; der Wert gilt im Speicher.
    await waitFor(t, () => _shows('10', '5'), 'Startgeschwindigkeit angezeigt');

    await pumpFor(t, const Duration(seconds: 3));
    await tapKey(t, 'treadmill_speed_up');
    await waitFor(t, () => _shows('10', '6'), 'Geschwindigkeit nach Knopf');
    await pumpFor(t, const Duration(seconds: 3));
    await tapKey(t, 'run_pause');
    await waitFor(t, () => has('run_finish'), 'Pause (Beenden sichtbar)');
    await tapKey(t, 'run_finish');
    await tapDialog(t, 'run_finish_confirm');
    await waitFor(t, () => has('run_done_status'), 'Laufende angezeigt');

    final runs = (await t.runAsync(() => s.runs.list()))!;
    final done = await _newestFinished(t, s);
    expect(runs.length, before + 1, reason: 'genau ein neuer Lauf');
    expect(done.mode, RunMode.treadmill);
    final raw = (await t.runAsync(() => s.rawData.read(done.id)))!;
    log(
      'TREADMILL belt=${raw.beltSettings.length} pos=${raw.positions.length}',
    );
    expect(raw.positions, isEmpty, reason: 'Bandlauf ohne GPS-Positionen');
    final speeds = [
      for (final b in raw.beltSettings) b.value.speedMetersPerSecond,
    ];
    expect(
      speeds.length,
      greaterThanOrEqualTo(2),
      reason: 'Start und Aenderung',
    );
    expect(speeds.first, closeTo(10.5 / 3.6, 1e-6), reason: 'Startwert');
    expect(speeds.last, closeTo(10.6 / 3.6, 1e-6), reason: 'nach Knopf');
    expect(raw.beltSettings.first.value.inclinePercent, 1.5);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

bool _shows(String whole, String tenth) =>
    RegExp('^$whole[.,]$tenth').hasMatch(txt('treadmill_speed'));

final _goFinder = find.byKey(const Key('run_start_ready'));

/// Neuester Lauf, wartet (echte Zeit), bis er als beendet gespeichert ist.
Future<StoredRun> _newestFinished(WidgetTester t, StorageSession s) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    final runs = [...(await t.runAsync(() => s.runs.list()))!]
      ..sort((a, b) => b.id.compareTo(a.id));
    if (runs.isNotEmpty && runs.first.state == RunState.finished) {
      return runs.first;
    }
    if (DateTime.now().isAfter(end)) fail('Lauf nicht als beendet gespeichert');
    await pumpFor(t, const Duration(milliseconds: 500));
  }
}
