import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/services.dart';

/// Kanalnamen zu `GpsStreamHandler.kt` und `MainActivity.kt`; dieselben
/// Zeichenketten stehen dort (ein Test prüft das).
const String locationStreamChannelName = 'ramuri/location_stream';

/// Zugriff (Berechtigung, GPS-Schalter) läuft über den Berechtigungskanal.
const String locationAccessChannelName = 'ramuri/permissions';

/// Takt der Standortabfrage in Millisekunden (OQ-0064: einmal je Sekunde).
/// Steht auch in `GpsStreamHandler.kt` (`INTERVAL_MS`).
const int locationIntervalMs = 1000;

/// [LocationSource] über `LocationManager.GPS_PROVIDER` (eigener Kotlin-Code,
/// keine Play-Dienste). Kotlin liefert Rohwerte samt `has*`-Flags; ob ein Wert
/// fehlt, entscheidet allein [decodeLocationEvent].
class MethodChannelLocationSource implements LocationSource {
  MethodChannelLocationSource([EventChannel? channel])
    : _channel = channel ?? const EventChannel(locationStreamChannelName);

  final EventChannel _channel;

  @override
  Stream<LocationSample> samples() {
    // Ein Fehler im Strom bleibt ein Fehlerereignis; der Strom läuft weiter.
    return Stream.eventTransformed(
      _channel.receiveBroadcastStream(<String, Object?>{
        'intervalMs': locationIntervalMs,
      }),
      (sink) => _Decoder(sink),
    );
  }
}

class _Decoder implements EventSink<dynamic> {
  _Decoder(this._out);
  final EventSink<LocationSample> _out;

  @override
  void add(dynamic event) {
    try {
      _out.add(decodeLocationEvent(event));
    } on FormatException catch (_) {
      _out.addError(const LocationSourceFailure(LocationFailureReason.other));
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    final reason = error is PlatformException
        ? switch (error.code) {
            'permission_denied' => LocationFailureReason.permissionDenied,
            'provider_disabled' => LocationFailureReason.providerDisabled,
            _ => LocationFailureReason.other,
          }
        : LocationFailureReason.other;
    // Nur der Grund, keine Plattformmeldung (kann Koordinaten enthalten).
    _out.addError(LocationSourceFailure(reason), stackTrace);
  }

  @override
  void close() => _out.close();
}

/// Wandelt ein Kotlin-Ereignis in einen Punkt. Pflicht: `timeMs`, `lat`,
/// `lon`; sonst [FormatException]. Optionale Werte sind `null`, wenn das
/// zugehörige `has*`-Flag nicht `true` ist oder der Wert nicht endlich ist.
LocationSample decodeLocationEvent(Object? event) {
  if (event is! Map) throw const FormatException('kein Standortereignis');
  double? optional(String key, String flag) {
    if (event[flag] != true) return null;
    final v = event[key];
    return v is num && v.isFinite ? v.toDouble() : null;
  }

  final time = event['timeMs'];
  final lat = event['lat'];
  final lon = event['lon'];
  if (time is! int ||
      lat is! num ||
      lon is! num ||
      !lat.isFinite ||
      !lon.isFinite) {
    throw const FormatException('Standortereignis unvollständig');
  }
  final age = event['ageMs'];
  return LocationSample(
    time: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
    ageMs: age is int ? age : null,
    latitude: lat.toDouble(),
    longitude: lon.toDouble(),
    accuracyMeters: optional('accuracy', 'hasAccuracy'),
    altitudeMeters: optional('altitude', 'hasAltitude'),
    speedMetersPerSecond: optional('speed', 'hasSpeed'),
    speedAccuracyMetersPerSecond: optional('speedAccuracy', 'hasSpeedAccuracy'),
    verticalAccuracyMeters: optional('verticalAccuracy', 'hasVerticalAccuracy'),
  );
}

/// [LocationAccessPort] über den Berechtigungskanal (`ramuri/permissions`).
class MethodChannelLocationAccess implements LocationAccessPort {
  MethodChannelLocationAccess([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(locationAccessChannelName);

  final MethodChannel _channel;

  LocationAccess _parse(String? s) => switch (s) {
    'precise' => LocationAccess.precise,
    'approximate' => LocationAccess.approximateOnly,
    // Unbekannt gilt als verweigert: im Zweifel kein Start.
    _ => LocationAccess.denied,
  };

  @override
  Future<LocationAccess> access() async =>
      _parse(await _channel.invokeMethod<String>('locationAccess'));

  @override
  Future<LocationAccess> request() async =>
      _parse(await _channel.invokeMethod<String>('requestLocation'));

  @override
  Future<bool> gpsEnabled() async =>
      await _channel.invokeMethod<bool>('gpsEnabled') ?? false;
}
