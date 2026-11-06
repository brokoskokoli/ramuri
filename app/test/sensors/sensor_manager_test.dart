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

/// Sensor mit vorgegebenen Verbindungen: je Gerät eine Warteschlange von
/// Strömen für die nächsten `connect`-Aufrufe; danach das normale Verhalten.
class _ScriptedSensor extends FakeHeartRateSensor {
  final plans = <String, List<Stream<HeartRateEvent> Function()>>{};
  int connects = 0;

  @override
  Stream<HeartRateEvent> connect(String deviceId) {
    connects++;
    final plan = plans[deviceId];
    if (plan != null && plan.isNotEmpty) return plan.removeAt(0)();
    return super.connect(deviceId);
  }
}

/// Gerätespeicher, bei dem `upsert` eines Geräts auf ein Signal wartet.
class _GatedStore implements KnownDeviceStore {
  _GatedStore(this.inner, this.gatedId, this.gate);

  final KnownDeviceStore inner;
  final String gatedId;
  final Future<void> gate;

  @override
  Future<List<KnownDevice>> list() => inner.list();

  @override
  Future<void> upsert(
    String deviceId, {
    String? displayName,
    required DateTime at,
  }) async {
    if (deviceId == gatedId) await gate;
    return inner.upsert(deviceId, displayName: displayName, at: at);
  }

  @override
  Future<void> setPreferred(String? deviceId) => inner.setPreferred(deviceId);
}

Stream<HeartRateEvent> _failing() => Stream.error(StateError('timeout'));

class _Rig {
  _Rig({
    FakeHeartRateSensor? sensor,
    FakeStorage? storage,
    Future<bool> Function()? bluetoothAvailable,
    Future<void> Function()? requestPermissions,
  }) : sensor = sensor ?? FakeHeartRateSensor(),
       storage = storage ?? FakeStorage() {
    manager = SensorManager(
      sensor: this.sensor,
      clock: clock,
      reconnectDelay: const Duration(seconds: 5),
      bluetoothAvailable: bluetoothAvailable,
      requestPermissions:
          requestPermissions ?? () async => permissionRequests++,
    );
  }

  final FakeHeartRateSensor sensor;
  final FakeStorage storage;
  final clock = FakeClock(DateTime.utc(2026, 6, 1));
  int permissionRequests = 0;
  late final StorageSession session;
  late final KnownDeviceStore store;
  late final SensorManager manager;

  /// Öffnet die Sitzung (wie der App-Start) und nimmt deren Gerätespeicher.
  Future<void> open() async {
    final session = await storage.open(Uint8List(32));
    this.session = session;
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

  testWidgets('Neuverbinden scheitert: weiter versuchen, nach Trennen nicht', (
    t,
  ) async {
    final sensor = _ScriptedSensor();
    final r = _Rig(sensor: sensor);
    await r.open();
    await r.connect(t, 'g1');
    sensor.plans['g1'] = [_failing, _failing];
    unawaited(sensor.drop('g1'));
    await t.pump();
    expect(sensor.connects, 1);

    // Zwei Versuche scheitern (Gerät außer Reichweite), der Takt bleibt.
    for (final n in [2, 3]) {
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(sensor.connects, n);
      expect(r.manager.knownEntries.single.state, SensorLinkState.reconnecting);
      expect(r.manager.problem, isNull);
    }
    await t.pump(const Duration(seconds: 5));
    expect(sensor.connects, 4);
    expect(r.manager.knownEntries.single.state, SensorLinkState.connected);
    expect(r.manager.selector.switches, isEmpty);

    // Nach bewusstem Trennen kein weiterer Versuch, auch mitten im Warten.
    sensor.plans['g1'] = [_failing];
    unawaited(sensor.drop('g1'));
    await t.pump(const Duration(seconds: 5));
    await t.pump();
    expect(sensor.connects, 5);
    r.manager.disconnect('g1');
    await t.pump(const Duration(minutes: 2));
    expect(sensor.connects, 5);
    expect(r.manager.knownEntries.single.state, SensorLinkState.idle);
  });

  testWidgets('Strom endet ohne Abbruch-Ereignis: Selector wechselt', (
    t,
  ) async {
    for (final ending in <Stream<HeartRateEvent> Function()>[
      () => Stream.value(const HeartRateConnected('g1')),
      () => (() async* {
        yield const HeartRateConnected('g1');
        throw StateError('link');
      })(),
    ]) {
      final sensor = _ScriptedSensor();
      sensor.plans['g1'] = [ending];
      final r = _Rig(sensor: sensor);
      await r.open();
      await r.connect(t, 'g1');
      await r.connect(t, 'g2');
      await t.pump();
      expect(r.manager.selector.activeId, 'g2');
      expect(
        r.manager.selector.switches.single.reason,
        SourceSwitchReason.lost,
      );
      r.manager.disconnect('g1');
      r.manager.disconnect('g2');
      await t.pump();
    }
  });

  testWidgets('Doppeltipp auf Verbinden verbindet nur einmal', (t) async {
    final sensor = _ScriptedSensor();
    final r = _Rig(sensor: sensor);
    await r.open();
    final a = r.manager.connect('g1');
    final b = r.manager.connect('g1');
    await Future.wait([a, b]);
    await t.pump();
    expect(sensor.connects, 1);
    expect(r.permissionRequests, 1);
    expect(r.manager.connectedIds, {'g1'});

    // Trennen während die Rechte/der Speicher noch laufen: kein Verbinden.
    final c = r.manager.connect('g2');
    r.manager.disconnect('g2');
    await c;
    await t.pump();
    expect(sensor.connects, 1);
    expect(r.manager.connectedIds, {'g1'});
  });

  testWidgets('Alle Daten löschen trennt Geräte und stoppt Neuverbinden', (
    t,
  ) async {
    final sensor = _ScriptedSensor();
    final r = _Rig(sensor: sensor);
    await r.open();
    await r.connect(t, 'g1');
    await r.connect(t, 'g2');
    unawaited(sensor.drop('g2'));
    await t.pump();
    expect(r.manager.knownEntries.last.state, SensorLinkState.reconnecting);

    await r.session.deleteAll();
    await r.manager.reloadKnown();
    await t.pump();
    expect(r.manager.knownEntries, isEmpty);
    expect(r.manager.connectedIds, isEmpty);
    expect(sensor.connectedIds, isEmpty);
    expect(r.manager.selector.activeId, isNull);
    final connects = sensor.connects;
    await t.pump(const Duration(minutes: 2));
    expect(sensor.connects, connects);
  });

  testWidgets('Verbinden scheitert bei Bluetooth aus: Bluetooth-Hinweis', (
    t,
  ) async {
    var on = false;
    final sensor = _ScriptedSensor();
    sensor.plans['g1'] = [_failing, _failing];
    final r = _Rig(sensor: sensor, bluetoothAvailable: () async => on);
    await r.open();
    await r.connect(t, 'g1');
    await t.pump();
    expect(r.manager.problem, SensorProblem.bluetoothUnavailable);
    expect(r.manager.knownEntries.single.state, SensorLinkState.idle);

    // Bluetooth an, Gerät nicht erreichbar: bleibt „Verbinden fehlgeschlagen“.
    on = true;
    await r.connect(t, 'g1');
    await t.pump();
    expect(r.manager.problem, SensorProblem.connectFailed);
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

  testWidgets('Rechte verweigert, dann erteilt: zweites connect verbindet', (
    t,
  ) async {
    var grant = false;
    final r = _Rig(
      requestPermissions: () async {
        if (!grant) throw StateError('denied');
      },
    );
    await r.open();
    await r.connect(t, 'g1');
    expect(r.manager.problem, SensorProblem.permissionDenied);
    expect(r.manager.knownEntries, isEmpty);
    expect(r.sensor.connectedIds, isEmpty);

    grant = true;
    await r.connect(t, 'g1');
    expect(r.manager.problem, isNull);
    expect(r.sensor.connectedIds, {'g1'});
  });
  testWidgets('zwei Geräte warten auf Rechte und Speicher: beide verbinden', (
    t,
  ) async {
    final permit = Completer<void>();
    final store = Completer<void>();
    final r = _Rig(requestPermissions: () => permit.future);
    await r.open();
    await r.manager.attachStore(_GatedStore(r.store, 'g2', store.future));
    final a = r.manager.connect('g1');
    final b = r.manager.connect('g2');
    permit.complete();
    // g1 ist gespeichert und lädt neu, g2 steht noch nicht im Speicher.
    await a;
    expect(r.manager.knownEntries.map((e) => e.id), ['g1']);
    store.complete();
    await b;
    await t.pump();
    expect(r.sensor.connectedIds, {'g1', 'g2'});
    expect(r.manager.knownEntries.map((e) => e.id), ['g1', 'g2']);
  });

  testWidgets('späte Bluetooth-Antwort überschreibt keinen neuen Stand', (
    t,
  ) async {
    final answer = Completer<bool>();
    final sensor = _ScriptedSensor();
    sensor.plans['g1'] = [_failing];
    final r = _Rig(sensor: sensor, bluetoothAvailable: () => answer.future);
    await r.open();
    await r.connect(t, 'g1');
    await t.pump();
    expect(r.manager.problem, SensorProblem.connectFailed);

    // Neuer Versuch gelingt und löscht den Hinweis; dann kommt die Antwort.
    await r.connect(t, 'g1');
    expect(r.manager.problem, isNull);
    answer.complete(false);
    await t.pump();
    expect(r.manager.problem, isNull);
    expect(r.sensor.connectedIds, {'g1'});
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
