import 'dart:async';

import '../ports/recording_service.dart';

class FakeRecordingService implements RecordingService {
  final _controller = StreamController<RecordingServiceState>.broadcast();
  bool _running = false;

  /// Wie oft der Dienst tatsächlich gestartet wurde.
  int startCount = 0;

  /// Wert des letzten wirksamen Starts.
  bool? lastWithConnectedDevice;

  @override
  Future<void> start({required bool withConnectedDevice}) async {
    if (_running) return;
    _running = true;
    startCount++;
    lastWithConnectedDevice = withConnectedDevice;
    _controller.add(RecordingServiceState.running);
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _controller.add(RecordingServiceState.stopped);
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Stream<RecordingServiceState> get states => _controller.stream;

  /// Die Plattform beendet den Dienst (Prozess-Ende).
  void killByPlatform() {
    if (!_running) return;
    _running = false;
    _controller.add(RecordingServiceState.stopped);
  }
}
