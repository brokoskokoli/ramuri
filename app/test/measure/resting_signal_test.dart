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

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (c) async {
            if (c.method == 'SystemSound.play') calls.add('ton ${c.arguments}');
            if (c.method == 'HapticFeedback.vibrate') calls.add('vibration');
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('Ton an: Systemton, keine Vibration', () async {
      await SystemRestingSignal(ValueNotifier(true)).restEnded();
      expect(calls, ['ton SystemSoundType.alert']);
    });

    test('Ton aus: Vibration, kein Ton', () async {
      await SystemRestingSignal(ValueNotifier(false)).restEnded();
      expect(calls, ['vibration']);
    });

    test('liest den Schalter bei jedem Signal neu', () async {
      final on = ValueNotifier(true);
      final s = SystemRestingSignal(on);
      await s.restEnded();
      on.value = false;
      await s.restEnded();
      expect(calls, ['ton SystemSoundType.alert', 'vibration']);
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
