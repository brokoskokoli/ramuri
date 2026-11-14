import 'package:flutter/services.dart';

/// Hersteller und Modell des Geräts (`Build.MANUFACTURER`, `Build.MODEL`) für
/// die Morgenmessung (FR-0215, PAR-160K: neue Reihe bei neuem Gerät). Keine
/// Seriennummer, keine Kennung.
typedef DeviceInfo = ({String manufacturer, String model});

/// Quelle der Geräteangabe; Tests setzen eine feste.
typedef DeviceInfoReader = Future<DeviceInfo> Function();

/// Liest die Angabe über den Berechtigungskanal (`MainActivity.kt`, Methode
/// `deviceInfo`). Ohne Plattform oder bei Fehler leer: Hersteller und Modell
/// dürfen leer gespeichert werden, die Messung scheitert daran nicht.
Future<DeviceInfo> readDeviceInfo([MethodChannel? channel]) async {
  final c = channel ?? const MethodChannel('ramuri/permissions');
  try {
    final m = await c.invokeMapMethod<String, dynamic>('deviceInfo');
    return (manufacturer: _text(m?['manufacturer']), model: _text(m?['model']));
  } on Object {
    // PlatformException, MissingPluginException und unerwartete Typen der
    // Plattform (TypeError): leere Angaben, die Messung scheitert nicht daran.
    return (manufacturer: '', model: '');
  }
}

String _text(Object? v) => v is String ? v : '';
