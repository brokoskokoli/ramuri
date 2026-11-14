// E2E: Lauf aufzeichnen und speichern (Test-Sensor mit RR, GPS vom Emulator,
// den tool/ci_e2e.sh per `adb emu geo fix` bewegt). Geprueft wird, was im
// verschluesselten Speicher ankommt: ein neuer, beendeter Lauf mit Positionen,
// Pulswerten und genau dem gesendeten RR-Kanarienpaket. Synthetische Daten,
// Ausgabe nur Zaehler.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Lauf aufzeichnen und speichern', (t) async {
    final w = buildWorld();
    w.sensor.sendRr = true;
    await startApp(t, w);
    await setupIfShown(t);
    final before = (await countRuns(t, w)).length;

    await connect(t, ['fake-gurt-1'], 'fake-gurt-1');
    await startRun(t);
    await pumpFor(t, const Duration(seconds: 8));
    // Die Live-Anzeige zeigt Puls aus dem Sensor und eine Zeit.
    expect(has('run_hr'), isTrue);
    expect(txt('run_hr'), isNot('<fehlt>'));
    // Kanarienpaket (Flags 0x16: RR + Kontakt) mit eindeutigem Wert 0x1357.
    for (var i = 0; i < 3; i++) {
      w.sensor.sendRaw('fake-gurt-1', [0x16, 120, 0x57, 0x13]);
      await pumpFor(t, const Duration(milliseconds: 400));
    }
    await pumpFor(t, const Duration(seconds: 6));
    await finishRun(t);
    // Der Abschluss schreibt asynchron in die Datenbank.
    await pumpFor(t, const Duration(seconds: 2));

    final after = await countRunsFinished(t, w);
    log('RUN runs_before=$before runs_after=${after.length}');
    expect(after.length, before + 1, reason: 'genau ein neuer Lauf');
    final run = after.first;
    expect(run.state, RunState.finished);
    expect(run.positions, greaterThan(3), reason: 'GPS-Positionen gespeichert');
    expect(run.heartRates, greaterThan(5), reason: 'Pulswerte gespeichert');
    expect(run.rrPackets, greaterThan(0), reason: 'RR gespeichert');
    expect(run.canary, 3, reason: 'Kanarienpaket genau dreimal');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
