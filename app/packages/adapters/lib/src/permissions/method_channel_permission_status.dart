import 'package:core/core.dart';
import 'package:flutter/services.dart';

/// Name des Kanals zu `MainActivity`; dieselbe Zeichenkette steht in
/// `MainActivity.kt` (der Test prüft das).
const String permissionChannelName = 'ramuri/permissions';

/// Kanal zu `MainActivity` für den Stand der Berechtigungen.
const MethodChannel permissionChannel = MethodChannel(permissionChannelName);

/// [PermissionStatusPort] über einen eigenen Plattformaufruf (kein Paket).
class MethodChannelPermissionStatus implements PermissionStatusPort {
  MethodChannelPermissionStatus([MethodChannel? channel])
    : _channel = channel ?? permissionChannel;

  final MethodChannel _channel;

  /// Schlüssel im Ergebnis des Plattformaufrufs `status`.
  static const Map<AppPermission, String> keys = {
    AppPermission.location: 'location',
    AppPermission.bluetooth: 'bluetooth',
    AppPermission.activityRecognition: 'activity_recognition',
  };

  @override
  Future<Map<AppPermission, PermissionState>> status() async {
    final raw = await _channel.invokeMapMethod<String, String>('status');
    return {
      for (final p in AppPermission.values)
        p: switch (raw?[keys[p]]) {
          'granted' => PermissionState.granted,
          'denied' => PermissionState.denied,
          _ => PermissionState.unknown,
        },
    };
  }

  /// Plattformaufruf `requested`: Liste der Schlüssel aus [keys], deren
  /// Berechtigung das Manifest anfordert. Unbekannte Schlüssel entfallen.
  @override
  Future<Set<AppPermission>> requested() async {
    final raw = await _channel.invokeListMethod<String>('requested');
    return {
      for (final p in AppPermission.values)
        if (raw?.contains(keys[p]) ?? false) p,
    };
  }

  @override
  Future<void> openSystemSettings() =>
      _channel.invokeMethod<void>('openAppSettings');
}
