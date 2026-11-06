import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/method_channel_recording_service.dart';
import 'package:running_app/features/run/run_ports.dart';

import 'app_harness.dart';

Finder key(String k) => find.byKey(Key(k));

Future<void> openRun(Device d, WidgetTester tester) async {
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
}

const _kt = 'android/app/src/main/kotlin/io/github/brokoskokoli/running_app';

void main() {
  group('Banner Dienststart (WP08)', () {
    testWidgets('Dienst scheitert: Banner sichtbar, Lauf läuft', (
      tester,
    ) async {
      final d = Device()
        ..recordingService = FakeRecordingServicePort(
          startError: StateError('abgelehnt'),
        );
      await openRun(d, tester);
      expect(key('run_banner_service'), findsOneWidget);
      expect(key('run_pause'), findsOneWidget);
    });

    testWidgets('Dienst läuft: kein Banner', (tester) async {
      final d = Device()..recordingService = FakeRecordingServicePort();
      await openRun(d, tester);
      expect(key('run_pause'), findsOneWidget);
      expect(key('run_banner_service'), findsNothing);
    });
  });

  group('POST_NOTIFICATIONS (ADR-0005 Punkt 2)', () {
    testWidgets('wird vor dem Dienststart gefragt', (tester) async {
      final order = <String>[];
      final service = FakeRecordingServicePort();
      final d = Device()
        ..recordingService = service
        ..requestNotifications = () async {
          order.add('ask:${service.startCalls}');
        };
      await openRun(d, tester);
      expect(order, ['ask:0']);
      expect(service.startCalls, 1);
    });

    testWidgets('Fehler der Abfrage blockiert den Lauf nicht', (tester) async {
      final d = Device()
        ..recordingService = FakeRecordingServicePort()
        ..requestNotifications = () async => throw StateError('detached');
      await openRun(d, tester);
      expect(key('run_pause'), findsOneWidget);
      expect(await d.session.runs.list(), hasLength(1));
    });

    testWidgets('Antwort erst nach resumed: genau kein Start, Tippen startet', (
      tester,
    ) async {
      final answer = Completer<void>();
      final service = FakeRecordingServicePort();
      final d = Device()
        ..recordingService = service
        ..requestNotifications = () => answer.future;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      await tester.tap(key('home_start_run'));
      await tester.pump();
      await tester.pump();
      // Systemdialog offen: Die App geht in den Hintergrund und kommt zurück,
      // bevor die Antwort ankommt. resumed liest den Stand neu (Generation).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(key('run_start_ready'), findsOneWidget);
      answer.complete();
      await tester.pumpAndSettle();
      // Die späte Antwort startet keinen zweiten Weg.
      expect(key('run_start_ready'), findsOneWidget);
      expect(key('run_pause'), findsNothing);
      expect(service.startCalls, 0);
      expect(await d.session.runs.list(), isEmpty);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
      expect(service.startCalls, 1);
      expect(await d.session.runs.list(), hasLength(1));
    });

    test(
      'Kanal: abgelehnt ist false, erteilt true; Kotlin kennt die Methode',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('running_app/permissions');
        String? answer;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'requestNotifications');
          return answer;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        answer = 'denied';
        expect(await requestNotificationPermission(), isFalse);
        answer = 'granted';
        expect(await requestNotificationPermission(), isTrue);
        final kt = File('$_kt/MainActivity.kt').readAsStringSync();
        expect(kt, contains('"requestNotifications"'));
        expect(kt, contains('Manifest.permission.POST_NOTIFICATIONS'));
      },
    );
  });
}
