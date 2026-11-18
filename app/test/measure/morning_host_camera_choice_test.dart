import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_launcher.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// Kamerawahl der Morgenmessung (FR-0220) über den echten Startweg
// [MorningMeasureHost]: Start, Ruhephase überspringen, Kamera startet. Alle
// Kameras erfunden.

const _std = PpgCameraRef('0');
const _second = PpgCameraRef('0', '2');

const _cameras = [
  PpgCameraInfo(ref: _std, focalLengthMm: 5.4, isDefault: true),
  PpgCameraInfo(ref: _second, focalLengthMm: 2.2),
];

final _clock = FakeClock(DateTime.utc(2026, 11, 18, 5, 30));

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump();
  }
}

Future<void> _tap(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

/// Speichert Entwicklermodus und Wahl von Hand, öffnet den Host, startet die
/// Morgenmessung und gibt die Fake-Kamera zurück.
Future<FakePpgCamera> _measure(
  WidgetTester t, {
  required bool developerMode,
}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final session = await t.runAsync(() => FakeStorage().open(testKey));
  await t.runAsync(() async {
    await SettingsDeveloperModeStore(
      session!.settings,
      _clock,
    ).set(developerMode);
    await SettingsPpgCameraChoiceStore(
      session.settings,
      _clock,
    ).setManual(_second);
  });
  final cam = FakePpgCamera()..cameraList = _cameras;
  await t.pumpWidget(
    MaterialApp(
      theme: RamuriTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MorningMeasureHost(
        camera: cam,
        store: (session! as MorningStorage).morning,
        settings: session.settings,
        clock: _clock,
        evaluate: evalFinalOnly,
        autoTick: false,
      ),
    ),
  );
  await _settle(t);
  await _tap(t, 'morning_start');
  expect(cam.startCount, 0);
  await _tap(t, 'morning_skip_rest');
  return cam;
}

void main() {
  testWidgets('Entwicklermodus an: gewählte zweite Kamera wird gestartet', (
    t,
  ) async {
    final cam = await _measure(t, developerMode: true);
    expect(cam.startedWith, [_second]);
    await _tap(t, 'measure_cancel');
  });

  testWidgets('Entwicklermodus aus: Standardkamera ohne Angabe', (t) async {
    final cam = await _measure(t, developerMode: false);
    expect(cam.startedWith, [null]);
    await _tap(t, 'measure_cancel');
  });
}
