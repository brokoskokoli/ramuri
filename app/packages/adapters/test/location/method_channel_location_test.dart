import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> full() => {
  'timeMs': 1893499200000, // 2030-01-01T12:00:00Z
  'ageMs': 250,
  'lat': 10.5,
  'lon': 20.25,
  'hasAccuracy': true,
  'accuracy': 4.0,
  'hasAltitude': true,
  'altitude': 123.0,
  'hasSpeed': true,
  'speed': 2.5,
  'hasSpeedAccuracy': true,
  'speedAccuracy': 0.5,
  'hasVerticalAccuracy': true,
  'verticalAccuracy': 3.0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('decodeLocationEvent', () {
    test('alle Werte vorhanden', () {
      final s = decodeLocationEvent(full());
      expect(s.time, DateTime.utc(2030, 1, 1, 12));
      expect(s.latitude, 10.5);
      expect(s.longitude, 20.25);
      expect(s.accuracyMeters, 4);
      expect(s.altitudeMeters, 123);
      expect(s.speedMetersPerSecond, 2.5);
      expect(s.speedAccuracyMetersPerSecond, 0.5);
      expect(s.verticalAccuracyMeters, 3);
      expect(s.ageMs, 250);
    });

    test('ageMs fehlt oder ist null: Alter ist null, nie 0', () {
      expect(decodeLocationEvent(full()..remove('ageMs')).ageMs, isNull);
      expect(decodeLocationEvent(full()..['ageMs'] = null).ageMs, isNull);
    });

    test(
      'has*-Flag false: Wert ist null, nie 0 (auch wenn Kotlin 0 liefert)',
      () {
        final e = full()
          ..['hasAccuracy'] = false
          ..['accuracy'] = 0.0
          ..['hasAltitude'] = false
          ..['altitude'] = 0.0
          ..['hasSpeed'] = false
          ..['speed'] = 0.0
          ..['hasSpeedAccuracy'] = false
          ..['speedAccuracy'] = 0.0
          ..['hasVerticalAccuracy'] = false
          ..['verticalAccuracy'] = 0.0;
        final s = decodeLocationEvent(e);
        expect(s.accuracyMeters, isNull);
        expect(s.altitudeMeters, isNull);
        expect(s.speedMetersPerSecond, isNull);
        expect(s.speedAccuracyMetersPerSecond, isNull);
        expect(s.verticalAccuracyMeters, isNull);
      },
    );

    test('jedes Flag wirkt nur auf seinen Wert', () {
      final s = decodeLocationEvent(full()..['hasSpeed'] = false);
      expect(s.speedMetersPerSecond, isNull);
      expect(s.speedAccuracyMetersPerSecond, 0.5);
      expect(s.accuracyMeters, 4);
    });

    test('Flag fehlt oder Wert nicht endlich: null', () {
      final e = full()
        ..remove('hasSpeedAccuracy')
        ..['speed'] = double.nan;
      final s = decodeLocationEvent(e);
      expect(s.speedAccuracyMetersPerSecond, isNull);
      expect(s.speedMetersPerSecond, isNull);
    });

    test('Pflichtfelder fehlen oder sind ungültig: FormatException', () {
      expect(() => decodeLocationEvent(null), throwsFormatException);
      expect(
        () => decodeLocationEvent(full()..remove('lat')),
        throwsFormatException,
      );
      expect(
        () => decodeLocationEvent(full()..['lon'] = double.nan),
        throwsFormatException,
      );
      expect(
        () => decodeLocationEvent(full()..['timeMs'] = '1'),
        throwsFormatException,
      );
    });
  });

  group('MethodChannelLocationSource', () {
    const channel = EventChannel(locationStreamChannelName);
    tearDown(() => messenger.setMockStreamHandler(channel, null));

    test('liefert Punkte, übergibt den Takt und beendet bei Abbruch', () async {
      Object? args;
      var cancelled = false;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (a, sink) {
            args = a;
            sink.success(full());
            sink.success(full()..['hasSpeed'] = false);
          },
          onCancel: (_) => cancelled = true,
        ),
      );
      final got = <LocationSample>[];
      final sub = MethodChannelLocationSource().samples().listen(got.add);
      await pumpEventQueue();
      expect(args, {'intervalMs': 1000});
      expect(got, hasLength(2));
      expect(got[0].speedMetersPerSecond, 2.5);
      expect(got[1].speedMetersPerSecond, isNull);
      await sub.cancel();
      await pumpEventQueue();
      expect(cancelled, isTrue);
    });

    test(
      'Fehlercodes werden zu LocationSourceFailure, Strom läuft weiter',
      () async {
        messenger.setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (a, sink) {
              sink.error(code: 'provider_disabled');
              sink.error(code: 'permission_denied', message: '10.5,20.25');
              sink.error(code: 'x');
              sink.success('kaputt');
              sink.success(full());
            },
          ),
        );
        final got = <Object>[];
        final sub = MethodChannelLocationSource().samples().listen(
          got.add,
          onError: got.add,
        );
        await pumpEventQueue();
        final reasons = got
            .whereType<LocationSourceFailure>()
            .map((e) => e.reason)
            .toList();
        expect(reasons, [
          LocationFailureReason.providerDisabled,
          LocationFailureReason.permissionDenied,
          LocationFailureReason.other,
          LocationFailureReason.other,
        ]);
        expect(got.last, isA<LocationSample>());
        // Keine Plattformmeldung im Fehlerobjekt (SEC: keine Koordinaten in Logs).
        expect(got.join(), isNot(contains('20.25')));
        await sub.cancel();
      },
    );
  });

  group('MethodChannelLocationAccess', () {
    const channel = MethodChannel(locationAccessChannelName);
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void answer(Map<String, Object?> byMethod) =>
        messenger.setMockMethodCallHandler(channel, (c) async {
          final v = byMethod[c.method];
          if (v is Exception) throw v;
          return v;
        });

    test('precise, approximate, denied und Unbekanntes', () async {
      final a = MethodChannelLocationAccess();
      answer({'locationAccess': 'precise', 'requestLocation': 'approximate'});
      expect(await a.access(), LocationAccess.precise);
      expect(await a.request(), LocationAccess.approximateOnly);
      answer({'locationAccess': 'denied', 'requestLocation': 'quatsch'});
      expect(await a.access(), LocationAccess.denied);
      expect(await a.request(), LocationAccess.denied);
      answer({});
      expect(await a.access(), LocationAccess.denied);
    });

    test('gpsEnabled: ohne Antwort false', () async {
      final a = MethodChannelLocationAccess();
      answer({'gpsEnabled': true});
      expect(await a.gpsEnabled(), isTrue);
      answer({});
      expect(await a.gpsEnabled(), isFalse);
    });

    test('Gate mit Adapter: ungefähr blockiert, genau erlaubt', () async {
      answer({'locationAccess': 'approximate', 'gpsEnabled': true});
      final gate = RecordingStartGate(MethodChannelLocationAccess());
      expect((await gate.check()).block, StartBlock.approximateOnly);
      answer({'locationAccess': 'precise', 'gpsEnabled': true});
      expect((await gate.check()).canStart, isTrue);
    });
  });

  test('Kanalnamen, Takt und Schlüssel stehen gleich in Dart und Kotlin', () {
    String read(String f) => File(
      '../../android/app/src/main/kotlin/io/github/brokoskokoli/running_app/$f',
    ).readAsStringSync();
    final main = read('MainActivity.kt');
    final gps = read('GpsStreamHandler.kt');
    expect(main, contains('"$locationStreamChannelName"'));
    expect(main, contains('"$locationAccessChannelName"'));
    expect(gps, contains('INTERVAL_MS = ${locationIntervalMs}L'));
    for (final key in full().keys) {
      expect(gps, contains('"$key"'), reason: key);
    }
    for (final m in ['locationAccess', 'requestLocation', 'gpsEnabled']) {
      expect(main, contains('"$m"'), reason: m);
    }
    for (final m in ['permission_denied', 'provider_disabled']) {
      expect(gps, contains('"$m"'), reason: m);
    }
  });
}
