import 'package:core/core.dart';

/// Was die Aufzeichnung von außen braucht (Ports, ADR-0005). Produktiv sind
/// es die Adapter, in Tests die Fakes aus `core`.
class RunPorts {
  const RunPorts({
    required this.access,
    required this.location,
    this.heartRate,
  });

  /// Standortberechtigung und GPS-Schalter (FR-0195).
  final LocationAccessPort access;

  /// Standortpunkte des Laufs.
  final LocationSource location;

  /// Pulswerte, sofern eine Quelle verbunden ist. Ohne Quelle `null`; die
  /// Oberfläche zeigt dann „nicht verfügbar“. Die Sensorverwaltung kommt mit
  /// WP07.
  final Stream<HeartRateReading> Function()? heartRate;
}
