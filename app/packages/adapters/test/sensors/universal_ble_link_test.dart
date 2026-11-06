import 'dart:async';

import 'package:adapters/adapters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

/// Fake-Plattform unter [UniversalBle.setInstance]; nicht benötigte Aufrufe
/// landen in [noSuchMethod] und lassen den Test scheitern.
class FakePlatform extends UniversalBlePlatform {
  final scanOut = StreamController<BleDevice>.broadcast();
  ScanFilter? filter;
  bool? autoConnect;
  ConnectionPlatformConfig? config;
  Object? startScanError;
  List<BleService> services = [];

  @override
  Stream<BleDevice> get scanStream => scanOut.stream;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    filter = scanFilter;
    if (startScanError != null) throw startScanError!;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    this.autoConnect = autoConnect;
    config = platformConfig;
    scheduleMicrotask(() => updateConnection(deviceId, true));
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async => services;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const hrFull = '0000180d-0000-1000-8000-00805f9b34fb';

void main() {
  late FakePlatform platform;
  const link = UniversalBleLink();

  setUp(() {
    platform = FakePlatform();
    UniversalBle.setInstance(platform);
  });

  test('scan: Filter auf den Pulsdienst, Adverts durchgereicht', () async {
    final adverts = <BleAdvert>[];
    final sub = link.scan(hrFull).listen(adverts.add);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(platform.filter, isNotNull);
    expect(platform.filter!.withServices, [hrFull]);
    platform.scanOut.add(BleDevice(deviceId: 'AA', name: 'Gurt'));
    await Future<void>.delayed(Duration.zero);
    expect(adverts.single.id, 'AA');
    expect(adverts.single.name, 'Gurt');
    await sub.cancel();
  });

  test('scan: Fehler des Plugin-Stroms wird Stromfehler', () async {
    final errors = <Object>[];
    final sub = link.scan(hrFull).listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    platform.scanOut.addError(StateError('boom'));
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<StateError>());
    await sub.cancel();
  });

  test('scan: Fehler von startScan wird Stromfehler', () async {
    platform.startScanError = StateError('bt aus');
    final errors = <Object>[];
    final sub = link.scan(hrFull).listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<StateError>());
    await sub.cancel();
  });

  test('connect: autoConnect und closeGattOnDetach kommen an', () async {
    await link.connect(
      'AA',
      autoConnect: true,
      closeGattOnDetach: true,
      timeout: const Duration(seconds: 5),
    );
    expect(platform.autoConnect, isTrue);
    expect(platform.config!.android!.closeGattOnDetach, isTrue);
  });

  test(
    'discoverServices: Basis-UUIDs werden Kurzform, andere bleiben',
    () async {
      const custom = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
      platform.services = [
        BleService(hrFull, [
          BleCharacteristic('00002a37-0000-1000-8000-00805f9b34fb', [], []),
        ]),
        BleService(custom, [BleCharacteristic(custom, [], [])]),
      ];
      final r = await link.discoverServices('AA');
      expect(r[0].uuid, '180d');
      expect(r[0].characteristics, ['2a37']);
      expect(r[1].uuid, custom);
      expect(r[1].characteristics, [custom]);
    },
  );
}
