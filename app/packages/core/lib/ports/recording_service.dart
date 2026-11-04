enum RecordingServiceState { stopped, running }

/// Port: Aufzeichnungsdienst (Foreground Service, ADR-0005).
abstract interface class RecordingService {
  /// [withConnectedDevice]: Diensttyp `connectedDevice` nur bei erteiltem
  /// `BLUETOOTH_CONNECT` (ADR-0005 Punkt 2). Start im laufenden Dienst ist
  /// wirkungslos.
  Future<void> start({required bool withConnectedDevice});

  /// Stoppen eines gestoppten Dienstes ist wirkungslos.
  Future<void> stop();

  /// Wird beim App-Start gebraucht: aktiver Lauf ohne Dienst (ADR-0005 Punkt 5).
  Future<bool> isRunning();

  /// Zustandswechsel, auch wenn die Plattform den Dienst beendet.
  Stream<RecordingServiceState> get states;
}
