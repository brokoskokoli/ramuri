import 'dart:async';
import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel(stepSensorChannelName);
  const events = EventChannel(stepStreamChannelName);

  String availability = 'available';
  StreamController<Object?>? sink;
  var listened = 0;
  var cancelled = 0;

  setUp(() {
    availability = 'available';
    listened = 0;
    cancelled = 0;
    messenger.setMockMethodCallHandler(method, (call) async {
      if (call.method == 'availability') return availability;
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, e) {
          listened++;
          sink = StreamController<Object?>(sync: true)
            ..stream.listen(e.success);
        },
        onCancel: (arguments) => cancelled++,
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('Verfügbarkeit aus den Kotlin-Zuständen', () async {
    final s = MethodChannelCadenceSensor();
    expect(await s.availability(), CadenceAvailability.available);
    availability = 'permission_denied';
    expect(await s.availability(), CadenceAvailability.permissionDenied);
    availability = 'no_sensor';
    expect(await s.availability(), CadenceAvailability.noSensor);
    availability = 'etwas anderes';
    expect(await s.availability(), CadenceAvailability.noSensor);
  });

  test('ohne Plugin: kein Sensor, kein Fehler', () async {
    messenger.setMockMethodCallHandler(method, null);
    expect(
      await MethodChannelCadenceSensor().availability(),
      CadenceAvailability.noSensor,
    );
  });

  test(
    'ohne Berechtigung: leerer Strom, der Sensor wird nicht angehört',
    () async {
      availability = 'permission_denied';
      expect(await MethodChannelCadenceSensor().readings().toList(), isEmpty);
      expect(listened, 0);
    },
  );

  test('Schrittzeitpunkte ergeben Schrittfrequenz', () async {
    final got = <CadenceReading>[];
    final sub = MethodChannelCadenceSensor().readings().listen(got.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final t0 = DateTime.utc(2030, 1, 1).millisecondsSinceEpoch;
    for (var i = 0; i < 6; i++) {
      sink!.add({'timeMs': t0 + i * 500, 'elapsedMs': 9000 + i * 500});
    }
    sink!.add({'kein': 'Schritt'}); // wird ignoriert
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cancelled, 1, reason: 'Abbestellen gibt den Sensor frei');
    expect(got, isNotEmpty);
    expect(got.last.stepsPerMinute, closeTo(120, 0.001));
    expect(got.last.time, DateTime.utc(2030, 1, 1, 0, 0, 2, 500));
  });

  test(
    'Wanduhr zurückgestellt: Schritte zählen weiter (Monotonzeit)',
    () async {
      final got = <CadenceReading>[];
      final sub = MethodChannelCadenceSensor().readings().listen(got.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final t0 = DateTime.utc(2030, 1, 1).millisecondsSinceEpoch;
      for (var i = 0; i < 6; i++) {
        // Die Wanduhr springt nach dem dritten Schritt um eine Stunde zurück.
        final wall = t0 + i * 500 - (i >= 3 ? 3600000 : 0);
        sink!.add({'timeMs': wall, 'elapsedMs': 9000 + i * 500});
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(got.length, 4, reason: 'Schritte 3 bis 6 liefern je einen Wert');
      expect(got.last.stepsPerMinute, closeTo(120, 0.001));
      expect(got.last.elapsed, const Duration(milliseconds: 11500));
    },
  );

  test('Kanalnamen und Zustände stehen gleich in Kotlin', () {
    final kt = File(
      '../../android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/StepSensor.kt',
    ).readAsStringSync();
    final app = File(
      '../../android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/RunningApplication.kt',
    ).readAsStringSync();
    expect(kt, contains('"$stepSensorChannelName"'));
    expect(kt, contains('"$stepStreamChannelName"'));
    expect(kt, contains('"timeMs"'));
    expect(kt, contains('"elapsedMs"'));
    for (final v in ['available', 'permission_denied', 'no_sensor']) {
      expect(kt, contains('"$v"'), reason: v);
    }
    // Prozessweit an der Engine, nicht an der Activity.
    expect(app, contains('StepSensor.register('));
  });
}
