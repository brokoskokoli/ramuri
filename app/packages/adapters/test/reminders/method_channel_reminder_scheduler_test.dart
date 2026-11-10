import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(reminderChannelName);

  late List<MethodCall> calls;
  late List<MethodCall> permissionCalls;
  Object? Function(MethodCall) answer = (_) => null;
  Object? permissionAnswer = 'granted';

  setUp(() {
    calls = [];
    permissionCalls = [];
    answer = (_) => null;
    permissionAnswer = 'granted';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
    messenger.setMockMethodCallHandler(permissionChannel, (call) async {
      permissionCalls.add(call);
      return permissionAnswer;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(permissionChannel, null);
  });

  final at = DateTime.utc(2026, 11, 10, 16, 30);
  final reminder = ScheduledReminder(at: at, kind: 'long');
  const labels = ReminderLabels(
    channelName: 'Trainingserinnerungen',
    title: 'Geplantes Training',
    bodies: {'long': 'Langer Lauf um 18:00'},
  );

  test('replaceAll sendet je Erinnerung nur Zeitpunkt in ms und '
      'Art-Schlüssel, die Texte getrennt', () async {
    await MethodChannelReminderScheduler().replaceAll([
      reminder,
    ], labels: labels);
    final c = calls.single;
    expect(c.method, 'replaceAll');
    final args = c.arguments as Map;
    expect(args['labels'], {
      'channelName': 'Trainingserinnerungen',
      'title': 'Geplantes Training',
      'bodies': {'long': 'Langer Lauf um 18:00'},
    });
    expect(args['reminders'], [
      {'at': at.millisecondsSinceEpoch, 'kind': 'long'},
    ]);
  });

  test('cancelAll und debugAdd', () async {
    final s = MethodChannelReminderScheduler();
    await s.cancelAll();
    await s.debugAdd(reminder, labels: labels);
    expect(calls.map((c) => c.method), ['cancelAll', 'debugAdd']);
    final args = calls.last.arguments as Map;
    expect((args['labels'] as Map)['channelName'], 'Trainingserinnerungen');
    expect(args['reminder'], {'at': at.millisecondsSinceEpoch, 'kind': 'long'});
  });

  test('permitted liest nur, ohne Antwort: nicht erlaubt', () async {
    answer = (_) => true;
    expect(await MethodChannelReminderScheduler().permitted(), isTrue);
    answer = (_) => null;
    expect(await MethodChannelReminderScheduler().permitted(), isFalse);
    expect(calls.map((c) => c.method), ['permitted', 'permitted']);
    expect(permissionCalls, isEmpty);
  });

  test('requestPermission fragt über den Kanal der Berechtigungen', () async {
    expect(await MethodChannelReminderScheduler().requestPermission(), isTrue);
    permissionAnswer = 'denied';
    expect(await MethodChannelReminderScheduler().requestPermission(), isFalse);
    expect(permissionCalls.map((c) => c.method), [
      'requestNotifications',
      'requestNotifications',
    ]);
    expect(calls, isEmpty);
  });

  test('Kanalname, Methoden und Schlüssel stehen gleich in Kotlin', () {
    const dir =
        '../../android/app/src/main/kotlin/io/github/brokoskokoli/ramuri';
    final kt = File('$dir/TrainingReminders.kt').readAsStringSync();
    expect(kt, contains('"$reminderChannelName"'));
    for (final m in [
      'permitted',
      'replaceAll',
      'cancelAll',
      'debugAdd',
      'labels',
      'channelName',
      'reminders',
      'reminder',
      'at',
      'kind',
      'title',
      'bodies',
    ]) {
      expect(kt, contains('"$m"'), reason: m);
    }
    // Prozessweit registriert (ohne Activity), inexakt, ohne Netz.
    final app = File('$dir/RunningApplication.kt').readAsStringSync();
    expect(app, contains('TrainingReminders.register('));
    expect(kt, contains('setAndAllowWhileIdle'));
    expect(kt, isNot(contains('setExact')));
    expect(kt, isNot(contains('java.net')));
    final manifest = File('../../android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('RECEIVE_BOOT_COMPLETED'));
    expect(manifest, isNot(contains('permission.SCHEDULE_EXACT_ALARM')));
    expect(manifest, isNot(contains('permission.USE_EXACT_ALARM')));
    expect(manifest, contains('.TrainingReminderReceiver'));
  });
}
