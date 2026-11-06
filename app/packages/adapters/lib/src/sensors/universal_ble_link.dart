import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

import 'ble_link.dart';

/// [BleLink] über `universal_ble` 3.2.0. Enthält keine Logik außer der
/// Abbildung der Plugin-Typen. Nichts hier läuft beim App-Start: Das Plugin
/// wird erst benutzt, wenn der Nutzer einen Sensor einrichtet.
class UniversalBleLink implements BleLink {
  const UniversalBleLink();

  @override
  Future<void> requestPermissions() => UniversalBle.requestPermissions();

  @override
  Stream<BleAdvert> scan(String serviceUuid) {
    late final StreamController<BleAdvert> out;
    StreamSubscription<BleDevice>? sub;
    out = StreamController<BleAdvert>(
      onListen: () async {
        sub = UniversalBle.scanStream.listen(
          (d) => out.add(BleAdvert(id: d.deviceId, name: d.name)),
        );
        try {
          await UniversalBle.startScan(
            scanFilter: ScanFilter(withServices: [serviceUuid]),
            skipDuplicates: true,
          );
        } catch (e, s) {
          out.addError(e, s);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await UniversalBle.stopScan();
        } catch (_) {
          // Ausgeschaltetes Bluetooth: nichts zu beenden.
        }
      },
    );
    return out.stream;
  }

  @override
  Stream<bool> connectionStates(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Future<void> connect(
    String deviceId, {
    required bool autoConnect,
    required bool closeGattOnDetach,
    required Duration timeout,
  }) => UniversalBle.connect(
    deviceId,
    timeout: timeout,
    autoConnect: autoConnect,
    platformConfig: ConnectionPlatformConfig(
      android: AndroidConnectionOptions(closeGattOnDetach: closeGattOnDetach),
    ),
  );

  @override
  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  @override
  Future<List<BleServiceInfo>> discoverServices(String deviceId) async {
    final services = await UniversalBle.discoverServices(deviceId);
    return [
      for (final s in services)
        BleServiceInfo(_short(s.uuid), [
          for (final c in s.characteristics) _short(c.uuid),
        ]),
    ];
  }

  @override
  Stream<List<int>> notifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    late final StreamController<List<int>> out;
    StreamSubscription<List<int>>? sub;
    out = StreamController<List<int>>(
      onListen: () async {
        sub = UniversalBle.characteristicValueStream(
          deviceId,
          characteristicUuid,
        ).listen(out.add);
        try {
          await UniversalBle.subscribeNotifications(
            deviceId,
            serviceUuid,
            characteristicUuid,
          );
        } catch (e, s) {
          out.addError(e, s);
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<List<int>> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => UniversalBle.read(deviceId, serviceUuid, characteristicUuid);

  /// `0000180d-0000-1000-8000-00805f9b34fb` -> `180d`.
  static String _short(String uuid) {
    final u = uuid.toLowerCase();
    if (u.length == 36 && u.startsWith('0000') && u.endsWith(_base)) {
      return u.substring(4, 8);
    }
    return u;
  }

  static const _base = '-0000-1000-8000-00805f9b34fb';
}
