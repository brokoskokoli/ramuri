import 'package:flutter/services.dart';

import 'run_ports.dart';

/// Kanalname zu `RecordingServiceState.kt` (`CHANNEL`); dieselbe Zeichenkette
/// steht dort (ein Test prüft das).
const String recordingServiceChannelName = 'ramuri/recording_service';

/// [RecordingServicePort] über den Kotlin-Dienst. Der Kanal hängt an der
/// Engine der Application, also auch ohne Activity erreichbar.
class MethodChannelRecordingService implements RecordingServicePort {
  MethodChannelRecordingService([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(recordingServiceChannelName);

  final MethodChannel _channel;

  /// Kehrt zurück, sobald der Dienst `startForeground` erreicht hat; sonst
  /// eine [PlatformException] (`start_failed`, Detail: Klassenname des Fehlers).
  @override
  Future<void> start() => _channel.invokeMethod<void>('start');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<bool> isRunning() async =>
      await _channel.invokeMethod<bool>('isRunning') ?? false;

  @override
  Future<bool> updateType() async =>
      await _channel.invokeMethod<bool>('updateType') ?? false;
}

/// Fragt ACTIVITY_RECOGNITION über den Berechtigungskanal (`MainActivity.kt`,
/// FR-0202). Liefert, ob der Schrittsensor jetzt nutzbar ist; Ablehnung oder
/// fehlender Sensor sind kein Fehler.
Future<bool> requestActivityRecognitionPermission([
  MethodChannel? channel,
]) async {
  final c = channel ?? const MethodChannel('ramuri/permissions');
  return await c.invokeMethod<String>('requestActivityRecognition') ==
      'available';
}

/// Fragt POST_NOTIFICATIONS über den Berechtigungskanal (`MainActivity.kt`,
/// ADR-0005 Punkt 2). Liefert, ob erteilt; Ablehnung ist kein Fehler.
Future<bool> requestNotificationPermission([MethodChannel? channel]) async {
  final c = channel ?? const MethodChannel('ramuri/permissions');
  return await c.invokeMethod<String>('requestNotifications') == 'granted';
}
