import 'dart:async';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app_dependencies.dart';

/// Bluetooth-Verbindung, die jeden Aufruf zählt.
class _Link implements BleLink {
  int permissionRequests = 0;
  int bluetoothChecks = 0;
  int connects = 0;

  @override
  Future<void> requestPermissions() async => permissionRequests++;

  @override
  Future<bool> isBluetoothOn() async {
    bluetoothChecks++;
    return true;
  }

  @override
  Stream<BleAdvert> scan(String serviceUuid) => const Stream.empty();

  @override
  Stream<bool> connectionStates(String deviceId) =>
      StreamController<bool>().stream;

  @override
  Future<void> connect(
    String deviceId, {
    required bool autoConnect,
    required bool closeGattOnDetach,
    required Duration timeout,
  }) async => connects++;

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<List<BleServiceInfo>> discoverServices(String deviceId) =>
      Completer<List<BleServiceInfo>>().future;

  @override
  Stream<List<int>> notifications(String d, String s, String c) =>
      StreamController<List<int>>().stream;

  @override
  Future<List<int>> read(String d, String s, String c) =>
      Completer<List<int>>().future;
}

/// Verdrahtung wie in der App (`AppDependencies.create` mit dem echten
/// Bluetooth-Adapter und dem echten Kanal der Berechtigungen); nur der
/// Kanal und die Verbindung sind Attrappen.
Future<(AppDependencies, _Link)> wired(Map<String, String>? status) async {
  final link = _Link();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(permissionChannel, (call) async {
        if (call.method == 'status') return status;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null),
  );
  final deps = AppDependencies.create(
    heartRateSensor: BleHeartRateSensor(link, FakeClock(DateTime.utc(2026))),
  );
  final session = await FakeStorage().open(Uint8List(32));
  await session.devices.upsert(
    'g1',
    displayName: 'Gurt',
    at: DateTime.utc(2026),
  );
  await deps.sensors.attachStore(session.devices);
  addTearDown(deps.sensors.dispose);
  return (deps, link);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (label, status) in [
    ('denied', {'bluetooth': 'denied'}),
    ('unknown (Schlüssel fehlt)', <String, String>{}),
    ('unbekannter Wert', {'bluetooth': 'maybe'}),
  ]) {
    test(
      'Kanal meldet Bluetooth $label: kein Verbinden, keine Abfrage',
      () async {
        final (deps, link) = await wired(status);
        await deps.runPorts.connectSensors!();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(link.connects, 0);
        expect(link.permissionRequests, 0);
        expect(link.bluetoothChecks, 0);
      },
    );
  }

  test(
    'Kanal meldet Bluetooth granted: verbindet ohne Rechteabfrage',
    () async {
      final (deps, link) = await wired({'bluetooth': 'granted'});
      await deps.runPorts.connectSensors!();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(link.connects, 1);
      expect(link.permissionRequests, 0);
    },
  );
}
