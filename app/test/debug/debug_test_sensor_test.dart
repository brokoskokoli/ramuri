import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adapters/adapters.dart' show BleHeartRateSensor;
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_sensor.dart';

void main() {
  debugWiringTests();
  // Alle Zeittests laufen in künstlicher Zeit (testWidgets = FakeAsync):
  // `tester.pump(d)` schiebt die Uhr um d vor und löst dabei den
  // `Timer.periodic` des Sensors genau so oft aus, wie es d entspricht.
  // Es wird nie auf der Wanduhr gewartet.
  const takt = Duration(milliseconds: 5);

  testWidgets('Test-Sensor: Werte, Abbruch, Neuverbinden', (tester) async {
    final sensor = DebugTestSensor(
      FakeClock(DateTime.utc(2030)),
      interval: takt,
    );
    final first = <HeartRateEvent>[];
    var done = false;
    sensor.connect('fake-gurt-1').listen(first.add, onDone: () => done = true);
    await tester.pump();
    expect(first.first, isA<HeartRateConnected>());
    expect(first.whereType<HeartRateReading>(), isEmpty);
    await tester.pump(takt * 8);
    expect(first.whereType<HeartRateReading>(), hasLength(8));
    sensor.drop('fake-gurt-1');
    await tester.pump();
    expect((first.last as HeartRateDisconnected).lost, isTrue);
    expect(done, isTrue);
    // Nach dem Abbruch erzeugt der Takt nichts mehr.
    final nachAbbruch = first.length;
    await tester.pump(takt * 4);
    expect(first, hasLength(nachAbbruch));

    final second = <HeartRateEvent>[];
    final sub = sensor.connect('fake-gurt-1').listen(second.add);
    await tester.pump(takt * 4);
    expect(second.first, isA<HeartRateConnected>());
    expect(second.whereType<HeartRateReading>(), hasLength(4));
    // Abmelden ohne await: die Zukunft von cancel() stammt nicht aus der
    // künstlichen Zone und würde dort nie fertig; pump() führt es aus.
    unawaited(sub.cancel());
    await tester.pump();
  });

  testWidgets('rohes Paket läuft durch den Parser, ungültiges nicht', (
    tester,
  ) async {
    final sensor = DebugTestSensor(
      FakeClock(DateTime.utc(2030)),
      interval: const Duration(hours: 1),
    );
    final ev = <HeartRateEvent>[];
    final sub = sensor.connect('fake-gurt-2').listen(ev.add);
    await tester.pump();
    sensor.sendRaw('fake-gurt-2', [0x16, 88]);
    sensor.sendRaw('fake-gurt-2', [0x01]);
    await tester.pump();
    expect(ev.whereType<HeartRateReading>().single.beatsPerMinute, 88);
    // Abmelden ohne await: die Zukunft von cancel() stammt nicht aus der
    // künstlichen Zone und würde dort nie fertig; pump() führt es aus.
    unawaited(sub.cancel());
    await tester.pump();
  });

  testWidgets('RR schaltbar: aus = keine, an = synthetisch (FR-0213)', (
    tester,
  ) async {
    final sensor = DebugTestSensor(
      FakeClock(DateTime.utc(2030)),
      interval: takt,
    );
    final ev = <HeartRateEvent>[];
    final sub = sensor.connect('fake-gurt-1').listen(ev.add);
    await tester.pump(takt * 6);
    final ohne = ev.whereType<HeartRateReading>().toList();
    expect(ohne, hasLength(6));
    expect(ohne.every((r) => r.rrIntervals.isEmpty), isTrue);

    // Alle bis hier erzeugten Werte sind zugestellt (pump leert die
    // Mikrotasks); jeder ab jetzt vom Takt erzeugte Wert trägt einen
    // Schlagabstand.
    final vorher = ev.length;
    sensor.sendRr = true;
    await tester.pump(takt * 6);
    final mit = ev.skip(vorher).whereType<HeartRateReading>().toList();
    expect(mit, hasLength(6));
    for (final r in mit) {
      // Puls 120 ± 3: ca. 512 (1/1024 s), exakt 1024 * 60 / Puls.
      expect(r.rrIntervals, hasLength(1));
      expect(r.rrIntervals.single, (1024 * 60 / r.beatsPerMinute).round());
      expect(r.rrIntervals.single, inInclusiveRange(496, 529));
    }

    // Rohpaket mit RR 1024 kommt auch bei ausgeschaltetem RR durch; die
    // Takt-Werte danach tragen wieder keinen Schlagabstand.
    sensor.sendRr = false;
    final vorRoh = ev.length;
    sensor.sendRaw('fake-gurt-1', [0x10, 60, 0x00, 0x04]);
    await tester.pump(takt * 3);
    final danach = ev.skip(vorRoh).whereType<HeartRateReading>().toList();
    expect(danach, hasLength(4));
    expect(danach.first.beatsPerMinute, 60);
    expect(danach.first.rrIntervals, [1024]);
    expect(danach.skip(1).every((r) => r.rrIntervals.isEmpty), isTrue);
    // Abmelden ohne await: die Zukunft von cancel() stammt nicht aus der
    // künstlichen Zone und würde dort nie fertig; pump() führt es aus.
    unawaited(sub.cancel());
    await tester.pump();
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
