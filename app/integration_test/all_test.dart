// Einstieg der Regressionssammlung: alle Ablaeufe, die ohne Neustart des
// Prozesses laufen, in EINEM Build/Install (ein `flutter test` je Datei baut
// und installiert jedes Mal neu). tool/ci_e2e.sh startet diese Datei; die
// Mehrphasen-Tests (e2e_storage_test.dart, e2e_recover_test.dart) laufen
// danach mit eigenem Lauf, weil der Prozess dazwischen beendet wird.
// Jede Datei hier hat eine eigene main() und gehoert in genau eine Gruppe.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_archive_test.dart' as archive;
import 'e2e_health_test.dart' as health;
import 'e2e_plan_test.dart' as plan;
import 'e2e_recalc_test.dart' as recalc;
import 'e2e_resting_test.dart' as resting;
import 'e2e_run_test.dart' as run;
import 'e2e_treadmill_test.dart' as treadmill;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Reihenfolge: Neuberechnung legt Profil und Laeufe an, danach zeichnet der
  // Lauf-Test auf dem vorhandenen Stand auf.
  group('Neuberechnung', recalc.main);
  group('Lauf', run.main);
  // Plan und Warnsignal zuletzt: brauchen nur den Speicher, kein Lauf-Zustand.
  group('Plan und Warnsignal', plan.main);
  // Archiv zuletzt vor den Profil-Tests: der Reimport ersetzt die Datenbank
  // durch den Stand, den er vorher exportiert hat (also unveraendert).
  group('Archiv', archive.main);
  group('Laufband', treadmill.main);
  group('Ruhepuls Kamera', resting.main);
  // Health-Connect-Import mit der Debug-Quelle; Szenario 5 (echter Dialog) nur lokal mit --dart-define=HC_REAL=true.
  group('Health Connect', health.main);
}
