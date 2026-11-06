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
    this.connectSensors,
    this.recordingService,
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

  /// Verbindet beim Öffnen des Lauf-Bildschirms die bekannten Pulssensoren,
  /// falls die Rechte schon erteilt sind (WP07 Teil E). Fragt nie nach Rechten.
  final Future<void> Function()? connectSensors;

  /// Foreground Service der Aufzeichnung (ADR-0005 Punkt 2, WP08). `null`
  /// ohne Dienst (Tests): Der Lauf läuft dann nur, solange die App sichtbar ist.
  final RecordingServicePort? recordingService;
}

/// Der Dienst, der den Prozess für die Dauer eines Laufs am Leben hält.
/// Dünn: Die Sitzung selbst läuft in Dart in derselben Engine weiter.
abstract interface class RecordingServicePort {
  /// Startet den Dienst und kehrt zurück, wenn er läuft. Wirft, wenn er nicht
  /// starten konnte (z. B. das System lehnt ab). Ein laufender Dienst bleibt
  /// unberührt.
  Future<void> start();

  /// Beendet den Dienst; ohne laufenden Dienst ohne Wirkung.
  Future<void> stop();

  /// Läuft der Dienst in diesem Prozess. Nach einem Prozessende `false`.
  Future<bool> isRunning();
}

/// Fake für Tests: zählt Aufrufe, kann den Start scheitern lassen und
/// lässt ihn auf Wunsch warten.
class FakeRecordingServicePort implements RecordingServicePort {
  FakeRecordingServicePort({this.startError});

  /// Wird bei [start] geworfen; der Dienst läuft dann nicht.
  Object? startError;

  /// Hält [start] an, bis diese Future fertig ist.
  Future<void>? startGate;

  int startCalls = 0;
  int stopCalls = 0;
  bool running = false;

  @override
  Future<void> start() async {
    startCalls++;
    await startGate;
    final e = startError;
    if (e != null) throw e;
    running = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    running = false;
  }

  @override
  Future<bool> isRunning() async => running;
}
