import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_ppg_panel.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/resting_measure_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Signal am Ende der Ruhephase', () {
    final calls = <String>[];
    const channel = MethodChannel(restingSignalChannelName);
    Object? failure;

    setUp(() {
      calls.clear();
      failure = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            calls.add(c.method);
            if (failure != null) throw failure!;
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('Ton an: Ton über den Kanal, keine Vibration', () async {
      await SystemRestingSignal(ValueNotifier(true)).restEnded();
      expect(calls, ['tone']);
    });

    test('Ton aus: Vibration über den Kanal, kein Ton', () async {
      await SystemRestingSignal(ValueNotifier(false)).restEnded();
      expect(calls, ['vibrate']);
    });

    test('liest den Schalter bei jedem Signal neu', () async {
      final on = ValueNotifier(true);
      final s = SystemRestingSignal(on);
      await s.restEnded();
      on.value = false;
      await s.restEnded();
      expect(calls, ['tone', 'vibrate']);
    });

    test('Fehler des Kanals werden verschluckt', () async {
      failure = PlatformException(code: 'signal_failed');
      await SystemRestingSignal(ValueNotifier(true)).restEnded();
      expect(calls, ['tone']);
    });

    test('fehlender Kanal (kein Handler) wird verschluckt', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await SystemRestingSignal(ValueNotifier(false)).restEnded();
    });

    test('Kanalname und Methoden stimmen mit RestingSignal.kt überein', () {
      final kt = File(
        'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/RestingSignal.kt',
      ).readAsStringSync();
      expect(kt, contains('"$restingSignalChannelName"'));
      expect(kt, contains('"tone" ->'));
      expect(kt, contains('"vibrate" ->'));
    });
  });

  group('Debug-Panel der Fake-Kamera', () {
    testWidgets('Szenario und Zeitraffer wählbar, Kennungen für UI Automator', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final cam = DebugTestPpgCamera();
      await tester.pumpWidget(
        DebugPpgPanel(camera: cam, child: const SizedBox.expand()),
      );
      expect(find.text('PPG weakSignal'), findsNothing);
      await tester.tap(find.text('PPG'));
      await tester.pump();
      for (final s in DebugPpgScenario.values) {
        expect(find.text('PPG ${s.name}'), findsOneWidget);
      }
      expect(
        find.bySemanticsIdentifier('debug_ppg_weakSignal'),
        findsOneWidget,
      );
      await tester.tap(find.text('PPG weakSignal'));
      await tester.pump();
      expect(cam.scenario, DebugPpgScenario.weakSignal);
      await tester.tap(find.text('PPG noCamera'));
      await tester.pump();
      expect(cam.scenario, DebugPpgScenario.noCamera);
      expect(cam.speed, 1);
      await tester.tap(find.text('PPG Zeitraffer aus'));
      await tester.pump();
      expect(cam.speed, greaterThan(1));
      handle.dispose();
    });
  });
}
