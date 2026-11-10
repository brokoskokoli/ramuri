import 'package:core/core.dart';
import 'package:flutter/services.dart';

import '../permissions/method_channel_permission_status.dart';

/// Name des prozessweiten Kanals der Erinnerungen; dieselbe Zeichenkette
/// steht in `TrainingReminders.kt` (der Test prüft das).
const String reminderChannelName = 'ramuri/reminders';

/// [ReminderScheduler] über einen eigenen Plattformaufruf (kein Paket,
/// FR-0174): Wecker des Systems inexakt, eigener Benachrichtigungskanal,
/// Neuplanung nach Geräteneustart in Kotlin, kein Netz.
///
/// Die Berechtigung (POST_NOTIFICATIONS) fragt der vorhandene Kanal der
/// Berechtigungen an der Activity an (`requestNotifications`).
class MethodChannelReminderScheduler implements ReminderScheduler {
  MethodChannelReminderScheduler({
    MethodChannel? channel,
    MethodChannel? permissions,
  }) : _channel = channel ?? const MethodChannel(reminderChannelName),
       _permissions = permissions ?? permissionChannel;

  final MethodChannel _channel;
  final MethodChannel _permissions;

  @override
  Future<bool> permitted() async =>
      await _channel.invokeMethod<bool>('permitted') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _permissions.invokeMethod<String>('requestNotifications') ==
      'granted';

  @override
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required ReminderLabels labels,
  }) => _channel.invokeMethod<void>('replaceAll', {
    'labels': _labels(labels),
    'reminders': [for (final r in reminders) _encode(r)],
  });

  @override
  Future<void> cancelAll() => _channel.invokeMethod<void>('cancelAll');

  /// Nur für den Debug-Einstieg (`main_debug.dart`, E2E-Test): plant
  /// [reminder] zusätzlich zu den geplanten über denselben Weg (Wecker,
  /// Empfänger, Benachrichtigung). Kotlin nimmt den Aufruf nur in einer
  /// debugfähigen App an.
  Future<void> debugAdd(
    ScheduledReminder reminder, {
    required ReminderLabels labels,
  }) => _channel.invokeMethod<void>('debugAdd', {
    'labels': _labels(labels),
    'reminder': _encode(reminder),
  });

  /// Je Erinnerung nur Zeitpunkt und Art-Schlüssel (Kotlin legt sie außerhalb
  /// der verschlüsselten Datenbank ab, SEC-0009-Ausnahme WP22 Teil F).
  static Map<String, Object> _encode(ScheduledReminder r) => {
    'at': r.at.millisecondsSinceEpoch,
    'kind': r.kind,
  };

  static Map<String, Object> _labels(ReminderLabels l) => {
    'channelName': l.channelName,
    'title': l.title,
    'bodies': l.bodies,
  };
}
