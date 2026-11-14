import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';

// WP37 C2: Auto-Verbinden beim Öffnen der Morgenmessung. Synthetische Geräte.

class _Counting extends FakeHeartRateSensor {
  final calls = <String>[];

  @override
  Stream<HeartRateEvent> connect(String deviceId) {
    calls.add(deviceId);
    return super.connect(deviceId);
  }
}

class _Rig {
  _Rig({Future<bool> Function()? bluetooth, this.granted = true}) {
    manager = SensorManager(
      sensor: sensor,
      clock: clock,
      requestPermissions: () async {},
      bluetoothGranted: () async => granted,
      bluetoothAvailable: bluetooth,
    );
  }

  final bool granted;
  final sensor = _Counting();
  final clock = FakeClock(DateTime.utc(2026, 11, 10, 6));
  late final SensorManager manager;
  late final KnownDeviceStore store;

  Future<void> open({
    List<String> known = const ['g1', 'g2'],
    String? preferred,
    Map<String, DateTime> used = const {},
  }) async {
    final s = await FakeStorage().open(Uint8List(32));
    store = s.devices;
    for (final id in known) {
      await store.upsert(id, displayName: 'Gurt $id', at: clock.now());
    }
    if (preferred != null) await store.setPreferred(preferred);
    for (final e in used.entries) {
      await store.markUsed(e.key, at: e.value);
    }
    await manager.attachStore(store);
  }
}

void main() {
  final t0 = DateTime.utc(2026, 11, 1);

  test('zuletzt genutztes Gerät kommt vor dem bevorzugten', () async {
    final r = _Rig();
    await r.open(preferred: 'g1', used: {'g2': t0});
    await r.manager.connectBestKnown();
    expect(r.sensor.calls, ['g2']);
    expect(r.manager.connectedIds, {'g2'});
  });

  test('das jüngere von zwei genutzten Geräten gewinnt', () async {
    final r = _Rig();
    await r.open(used: {'g1': t0, 'g2': t0.add(const Duration(days: 1))});
    await r.manager.connectBestKnown();
    expect(r.sensor.calls, ['g2']);
  });

  test('ohne genutztes Gerät das bevorzugte, ohne beides keins', () async {
    final a = _Rig();
    await a.open(preferred: 'g1');
    await a.manager.connectBestKnown();
    expect(a.sensor.calls, ['g1']);
    final b = _Rig();
    await b.open();
    await b.manager.connectBestKnown();
    expect(b.sensor.calls, isEmpty);
  });

  test('kein bekanntes Gerät, keine Rechte, Bluetooth aus: nichts', () async {
    final a = _Rig();
    await a.open(known: const []);
    await a.manager.connectBestKnown();
    expect(a.sensor.calls, isEmpty);
    final b = _Rig(granted: false);
    await b.open(preferred: 'g1');
    await b.manager.connectBestKnown();
    expect(b.sensor.calls, isEmpty);
    final c = _Rig(bluetooth: () async => false);
    await c.open(preferred: 'g1');
    await c.manager.connectBestKnown();
    expect(c.sensor.calls, isEmpty);
  });

  test('Verbinden vermerkt „zuletzt genutzt“, auch von Hand', () async {
    final r = _Rig();
    await r.open();
    await r.manager.connect('g1');
    await pumpEventQueue();
    final list = await r.store.list();
    expect(
      list.firstWhere((k) => k.deviceId == 'g1').lastUsedAt,
      r.clock.now(),
    );
    expect(list.firstWhere((k) => k.deviceId == 'g2').lastUsedAt, isNull);
  });

  test('schon verbunden: kein zweites Gerät', () async {
    final r = _Rig();
    await r.open(preferred: 'g1', used: {'g2': t0});
    await r.manager.connect('g1');
    await r.manager.connectBestKnown();
    expect(r.sensor.calls, ['g1']);
  });

  test(
    'gleichzeitig Auto und Hand zum selben Gerät: eine Verbindung',
    () async {
      final r = _Rig();
      await r.open(used: {'g1': t0});
      await Future.wait([
        r.manager.connectBestKnown(),
        r.manager.connect('g1'),
      ]);
      await pumpEventQueue();
      expect(r.sensor.calls, ['g1']);
      expect(r.manager.connectedIds, {'g1'});
    },
  );

  test('Hand verbindet während Auto wartet: Auto lässt es dabei', () async {
    final gate = Completer<bool>();
    final r = _Rig(bluetooth: () => gate.future);
    await r.open(used: {'g1': t0});
    final auto = r.manager.connectBestKnown();
    await pumpEventQueue();
    await r.manager.connect('g2');
    gate.complete(true);
    await auto;
    expect(r.sensor.calls, ['g2']);
    expect(r.manager.connectedIds, {'g2'});
  });

  test('Lauf offen oder während des Wartens gestartet: kein Doppel', () async {
    final gate = Completer<bool>();
    final r = _Rig(bluetooth: () => gate.future);
    await r.open(used: {'g1': t0});
    final auto = r.manager.connectBestKnown();
    await pumpEventQueue();
    final run = r.manager.beginRun();
    gate.complete(true);
    await auto;
    expect(r.sensor.calls, isEmpty);
    await r.manager.connectBestKnown();
    expect(r.sensor.calls, isEmpty);
    run.close();
    r.manager.dispose();
  });

  test('zweiter Aufruf während des ersten: nur ein Versuch', () async {
    final r = _Rig();
    await r.open(used: {'g1': t0});
    await Future.wait([
      r.manager.connectBestKnown(),
      r.manager.connectBestKnown(),
    ]);
    expect(r.sensor.calls, ['g1']);
  });
}
