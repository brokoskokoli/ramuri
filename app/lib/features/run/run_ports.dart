import 'package:core/core.dart';

import '../sensors/run_heart_rate.dart';

/// Was die Aufzeichnung von außen braucht (Ports, ADR-0005). Produktiv sind
/// es die Adapter, in Tests die Fakes aus `core`.
class RunPorts {
  const RunPorts({
    required this.access,
    required this.location,
    this.heartRateRun,
    this.connectSensors,
  });

  /// Standortberechtigung und GPS-Schalter (FR-0195).
  final LocationAccessPort access;

  /// Standortpunkte des Laufs.
  final LocationSource location;

  /// Pulsquelle eines Laufs aus der Sensorverwaltung: wird beim Start des
  /// Laufs aufgerufen (ein Selector je Lauf, WP07 Teil D). `null` ohne
  /// Sensorverwaltung; die Oberfläche zeigt dann „nicht verfügbar“.
  final RunHeartRate Function()? heartRateRun;

  /// Verbindet beim Öffnen des Lauf-Bildschirms die bekannten Pulssensoren,
  /// falls die Rechte schon erteilt sind (WP07 Teil E). Fragt nie nach Rechten.
  final Future<void> Function()? connectSensors;
}
