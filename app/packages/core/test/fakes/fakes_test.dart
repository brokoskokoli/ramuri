import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2030, 1, 1, 12);

void main() {
  group('FakeClock', () {
    test('läuft nur auf Anweisung', () {
      final c = FakeClock(t0);
      expect(c.now(), t0);
      expect(c.now(), t0, reason: 'ohne advance keine Bewegung');
      c.advance(const Duration(minutes: 5));
      expect(c.now(), t0.add(const Duration(minutes: 5)));
      c.set(t0);
      expect(c.now(), t0);
    });
  });

  group('FakeLocationSource', () {
    test(
      'liefert Punkte samt fehlenden Angaben als null und Ausfall',
      () async {
        final s = FakeLocationSource();
        final got = <Object>[];
        final sub = s.samples().listen(got.add, onError: got.add);
        s.emit(LocationSample(time: t0, latitude: 1, longitude: 2));
        s.fail(StateError('Ausfall'));
        await Future<void>.delayed(Duration.zero);
        expect(got, hasLength(2));
        expect((got[0] as LocationSample).accuracyMeters, isNull);
        expect(got[1], isA<StateError>());
        await sub.cancel();
        expect(s.hasListeners, isFalse);
      },
    );
  });

  group('FakeHeartRateSensor', () {
    test('Werte tragen ihr Quellgerät, Geräte bleiben getrennt', () async {
      final s = FakeHeartRateSensor();
      final a = <HeartRateEvent>[];
      final b = <HeartRateEvent>[];
      final subA = s.connect('A').listen(a.add);
      final subB = s.connect('B').listen(b.add);
      s.emitReading('A', t0, 100);
      s.emitBattery('B', 50);
      await Future<void>.delayed(Duration.zero);
      expect(a.whereType<HeartRateReading>().single.beatsPerMinute, 100);
      expect(a.every((e) => e.deviceId == 'A'), isTrue);
      expect(b.whereType<HeartRateReading>(), isEmpty);
      expect(b.whereType<HeartRateBattery>().single.percent, 50);
      expect(s.connectedIds, {'A', 'B'});
      await subA.cancel();
      expect(s.connectedIds, {'B'}, reason: 'Abo beenden trennt');
      await subB.cancel();
    });

    test(
      'Abbruch meldet lost und schließt; Senden an Unverbundene scheitert',
      () async {
        final s = FakeHeartRateSensor();
        final events = <HeartRateEvent>[];
        var done = false;
        s.connect('A').listen(events.add, onDone: () => done = true);
        await s.drop('A');
        await Future<void>.delayed(Duration.zero);
        expect(events.last, isA<HeartRateDisconnected>());
        expect((events.last as HeartRateDisconnected).lost, isTrue);
        expect(done, isTrue);
        expect(() => s.emitReading('A', t0, 90), throwsStateError);
      },
    );

    test('Suche meldet entdeckte Geräte', () async {
      final s = FakeHeartRateSensor();
      final found = <HeartRateDevice>[];
      final sub = s.scan().listen(found.add);
      s.discover(const HeartRateDevice(id: 'X', name: 'Gurt'));
      await Future<void>.delayed(Duration.zero);
      expect(found.single.id, 'X');
      await sub.cancel();
    });
  });

  group('FakeCadenceSensor', () {
    test('liefert Werte nur bei Verfügbarkeit', () async {
      final s = FakeCadenceSensor();
      final got = <CadenceReading>[];
      final sub = s.readings().listen(got.add);
      s.emit(t0, 170);
      await Future<void>.delayed(Duration.zero);
      expect(got.single.stepsPerMinute, 170);
      await sub.cancel();

      final denied = FakeCadenceSensor(CadenceAvailability.permissionDenied);
      expect(await denied.availability(), CadenceAvailability.permissionDenied);
      expect(await denied.readings().toList(), isEmpty);
    });
  });

  group('FakeRecordingService', () {
    test(
      'Start ist idempotent, Zustände und Parameter werden gemeldet',
      () async {
        final s = FakeRecordingService();
        final states = <RecordingServiceState>[];
        s.states.listen(states.add);
        expect(await s.isRunning(), isFalse);
        await s.start(withConnectedDevice: true);
        await s.start(withConnectedDevice: false);
        expect(s.startCount, 1);
        expect(s.lastWithConnectedDevice, isTrue);
        expect(await s.isRunning(), isTrue);
        await s.stop();
        await s.stop();
        await Future<void>.delayed(Duration.zero);
        expect(states, [
          RecordingServiceState.running,
          RecordingServiceState.stopped,
        ]);
      },
    );

    test('Beenden durch die Plattform ist sichtbar', () async {
      final s = FakeRecordingService();
      await s.start(withConnectedDevice: false);
      s.killByPlatform();
      expect(await s.isRunning(), isFalse);
    });
  });

  group('FakeStorage', () {
    final k1 = Uint8List.fromList([1, 2, 3]);
    final k2 = Uint8List.fromList([9, 9, 9]);

    test('öffnet mit gleichem Schlüssel wieder, falscher scheitert', () async {
      final s = FakeStorage();
      final first = await s.open(k1);
      await first.close();
      await (await s.open(Uint8List.fromList([1, 2, 3]))).close();
      expect(
        () => s.open(k2),
        throwsA(
          isA<StorageException>().having(
            (e) => e.failure,
            'failure',
            StorageFailure.unreadable,
          ),
        ),
      );
    });

    test('ohne aktive Verschlüsselung wird nicht geöffnet', () async {
      final s = FakeStorage(encryptionActive: false);
      await expectLater(
        s.open(k1),
        throwsA(
          isA<StorageException>().having(
            (e) => e.failure,
            'failure',
            StorageFailure.encryptionNotActive,
          ),
        ),
      );
      expect(s.openSessions, 0);
    });

    test(
      'Sitzungen werden gezählt, doppeltes Schließen zählt einmal',
      () async {
        final s = FakeStorage();
        final a = await s.open(k1);
        expect(s.openSessions, 1);
        await a.close();
        await a.close();
        expect(s.openSessions, 0);
      },
    );
  });

  group('FakeKeyStore', () {
    test('speichert Kopien, liest null für Fehlendes, löscht', () async {
      final s = FakeKeyStore();
      expect(await s.read('k'), isNull);
      final v = Uint8List.fromList([1, 2]);
      await s.write('k', v);
      v[0] = 99;
      expect(await s.read('k'), [1, 2], reason: 'Kopie, nicht Verweis');
      await s.delete('k');
      expect(await s.read('k'), isNull);
    });

    test('Zugriffsfehler wird als KeyStoreException gemeldet', () async {
      final s = FakeKeyStore()..failWith = 'Keystore defekt';
      await expectLater(s.read('k'), throwsA(isA<KeyStoreException>()));
      await expectLater(
        s.write('k', Uint8List(1)),
        throwsA(isA<KeyStoreException>()),
      );
    });
  });

  group('FakeHealthConnect', () {
    test('meldet den eingestellten Zustand', () async {
      final h = FakeHealthConnect();
      expect(await h.availability(), HealthConnectAvailability.available);
      h.state = HealthConnectAvailability.updateRequired;
      expect(await h.availability(), HealthConnectAvailability.updateRequired);
    });
  });
}
