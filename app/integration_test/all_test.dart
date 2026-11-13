// Einstieg der Regressionssammlung: alle Ablaeufe, die ohne Neustart des
// Prozesses laufen, in EINEM Build/Install (ein `flutter test` je Datei baut
// und installiert jedes Mal neu). tool/ci_e2e.sh startet diese Datei; die
// Mehrphasen-Tests (e2e_storage_test.dart, e2e_recover_test.dart) laufen
// danach mit eigenem Lauf, weil der Prozess dazwischen beendet wird.
// Jede Datei hier hat eine eigene main() und gehoert in genau eine Gruppe.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_recalc_test.dart' as recalc;
import 'e2e_run_test.dart' as run;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Reihenfolge: Neuberechnung legt Profil und Laeufe an, danach zeichnet der
  // Lauf-Test auf dem vorhandenen Stand auf.
  group('Neuberechnung', recalc.main);
  group('Lauf', run.main);
}
