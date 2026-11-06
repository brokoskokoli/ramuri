import 'dart:async';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLink implements BleLink {
  final adverts = StreamController<BleAdvert>.broadcast();
  final states = StreamController<bool>.broadcast();
  final hrValues = StreamController<List<int>>.broadcast();
  bool bluetoothOn = true;
  @override
  Future<bool> isBluetoothOn() async => bluetoothOn;

  String? scanService;
  bool scanCancelled = false;
  bool? autoConnect;
  bool? closeGatt;
  int disconnects = 0;
  Object? connectError;
  Completer<void>? connectGate;
  List<BleServiceInfo> services = const [
    BleServiceInfo('180d', ['2a37']),
    BleServiceInfo('180f', ['2a19']),
  ];
  List<int>? battery = [80];
  bool batteryFails = false;
  bool permissionsAsked = false;

  @override
  Future<void> requestPermissions() async => permissionsAsked = true;

  @override
  Stream<BleAdvert> scan(String serviceUuid) {
    scanService = serviceUuid;
    return adverts.stream.transform(
      StreamTransformer.fromHandlers(handleDone: (s) => s.close()),
    );
  }

  @override
  Stream<bool> connectionStates(String deviceId) => states.stream;

  @override
  Future<void> connect(
    String deviceId, {
    required bool autoConnect,
    required bool closeGattOnDetach,
    required Duration timeout,
  }) async {
    this.autoConnect = autoConnect;
    closeGatt = closeGattOnDetach;
    await connectGate?.future;
    if (connectError != null) throw connectError!;
  }

  @override
  Future<void> disconnect(String deviceId) async => disconnects++;

  @override
  Future<List<BleServiceInfo>> discoverServices(String deviceId) async =>
      services;

  @override
  Stream<List<int>> notifications(String d, String s, String c) =>
      hrValues.stream;

  @override
  Future<List<int>> read(String d, String s, String c) async {
    if (batteryFails) throw StateError('x');
    return battery!;
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  final t0 = DateTime.utc(2030, 1, 1, 12);
  late FakeLink link;
  late BleHeartRateSensor sensor;

  setUp(() {
    link = FakeLink();
    sensor = BleHeartRateSensor(link, FakeClock(t0));
  });

  group('scan', () {
    test('filtert auf 0x180D und meldet jedes Gerät einmal', () async {
      final found = <HeartRateDevice>[];
      final sub = sensor.scan().listen(found.add);
      await pump();
      expect(link.scanService, '180d');
      link.adverts
        ..add(const BleAdvert(id: 'a', name: 'Gurt'))
        ..add(const BleAdvert(id: 'a', name: 'Gurt'))
        ..add(const BleAdvert(id: 'b'));
      await pump();
      expect(found.map((d) => d.id), ['a', 'b']);
      expect(found.first.name, 'Gurt');
      await sub.cancel();
    });

    test('Abbrechen beendet die Suche im Link', () async {
      final sub = sensor.scan().listen((_) {});
      await pump();
      expect(link.adverts.hasListener, isTrue);
      await sub.cancel();
      expect(link.adverts.hasListener, isFalse);
    });
  });

  group('connect', () {
    Future<(List<HeartRateEvent>, StreamSubscription<HeartRateEvent>)>
    open() async {
      final events = <HeartRateEvent>[];
      final sub = sensor.connect('d1').listen(events.add, onError: (_) {});
      await pump();
      await pump();
      await pump();
      return (events, sub);
    }

    test('autoConnect und closeGattOnDetach nach ADR-0006', () async {
      final (_, sub) = await open();
      expect(link.autoConnect, isTrue);
      expect(link.closeGatt, isTrue);
      await sub.cancel();
    });

    test('Connected, Batterie, dann Werte mit Zeit und Kontakt', () async {
      final (events, sub) = await open();
      link.hrValues.add([0x16, 72]); // Kontakt gut, 8 Bit
      link.hrValues.add([0x01, 0x2C, 0x01]); // 16 Bit: 300
      await pump();
      expect(events[0], isA<HeartRateConnected>());
      expect((events[1] as HeartRateBattery).percent, 80);
      final r = events[2] as HeartRateReading;
      expect(r.deviceId, 'd1');
      expect(r.beatsPerMinute, 72);
      expect(r.contact, SensorContact.good);
      expect(r.time, t0);
      expect((events[3] as HeartRateReading).beatsPerMinute, 300);
      await sub.cancel();
    });

    test('ungültige Pakete ergeben kein Ereignis', () async {
      final (events, sub) = await open();
      link.hrValues
        ..add([])
        ..add([0x01, 70]) // 16 Bit, ein Byte fehlt
        ..add([0x00, 300]); // Byte außerhalb 0..255
      await pump();
      expect(events.whereType<HeartRateReading>(), isEmpty);
      await sub.cancel();
    });

    test('ohne Batteriedienst kein Batterie-Ereignis', () async {
      link.services = const [
        BleServiceInfo('180d', ['2a37']),
      ];
      final (events, sub) = await open();
      expect(events.whereType<HeartRateBattery>(), isEmpty);
      expect(events.first, isA<HeartRateConnected>());
      await sub.cancel();
    });

    test('Lesefehler oder ungültige Batterie: kein Ereignis', () async {
      link.batteryFails = true;
      var (events, sub) = await open();
      expect(events.whereType<HeartRateBattery>(), isEmpty);
      await sub.cancel();
      link.batteryFails = false;
      link.battery = [101];
      (events, sub) = await open();
      expect(events.whereType<HeartRateBattery>(), isEmpty);
      await sub.cancel();
    });

    test('Verlust: Disconnected(lost) und Ende', () async {
      final (events, sub) = await open();
      var done = false;
      sub.onDone(() => done = true);
      link.states.add(false);
      await pump();
      await pump();
      link.hrValues.add([0, 70]);
      await pump();
      expect((events.last as HeartRateDisconnected).lost, isTrue);
      expect(events.whereType<HeartRateReading>(), isEmpty);
      expect(done, isTrue);
      expect(link.disconnects, 1);
    });

    test('Abbrechen des Abos trennt, danach keine Werte', () async {
      final (events, sub) = await open();
      await sub.cancel();
      expect(link.disconnects, 1);
      link.hrValues.add([0, 70]);
      await pump();
      expect(events.whereType<HeartRateReading>(), isEmpty);
    });

    test('Abbrechen während des Verbindens: trennt (auch nach spätem Verbinden), kein Ereignis', () async {
      link.connectGate = Completer<void>();
      final events = <HeartRateEvent>[];
      final sub = sensor.connect('d1').listen(events.add);
      await pump();
      await sub.cancel();
      link.connectGate!.complete();
      await pump();
      await pump();
      expect(link.disconnects, 2);
      expect(events, isEmpty);
    });

    test(
      'Fehler beim Verbinden: Fehler am Strom, Ende, ohne Kennung',
      () async {
        link.connectError = StateError('mac AA:BB:CC:DD:EE:FF');
        final errors = <Object>[];
        var done = false;
        sensor
            .connect('d1')
            .listen((_) {}, onError: errors.add, onDone: () => done = true);
        await pump();
        await pump();
        await pump();
        expect(errors.single, isA<HeartRateConnectException>());
        expect(errors.single.toString(), isNot(contains('AA:BB')));
        expect(done, isTrue);
      },
    );

    test('Gerät ohne 0x2A37: Fehler, getrennt', () async {
      link.services = const [
        BleServiceInfo('180f', ['2a19']),
      ];
      final errors = <Object>[];
      sensor.connect('d1').listen((_) {}, onError: errors.add);
      await pump();
      await pump();
      await pump();
      expect(errors.single, isA<HeartRateConnectException>());
      expect(link.disconnects, 1);
    });

    test('Rechte werden nur auf Anforderung abgefragt', () async {
      expect(link.permissionsAsked, isFalse);
      await sensor.requestPermissions();
      expect(link.permissionsAsked, isTrue);
    });
  });
}
