// E2E: Wiederanlauf nach Prozessende, zwei Stufen (tool/ci_e2e.sh).
// PHASE=a: Lauf starten, aufzeichnen, "E2E_NEED_KILL" ausgeben; der Host beendet
//   den Prozess (am force-stop). Die Stufe laeuft mit --no-uninstall.
// PHASE=b: App neu starten; der Wiederanlauf-Dialog (recover_dialog) erscheint,
//   der Lauf wird fortgesetzt (recover_resume) und beendet. Geprueft wird, was
//   im Speicher steht: derselbe Lauf, nach dem Prozessende noch nicht beendet,
//   danach beendet und mit weiteren Positionen. Synthetische Daten, nur Zaehler.
// Ohne PHASE (Verzeichnislauf) wird der Test uebersprungen.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_support.dart';

const phase = String.fromEnvironment('PHASE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Wiederanlauf nach Prozessende $phase',
    (t) async {
      final w = buildWorld();
      await startApp(t, w);
      if (phase == 'a') {
        await setupIfShown(t);
        await connect(t, ['fake-gurt-1'], 'fake-gurt-1');
        await startRun(t);
        await pumpFor(t, const Duration(seconds: 14));
        final runs = await countRuns(t, w);
        log('RECOVER_A runs=${runs.length} pos=${runs.first.positions}');
        expect(runs.first.state, isNot(RunState.finished));
        expect(runs.first.positions, greaterThan(3));
        expect(runs.first.heartRates, greaterThan(3));
        log('NEED_KILL');
        await pumpFor(t, const Duration(seconds: 60));
        fail('Prozess lebt nach NEED_KILL noch');
      } else {
        await waitFor(t, () => has('recover_dialog'), 'Wiederanlauf-Dialog');
        final before = await countRuns(t, w);
        log('RECOVER_B runs=${before.length} state=${before.first.state}');
        expect(before.length, 1, reason: 'der eine Lauf aus Stufe a');
        expect(before.first.state, isNot(RunState.finished));
        expect(before.first.positions, greaterThan(3));
        await tapKey(t, 'recover_resume');
        await waitFor(t, () => has('run_time'), 'Laufseite nach Fortsetzen');
        await pumpFor(t, const Duration(seconds: 8));
        await finishRun(t);
        await pumpFor(t, const Duration(seconds: 2));
        final after = await countRuns(t, w);
        expect(after.length, 1, reason: 'kein zweiter Lauf entstanden');
        expect(after.first.state, RunState.finished);
        expect(
          after.first.positions,
          greaterThan(before.first.positions),
          reason: 'nach dem Fortsetzen kommen Positionen dazu',
        );
        expect(
          after.first.heartRates,
          greaterThanOrEqualTo(before.first.heartRates),
        );
      }
    },
    skip: phase.isEmpty,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
