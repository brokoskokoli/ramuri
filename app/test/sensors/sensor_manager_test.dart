import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';

/// Sensor, dessen Suche mit einem Fehler endet (Bluetooth aus).
class _FailingScan extends FakeHeartRateSensor {
  @override
  Stream<HeartRateDevice> scan() => Stream.error(StateError('bluetooth off'));
}

class _Rig {
  _Rig({FakeHeartRateSensor? sensor, FakeStorage? storage})
    : sensor = sensor ?? FakeHeartRateSensor(),
      storage = storage ?? FakeStorage() {
    manager = SensorManager(
      sensor: this.sensor,
      clock: clock,
      reconnectDelay: const Duration(seconds: 5),
      requestPermissions: () async => permissionRequests++,
    );
  }

  final FakeHeartRateSensor sensor;
  final FakeStorage storage;
  final clock = FakeClock(DateTime.utc(2026, 6, 1));
  int permissionRequests = 0;
  late final KnownDeviceStore store;
  late final SensorManager manager;

  /// Öffnet die Sitzung (wie der App-Start) und nimmt deren Gerätespeicher.
  Future<void> open() async {
    final session = await storage.open(Uint8List(32));
    store = session.devices;
    await manager.attachStore(store);
  }

  Future<void> connect(WidgetTester t, String id, {String? name}) async {
    await manager.connect(id, name: name);
    await t.pump();
  }

  void reading(String id, int bpm) => sensor.emitReading(id, clock.now(), bpm);
}

void main() {
  testWidgets('Start und Anbinden des Speichers fragen nichts ab', (t) async {
    final r = _Rig();
    await r.open();
    await r.manager.reloadKnown();
    expect(r.permissionRequests, 0);
    expect(r.sensor.connectedIds, isEmpty);
    expect(r.manager.scanning, isFalse);
    expect(r.manager.problem, isNull);
  });

  testWidgets('bekannte Geräte und Bevorzugung überstehen den Neustart', (
    t,
  ) async {
    final storage = FakeStorage();
    final a = _Rig(storage: storage);
    await a.open();
    await a.connect(t, 'g1', name: 'Gurt 1');
    await a.connect(t, 'g2', name: 'Gurt 2');
    await a.manager.setPreferred('g2');
    a.manager.dispose();

    // Neuer Prozess, derselbe Speicher.
    final b = _Rig(storage: storage);
    await b.open();
    expect(b.manager.knownEntries.map((e) => e.id), ['g1', 'g2']);
    expect(b.manager.knownEntries.map((e) => e.name), ['Gurt 1', 'Gurt 2']);
    expect(b.manager.knownEntries.where((e) => e.preferred).single.id, 'g2');
    expect(b.manager.selector.preferredId, 'g2');
    // Nichts verbindet sich von selbst.
    expect(b.sensor.connectedIds, isEmpty);
    expect(b.permissionRequests, 0);
    // Änderbar.
    await b.manager.setPreferred('g1');
    expect(b.manager.selector.preferredId, 'g1');
    await b.manager.setPreferred(null);
    expect(b.manager.selector.preferredId, isNull);
  });

  testWidgets('Puls nur bei Verbindung, nach Trennen keine Werte', (t) async {
    final r = _Rig();
    await r.open();
    await r.connect(t, 'g1');
    final got = <int>[];
    r.manager.activeReadings.listen((e) => got.add(e.beatsPerMinute));
    r.reading('g1', 120);
    await t.pump();
    expect(r.manager.knownEntries.single.bpm, 120);
    expect(got, [120]);

    r.manager.disconnect('g1');
    await t.pump();
    final e = r.manager.knownEntries.single;
    expect(e.state, SensorLinkState.idle);
    expect(e.bpm, isNull);
    expect(r.sensor.connectedIds, isEmpty);
    expect(r.manager.selector.connectedIds, isEmpty);
    expect(r.manager.selector.activeId, isNull);
    expect(() => r.reading('g1', 130), throwsStateError);
    // Nach Trennen kein Neuverbinden.
    await t.pump(const Duration(minutes: 1));
    expect(r.sensor.connectedIds, isEmpty);
    expect(got, [120]);
  });

  testWidgets('Batterie nur, wenn gemeldet', (t) async {
    final r = _Rig();
    await r.open();
    await r.connect(t, 'g1');
    r.reading('g1', 100);
    await t.pump();
    expect(r.manager.knownEntries.single.batteryPercent, isNull);
    r.sensor.emitBattery('g1', 64);
    await t.pump();
    expect(r.manager.knownEntries.single.batteryPercent, 64);
    r.manager.disconnect('g1');
    expect(r.manager.knownEntries.single.batteryPercent, isNull);
  });

  testWidgets('Verlust: Neuverbinden desselben Geräts ohne Wechsel', (t) async {
    final r = _Rig();
    await r.open();
    await r.connect(t, 'g1');
    await r.connect(t, 'g2');
    expect(r.manager.selector.activeId, 'g1');

    unawaited(r.sensor.drop('g1'));
    await t.pump();
    expect(r.manager.knownEntries.first.state, SensorLinkState.reconnecting);
    expect(r.manager.knownEntries.first.bpm, isNull);
    expect(r.manager.selector.activeId, 'g2');

    await t.pump(const Duration(seconds: 5));
    expect(r.sensor.connectedIds, {'g1', 'g2'});
    expect(r.manager.knownEntries.first.state, SensorLinkState.connected);
    // Kein Rückwechsel auf g1 (OQ-0037); nur der eine Wechsel durch den Verlust.
    expect(r.manager.selector.activeId, 'g2');
    expect(r.manager.selector.switches, hasLength(1));
  });

  testWidgets('Verlust des einzigen Geräts: Neuverbinden ohne Wechsel', (
    t,
  ) async {
    final r = _Rig();
    await r.open();
    await r.connect(t, 'g1');
    unawaited(r.sensor.drop('g1'));
    await t.pump();
    expect(r.manager.selector.activeId, isNull);
    await t.pump(const Duration(seconds: 5));
    expect(r.manager.selector.activeId, 'g1');
    expect(r.manager.selector.switches, isEmpty);
    r.reading('g1', 90);
    await t.pump();
    expect(r.manager.knownEntries.single.bpm, 90);
  });

  testWidgets('bewusstes Trennen: Selector bekommt lost:false', (t) async {
    final r = _Rig();
    await r.open();
    await r.connect(t, 'g1');
    await r.connect(t, 'g2');
    r.manager.disconnect('g1');
    expect(
      r.manager.selector.switches.single.reason,
      SourceSwitchReason.disconnected,
    );
    expect(r.manager.selector.activeId, 'g2');
  });

  testWidgets('Rechte verweigert: Hinweis, kein Sensorzugriff', (t) async {
    final sensor = FakeHeartRateSensor();
    final manager = SensorManager(
      sensor: sensor,
      clock: FakeClock(DateTime.utc(2026)),
      requestPermissions: () async => throw StateError('denied'),
    );
    await manager.startScan();
    expect(manager.problem, SensorProblem.permissionDenied);
    expect(manager.scanning, isFalse);
    await manager.connect('g1');
    expect(manager.problem, SensorProblem.permissionDenied);
    expect(sensor.connectedIds, isEmpty);
  });

  testWidgets('Bluetooth aus: Fehler der Suche wird Hinweis', (t) async {
    final r = _Rig(sensor: _FailingScan());
    await r.manager.startScan();
    await t.pump();
    expect(r.manager.problem, SensorProblem.bluetoothUnavailable);
    expect(r.manager.scanning, isFalse);
  });

  testWidgets('Suche listet kompatible Geräte', (t) async {
    final r = _Rig();
    await r.open();
    await r.manager.startScan();
    expect(r.permissionRequests, 1);
    r.sensor.discover(const HeartRateDevice(id: 'x', name: 'Gurt X'));
    await t.pump();
    expect(r.manager.foundEntries.single.name, 'Gurt X');
    expect(r.manager.knownEntries, isEmpty);
    r.manager.stopScan();
  });
}
