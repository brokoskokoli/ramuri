import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adapters/adapters.dart' show BleHeartRateSensor;
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_sensor.dart';

void main() {
  debugWiringTests();
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

void debugWiringTests() {
  test('main_debug: derselbe Sensordienst nutzt den Test-Sensor', () async {
    final sensor = DebugTestSensor(FakeClock(DateTime.utc(2030)));
    final deps = AppDependencies.create(heartRateSensor: sensor);
    expect(identical(deps.sensors.sensor, sensor), isTrue);
    // Der Test-Sensor braucht keine Bluetooth-Rechte.
    expect(deps.sensors.requestPermissions, isNull);
    await deps.sensors.startScan();
    await pumpEventQueue();
    expect(deps.sensors.foundEntries, isNotEmpty);
    deps.sensors.dispose();
  });

  test('Standard: echter Adapter mit Rechteanfrage erst auf Abruf', () {
    final deps = AppDependencies.create();
    expect(deps.sensors.sensor, isA<BleHeartRateSensor>());
    expect(deps.sensors.requestPermissions, isNotNull);
    expect(deps.sensors.scanning, isFalse);
    deps.sensors.dispose();
  });
}
