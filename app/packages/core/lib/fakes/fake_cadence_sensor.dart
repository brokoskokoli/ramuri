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

  /// [elapsed] fehlt: Monotonzeit wie die Wanduhr seit der Epoche.
  void emit(DateTime time, double stepsPerMinute, [Duration? elapsed]) =>
      _controller.add(
        CadenceReading(
          time,
          stepsPerMinute,
          elapsed ?? Duration(milliseconds: time.millisecondsSinceEpoch),
        ),
      );

  /// Der Strom endet mit Fehler (Sensor oder Recht fiel weg).
  void fail() => _controller.addError(StateError('Sensor weg'));

  /// Der Strom endet regulär.
  Future<void> end() => _controller.close();
}
