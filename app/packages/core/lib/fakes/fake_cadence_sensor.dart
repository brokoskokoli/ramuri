import 'dart:async';

import '../ports/cadence_sensor.dart';

class FakeCadenceSensor implements CadenceSensor {
  FakeCadenceSensor([this._availability = CadenceAvailability.available]);

  CadenceAvailability _availability;
  final _controller = StreamController<CadenceReading>.broadcast();

  set availabilityState(CadenceAvailability a) => _availability = a;

  @override
  Future<CadenceAvailability> availability() async => _availability;

  @override
  Stream<CadenceReading> readings() =>
      _availability == CadenceAvailability.available
      ? _controller.stream
      : const Stream<CadenceReading>.empty();

  void emit(DateTime time, double stepsPerMinute) =>
      _controller.add(CadenceReading(time, stepsPerMinute));
}
