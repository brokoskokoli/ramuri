import 'package:core/core.dart';

import '../sensors/run_heart_rate.dart';

/// Was die Aufzeichnung von außen braucht (Ports, ADR-0005). Produktiv sind
/// es die Adapter, in Tests die Fakes aus `core`.
class RunPorts {
  const RunPorts({
    required this.access,
    required this.location,
    this.heartRate,
    this.heartRateRun,
  });

  /// Standortberechtigung und GPS-Schalter (FR-0195).
  final LocationAccessPort access;

  /// Standortpunkte des Laufs.
  final LocationSource location;

  /// Einfache Pulsquelle ohne Verwaltung (Tests). Ohne Quelle `null`; die
  /// Oberfläche zeigt dann „nicht verfügbar“. Hat [heartRateRun] Vorrang.
  final Stream<HeartRateReading> Function()? heartRate;

  /// Pulsquelle eines Laufs aus der Sensorverwaltung: wird beim Start des
  /// Laufs aufgerufen (ein Selector je Lauf, WP07 Teil D). `null` ohne
  /// Sensorverwaltung.
  final RunHeartRate Function()? heartRateRun;
}
