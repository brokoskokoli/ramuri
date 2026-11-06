import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_test_sensor.dart';

void main() {
  test('Test-Sensor: Werte, Abbruch, Neuverbinden', () async {
    final sensor = DebugTestSensor(
      FakeClock(DateTime.utc(2030)),
      interval: const Duration(milliseconds: 5),
    );
    final first = <HeartRateEvent>[];
    var done = false;
    sensor.connect('fake-gurt-1').listen(first.add, onDone: () => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(first.first, isA<HeartRateConnected>());
    expect(first.whereType<HeartRateReading>(), isNotEmpty);
    sensor.drop('fake-gurt-1');
    await Future<void>.delayed(Duration.zero);
    expect((first.last as HeartRateDisconnected).lost, isTrue);
    expect(done, isTrue);

    final second = <HeartRateEvent>[];
    final sub = sensor.connect('fake-gurt-1').listen(second.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second.first, isA<HeartRateConnected>());
    await sub.cancel();
  });

  test('rohes Paket läuft durch den Parser, ungültiges nicht', () async {
    final sensor = DebugTestSensor(
      FakeClock(DateTime.utc(2030)),
      interval: const Duration(hours: 1),
    );
    final ev = <HeartRateEvent>[];
    final sub = sensor.connect('fake-gurt-2').listen(ev.add);
    await Future<void>.delayed(Duration.zero);
    sensor.sendRaw('fake-gurt-2', [0x16, 88]);
    sensor.sendRaw('fake-gurt-2', [0x01]);
    await Future<void>.delayed(Duration.zero);
    expect(ev.whereType<HeartRateReading>().single.beatsPerMinute, 88);
    await sub.cancel();
  });
}
