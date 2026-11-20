import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_ppg_panel.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/resting_measure_launcher.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

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

  group('Laufende Signalanzeige im Messbildschirm (PAR-234)', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    Future<void> tap(WidgetTester tester, String key) async {
      final f = find.byKey(Key(key));
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await settle(tester);
    }

    testWidgets('sauberes Signal 60/min, echte Auswertung: „Signal gut“', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = (await tester.runAsync(
        () => FakeStorage().open(testKey),
      ))!;
      final clock = FakeClock(DateTime.utc(2026, 11, 10, 12));
      final cam = HoldingCamera();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: RamuriTheme.light,
          home: RestingMeasureHost(
            camera: cam,
            profile: ProfileService(
              session.profile,
              clock,
              settings: session.settings,
            ),
            settings: session.settings,
            clock: clock,
            evaluate: (f, w) async => evaluatePpg(f, window: w),
          ),
        ),
      );
      await settle(tester);
      await tap(tester, 'measure_mode_now');
      await tap(tester, 'measure_start');
      final src = PulseSource.bpm(60);
      final shown = <String>[];
      for (var s = 1; s <= 20; s++) {
        while (true) {
          final f = src.next();
          cam.emitFrame(f);
          if (f.t >= s) break;
        }
        await settle(tester);
        if (s >= 10) {
          shown.add(
            tester.widget<Text>(find.byKey(const Key('measure_signal'))).data!,
          );
        }
      }
      expect(shown, everyElement('Signal gut'));
      expect(find.text('Signal eingeschränkt'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  });
}
