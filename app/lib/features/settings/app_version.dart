import 'package:flutter/services.dart';

/// Version der installierten App (`versionName (versionCode)`) über den
/// Berechtigungskanal (`MainActivity.kt`, Methode `appVersion`). Ohne Plattform
/// oder bei Fehler `null`; die Seite zeigt dann „unbekannt“.
Future<String?> readAppVersion([MethodChannel? channel]) async {
  final c = channel ?? const MethodChannel('ramuri/permissions');
  try {
    return await c.invokeMethod<String>('appVersion');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
