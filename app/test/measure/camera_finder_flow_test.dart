import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/camera_finder_screen.dart';
import 'package:running_app/features/measure/morning_launcher.dart';
import 'package:running_app/features/measure/resting_measure_launcher.dart';
import 'package:running_app/features/profile/profile_screen.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// Kamerasuche vor der ersten Kamera-Messung (FR-0220) über die echten Startwege: Ruhepuls aus
// dem Profil (FR-0214) und Morgenmessung über ihren Host (FR-0215). Debug-Quelle mit zwei
// nutzbaren Kameras (Standardkamera „kein Finger“, zweite „Finger“) und einer ohne Blitz.
// Erfundene Kameras und Werte.

const _std = PpgCameraRef('0');
const _second = PpgCameraRef('0', '2');

Future<PpgMeasurement> _good(List<PpgFrame> f, PpgWindow w) async =>
    const PpgMeasurement(
      quality: PpgQuality.good,
      reasons: [],
      bpm: 52.4,
      rmssdMs: 40,
    );

class _Env {
  _Env(this.session, this.clock, this.cam);

  final StorageSession session;
  final FakeClock clock;
  final PpgCamera cam;

  SettingsPpgCameraChoiceStore get choice =>
      SettingsPpgCameraChoiceStore(session.settings, clock);

  DebugTestPpgCamera get debug => cam as DebugTestPpgCamera;

  static Future<_Env> make(
    WidgetTester t, {
    PpgCamera? camera,
    bool developerMode = false,
    PpgCameraRef? manual,
    PpgCameraRef? auto,
  }) async {
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final clock = FakeClock(DateTime.utc(2026, 11, 24, 6));
    final session = (await t.runAsync(() async {
      final s = await FakeStorage().open(testKey);
      await s.profile.save(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
      );
      await SettingsDeveloperModeStore(s.settings, clock).set(developerMode);
      final choice = SettingsPpgCameraChoiceStore(s.settings, clock);
      await choice.setManual(manual);
      await choice.setAuto(auto);
      return s;
    }))!;
    final cam =
        camera ??
        (DebugTestPpgCamera(wallClock: () => Duration.zero)
          ..setScenario(_std, DebugPpgScenario.noFinger)
          ..setScenario(_second, DebugPpgScenario.goodPulse));
    return _Env(session, clock, cam);
  }

  Future<void> pumpApp(WidgetTester t, Widget home) async {
    await t.pumpWidget(
      PpgCameraScope(
        camera: cam,
        evaluate: _good,
        child: MaterialApp(
          theme: RamuriTheme.light,
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await _settle(t);
  }

  Future<void> pumpProfile(WidgetTester t) async {
    final recalc = RecalculationController(
      RecalculationService(
        session: session,
        clock: clock,
        calculation: ValueCalculationService(
          algorithms: AlgorithmRegistry.standard(),
          session: session,
          clock: clock,
        ),
      ),
    );
    addTearDown(recalc.dispose);
    await pumpApp(
      t,
      ProfileScreen(session: session, clock: clock, recalculation: recalc),
    );
  }

  Future<void> pumpMorning(WidgetTester t) => pumpApp(
    t,
    MorningMeasureHost(
      camera: cam,
      store: (session as MorningStorage).morning,
      settings: session.settings,
      clock: clock,
      evaluate: _good,
    ),
  );

  Future<T> read<T>(WidgetTester t, Future<T> Function() f) async =>
      (await t.runAsync(f)) as T;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>(() {}));
    await t.pump();
  }
  // Ein Takt der Vorschau (Debug-Quelle: 0,1 s).
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
  if (key.startsWith('camera_finder_')) {
    // Vorschau endet (letzter Takt der Debug-Quelle), dann schließt die Seite.
    await t.pump(const Duration(seconds: 1));
    await _settle(t);
  }
}

/// Ruhepuls aus dem Profil öffnen und „sofort messen“ starten.
Future<void> _startResting(WidgetTester t) async {
  await _tap(t, 'profile_resting_measure');
  await _tap(t, 'measure_mode_now');
  await _tap(t, 'measure_start');
}

/// Laufende Messung abbrechen und die Seite schließen; Taktgeber der Debug-Quelle auslaufen
/// lassen.
Future<void> _cancel(WidgetTester t) async {
  await _tap(t, 'measure_cancel');
  if (find.byKey(const Key('measure_back')).evaluate().isNotEmpty) {
    await _tap(t, 'measure_back');
  }
  await t.pump(const Duration(seconds: 1));
}

/// Zurück des Systems (schließt die Kamerasuche).
Future<void> _back(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await _settle(t);
  await t.pump(const Duration(seconds: 1));
}

/// Baum abbauen und Taktgeber auslaufen lassen.
Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

final _finder = find.byType(CameraFinderScreen);

void main() {
  testWidgets(
    'erste Ruhepulsmessung: Seite, Empfehlung zweite Kamera, „Weiter“ '
    'misst mit ihr; zweite Messung ohne Seite',
    (t) async {
      final e = await _Env.make(t);
      await e.pumpProfile(t);
      await _startResting(t);
      expect(_finder, findsOneWidget);
      expect(e.debug.startedCameras, isEmpty);
      expect(
        find.text(
          'Dein Handy hat mehrere Kameras. Lege den Finger über Blitz und '
          'Kamera – die beleuchtete Kamera ist markiert.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(CameraFinderScreen.recommendedKey(_second)), findsOne);
      // Ohne Entwicklermodus keine Zahlen je Kamera.
      expect(find.byKey(CameraFinderScreen.numbersKey(_second)), findsNothing);
      expect(find.text('Weiter'), findsOneWidget);
      await _tap(t, 'camera_finder_apply');
      expect(_finder, findsNothing);
      expect(e.debug.startedCameras, [_second]);
      expect(await e.read(t, e.choice.readAuto), _second);
      await _cancel(t);

      // Zweite Messung: keine Seite, wieder die zweite Kamera.
      await _startResting(t);
      expect(_finder, findsNothing);
      expect(e.debug.startedCameras, [_second, _second]);
      await _cancel(t);
    },
  );

  testWidgets('erste Morgenmessung: Seite vor der Ruhephase; Zeit darin zählt '
      'nicht, Ruhephase danach mit voller Dauer', (t) async {
    final e = await _Env.make(t);
    await e.pumpMorning(t);
    await _tap(t, 'morning_start');
    expect(_finder, findsOneWidget);
    expect(find.byKey(const Key('measure_rest_clock')), findsNothing);
    // 90 s auf der Seite.
    e.clock.advance(const Duration(seconds: 90));
    await _tap(t, 'camera_finder_apply');
    expect(_finder, findsNothing);
    await t.pump(const Duration(seconds: 1));
    expect(
      t.widget<Text>(find.byKey(const Key('measure_rest_clock'))).data,
      '2:00',
    );
    expect(e.debug.startedCameras, isEmpty);
    await _tap(t, 'morning_skip_rest');
    expect(e.debug.startedCameras, [_second]);
    await _cancel(t);
  });

  group('keine Seite', () {
    testWidgets('nur eine nutzbare Kamera', (t) async {
      final e = await _Env.make(t, camera: FakePpgCamera());
      await e.pumpProfile(t);
      await _startResting(t);
      expect(_finder, findsNothing);
      expect((e.cam as FakePpgCamera).startedWith, [null]);
      await _cancel(t);
    });

    testWidgets('gültiges Suchergebnis', (t) async {
      final e = await _Env.make(t, auto: _std);
      await e.pumpProfile(t);
      await _startResting(t);
      expect(_finder, findsNothing);
      expect(e.debug.startedCameras, [_std]);
      await _cancel(t);
    });

    testWidgets('Entwicklermodus mit gültiger Wahl von Hand', (t) async {
      final e = await _Env.make(t, developerMode: true, manual: _second);
      await e.pumpMorning(t);
      await _tap(t, 'morning_start');
      expect(_finder, findsNothing);
      await _tap(t, 'morning_skip_rest');
      expect(e.debug.startedCameras, [_second]);
      await _cancel(t);
    });
  });

  testWidgets('Wahl von Hand ohne Entwicklermodus verhindert die Seite nicht', (
    t,
  ) async {
    final e = await _Env.make(t, manual: _second);
    await e.pumpProfile(t);
    await _startResting(t);
    expect(_finder, findsOneWidget);
    await _back(t);
    await _tap(t, 'measure_back');
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Suchergebnis auf eine verschwundene Kamera: Seite erscheint '
      'wieder', (t) async {
    final e = await _Env.make(t, auto: const PpgCameraRef('7'));
    await e.pumpProfile(t);
    await _startResting(t);
    expect(_finder, findsOneWidget);
    await _tap(t, 'camera_finder_apply');
    expect(e.debug.startedCameras, [_second]);
    expect(await e.read(t, e.choice.readAuto), _second);
    await _cancel(t);
  });

  testWidgets('ohne Empfehlung: „Standardkamera verwenden“ speichert sie und '
      'misst; danach keine Seite mehr', (t) async {
    final e = await _Env.make(t);
    e.debug.setScenario(_second, DebugPpgScenario.noFinger);
    await e.pumpProfile(t);
    await _startResting(t);
    expect(_finder, findsOneWidget);
    expect(find.byKey(const Key('camera_finder_apply')), findsNothing);
    await _tap(t, 'camera_finder_default');
    expect(_finder, findsNothing);
    expect(e.debug.startedCameras, [_std]);
    expect(await e.read(t, e.choice.readAuto), _std);
    await _cancel(t);
    await _startResting(t);
    expect(_finder, findsNothing);
    expect(e.debug.startedCameras, [_std, _std]);
    await _cancel(t);
  });

  testWidgets('Zurück: keine Messung, nichts gespeichert, Taschenlampe aus; '
      'nächster Start zeigt die Seite', (t) async {
    final e = await _Env.make(t);
    await e.pumpMorning(t);
    await _tap(t, 'morning_start');
    expect(_finder, findsOneWidget);
    expect(e.debug.torchOn, isTrue);
    await t.tap(find.byKey(CameraFinderScreen.tileKey(_second)));
    await t.pump();
    await _back(t);
    expect(_finder, findsNothing);
    expect(e.debug.torchOn, isFalse);
    expect(e.debug.previewOn, isFalse);
    expect(e.debug.startedCameras, isEmpty);
    expect(find.byKey(const Key('measure_rest_clock')), findsNothing);
    expect(find.byKey(const Key('morning_start')), findsOneWidget);
    expect(await e.read(t, e.choice.readAuto), isNull);
    expect(await e.read(t, e.choice.readManual), isNull);
    await _tap(t, 'morning_start');
    expect(_finder, findsOneWidget);
    await _back(t);
    await _end(t);
  });

  testWidgets('Hintergrund: keine Messung, nichts gespeichert, Taschenlampe '
      'aus; zurück im Vordergrund wieder die Seite', (t) async {
    final e = await _Env.make(t);
    await e.pumpProfile(t);
    await _startResting(t);
    expect(_finder, findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(t);
    await t.pump(const Duration(seconds: 1));
    expect(e.debug.torchOn, isFalse);
    expect(e.debug.previewOn, isFalse);
    expect(e.debug.startedCameras, isEmpty);
    expect(await e.read(t, e.choice.readAuto), isNull);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(t);
    expect(_finder, findsOneWidget);
    expect(e.debug.previewOn, isTrue);
    expect(e.debug.startedCameras, isEmpty);
    await _back(t);
    await _end(t);
  });
}
