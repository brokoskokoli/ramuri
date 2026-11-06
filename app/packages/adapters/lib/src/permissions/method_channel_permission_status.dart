import 'package:core/core.dart';
import 'package:flutter/services.dart';

/// Kanal zu `MainActivity` für den Stand der Berechtigungen.
const MethodChannel permissionChannel = MethodChannel(
  'running_app/permissions',
);

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

  @override
  Future<void> openSystemSettings() =>
      _channel.invokeMethod<void>('openAppSettings');
}
