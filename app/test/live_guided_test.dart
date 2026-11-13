// WP24 C: Live-Seite der geführten Einheit (FR-0027, FR-0146, FR-0205): bleibt in hell und dunkel dunkel, Restzeit des
// Abschnitts, Soll/Ist, nächster Abschnitt, Pulshinweis nur nach PAR-107, Laufband, Pflichtanzeigen (FR-0026) daneben.
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/live_run_view.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/sensors/run_heart_rate.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

const _fmt = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'de',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

const _fmtEn = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'en',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

const _plan = [
  PlanSegment(kind: PlanSegmentKind.warmUp, minutes: 1),
  PlanSegment(
    kind: PlanSegmentKind.interval,
    minutes: 5,
    intensity: PlanTargetIntensity(
      paceFastSecondsPerKm: 270,
      paceSlowSecondsPerKm: 285,
      rpeMin: 7,
      rpeMax: 8,
      hrMinBpm: 150,
      hrMaxBpm: 170,
    ),
  ),
  PlanSegment(kind: PlanSegmentKind.recovery, minutes: 2),
];

/// Block unter 4 min mit Pulsgrenze (PAR-107: nie ein Pulshinweis).
const _short = [
  PlanSegment(
    kind: PlanSegmentKind.interval,
    minutes: 3,
    seconds: 230,
    intensity: PlanTargetIntensity(hrMaxBpm: 150),
  ),
];

class _World {
  _World({List<PlanSegment>? segments, bool belt = false, bool withHr = false})
    : clock = FakeClock(DateTime.utc(2031, 3, 1, 10)) {
    if (withHr) {
      hr = SensorManager(sensor: FakeHeartRateSensor(), clock: clock).beginRun()
        ..handle(const HeartRateConnected('s'));
    }
    _segments = segments;
    _belt = belt;
  }

  final FakeClock clock;
  final location = FakeLocationSource();
  RunHeartRate? hr;
  late final RunController run;
  List<PlanSegment>? _segments;
  bool _belt = false;
  int _i = 0;

  Future<void> start() async {
    final session = await FakeStorage().open(Uint8List(32));
    run = RunController(
      clock: clock,
      storage: session,
      location: location,
      sensors: hr,
      guidedSegments: _segments,
      mode: _belt ? RunMode.treadmill : RunMode.gps,
      startBeltSpeedMetersPerSecond: _belt ? 3 : null,
    );
    await run.start();
  }

  Future<void> seconds(WidgetTester tester, int n, {int? bpm}) async {
    for (var k = 0; k < n; k++) {
      clock.advance(const Duration(seconds: 1));
      if (!_belt) {
        location.emit(
          LocationSample(
            time: clock.now(),
            latitude: 50 + _i++ * 0.000027,
            longitude: 8,
            accuracyMeters: 5,
          ),
        );
      }
      if (bpm != null) hr?.handle(HeartRateReading('s', clock.now(), bpm));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

Future<_World> _show(
  WidgetTester tester, {
  List<PlanSegment>? segments = _plan,
  bool dark = false,
  String lang = 'de',
  bool belt = false,
  bool withHr = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final w = _World(segments: segments, belt: belt, withHr: withHr);
  _worlds.add(w);
  await w.start();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(lang),
      theme: dark ? RamuriTheme.dark : RamuriTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ListenableBuilder(
        listenable: w.run,
        builder: (context, _) => LiveRunView(
          controller: w.run,
          formatter: lang == 'de' ? _fmt : _fmtEn,
        ),
      ),
    ),
  );
  await tester.pump();
  return w;
}

Finder _k(String k) => find.byKey(Key(k));
String _t(WidgetTester tester, String k) =>
    tester.widget<Text>(_k(k)).data ?? '';

final _worlds = <_World>[];

/// Wie testWidgets; danach wird die Anzeige abgebaut und der Takt des Laufs beendet.
void _test(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final w in _worlds) {
        w.run.dispose();
      }
      _worlds.clear();
      tester.view.reset();
    }
  });
}

void main() {
  for (final lang in ['de', 'en']) {
    for (final dark in [false, true]) {
      _test(
        'Seite bleibt dunkel, Restzeit, n von m ($lang, ${dark ? 'dunkel' : 'hell'})',
        (tester) async {
          final w = await _show(tester, lang: lang, dark: dark);
          await w.seconds(tester, 10);
          final l = lookupAppLocalizations(Locale(lang));
          expect(_t(tester, 'guided_remaining'), '0:50');
          expect(
            _t(tester, 'guided_section'),
            l.guidedLiveSection(1, 3, l.voiceSegmentWarmUp),
          );
          expect(_t(tester, 'guided_title'), l.guidedLiveTitle.toUpperCase());
          // Nächster Abschnitt: 5:00 Intervall.
          expect(_t(tester, 'guided_next'), '5:00 ${l.voiceSegmentInterval}');
          // FR-0205: dunkel in beiden Modi, Farben aus dem Theme.
          final ctx = tester.element(_k('guided_remaining'));
          expect(Theme.of(ctx).brightness, Brightness.dark);
          expect(
            RamuriColors.of(ctx).background,
            RamuriColors.night.background,
          );
          final bg = tester.widget<Material>(
            find
                .ancestor(
                  of: _k('guided_remaining'),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(bg.color, RamuriColors.night.background);
          // Ohne Soll im Aufwärmabschnitt.
          expect(_k('guided_no_target'), findsOneWidget);
          expect(_k('guided_hr_hint'), findsNothing);
        },
      );
    }
  }

  _test('Abschnittswechsel: Zähler, Soll (Pace, RPE, Puls), Danach', (
    tester,
  ) async {
    final w = await _show(tester);
    await w.seconds(tester, 61);
    expect(_t(tester, 'guided_section'), 'Abschnitt 2 von 3 · Intervall');
    expect(_t(tester, 'guided_remaining'), '4:59');
    expect(_t(tester, 'guided_target_0'), 'Pace 4:30 bis 4:45 min/km');
    expect(_t(tester, 'guided_target_1'), 'Anstrengung 7 bis 8 von 10');
    expect(_t(tester, 'guided_target_2'), 'Puls 150 bis 170 bpm');
    expect(_t(tester, 'guided_next'), '2:00 Trabpause');
    await w.seconds(tester, 300);
    expect(_t(tester, 'guided_section'), 'Abschnitt 3 von 3 · Trabpause');
    expect(_k('guided_next'), findsNothing); // letzter Abschnitt
    await w.seconds(tester, 120);
    expect(_k('guided_done'), findsOneWidget); // alle durch
    expect(_k('guided_remaining'), findsNothing);
  });

  _test('Pulshinweis erst nach 3 min im Abschnitt und nur über der Grenze', (
    tester,
  ) async {
    final w = await _show(tester, withHr: true);
    await w.seconds(tester, 60 + 179, bpm: 175); // 2:59 im Block
    expect(_k('guided_hr_hint'), findsNothing);
    await w.seconds(tester, 1, bpm: 175); // 3:00
    expect(_t(tester, 'guided_hr_hint'), contains('175 bpm'));
    await w.seconds(tester, 1, bpm: 165); // im Bereich
    expect(_k('guided_hr_hint'), findsNothing);
  });

  _test('Block unter 4 min: nie ein Pulshinweis (PAR-107)', (tester) async {
    final w = await _show(tester, segments: _short, withHr: true);
    await w.seconds(tester, 215, bpm: 190); // weit nach 3 min im Abschnitt
    expect(_k('guided_remaining'), findsOneWidget);
    expect(_k('guided_hr_hint'), findsNothing);
  });

  _test('Pause hält den Abschnitt, Weiter und Beenden erreichbar', (
    tester,
  ) async {
    final w = await _show(tester);
    await w.seconds(tester, 20);
    await tester.tap(_k('run_pause').hitTestable());
    await tester.pump();
    expect(_k('guided_paused'), findsOneWidget);
    final frozen = _t(tester, 'guided_remaining');
    w.clock.advance(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(_t(tester, 'guided_remaining'), frozen);
    expect(_k('run_finish').hitTestable(), findsOneWidget);
    await tester.tap(_k('run_resume').hitTestable());
    await tester.pump();
    expect(_k('guided_paused'), findsNothing);
  });

  _test(
    'Pflichtanzeigen (FR-0026) auf der Werte-Seite erreichbar, Touchziele 48 dp',
    (tester) async {
      final w = await _show(tester);
      await w.seconds(tester, 5);
      for (final k in ['run_pause', 'run_lap']) {
        final s = tester.getSize(_k(k).hitTestable());
        expect(s.width, greaterThanOrEqualTo(48));
        expect(s.height, greaterThanOrEqualTo(48));
      }
      for (var i = 0; i < 3; i++) {
        final s = tester.getSize(_k('run_tab_$i'));
        expect(s.height, greaterThanOrEqualTo(48), reason: 'Reiter $i');
      }
      await tester.tap(_k('run_tab_1'));
      await tester.pumpAndSettle();
      for (final k in ['run_time', 'run_pace', 'run_pause']) {
        expect(_k(k).hitTestable(), findsOneWidget, reason: k);
      }
      await tester.tap(_k('run_tab_2'));
      await tester.pumpAndSettle();
      expect(_k('run_page_map'), findsOneWidget);
      await tester.tap(_k('run_tab_0'));
      await tester.pumpAndSettle();
      expect(_k('guided_remaining').hitTestable(), findsOneWidget);
    },
  );

  _test('GPS-Status (FR-0026) bleibt auf der Werte-Seite sichtbar', (
    tester,
  ) async {
    await _show(tester); // noch keine Position: Suche läuft
    await tester.tap(_k('run_tab_1'));
    await tester.pumpAndSettle();
    expect(_k('run_gps').hitTestable(), findsOneWidget);
  });

  _test('Laufband: Bandgeschwindigkeit als Ist, keine Karte', (tester) async {
    final w = await _show(tester, belt: true);
    await w.seconds(tester, 10);
    expect(_t(tester, 'guided_remaining'), '0:50');
    expect(_t(tester, 'guided_now'), '10,8 km/h');
    expect(_k('run_tab_1'), findsOneWidget); // Werte
    expect(_k('run_tab_2'), findsNothing); // keine Karte
    await tester.tap(_k('run_tab_1'));
    await tester.pumpAndSettle();
    expect(_k('run_time').hitTestable(), findsOneWidget);
  });

  _test('Ist im GPS-Lauf ist die aktuelle Pace', (tester) async {
    final w = await _show(tester);
    await w.seconds(tester, 15);
    expect(_t(tester, 'guided_now'), contains('min/km'));
  });

  _test('Freier Lauf unverändert: keine Einheiten-Seite', (tester) async {
    final w = await _show(tester, segments: null);
    await w.seconds(tester, 5);
    expect(_k('guided_title'), findsNothing);
    expect(_k('run_tab_1'), findsOneWidget); // Karte
    expect(_k('run_tab_2'), findsNothing);
    expect(_k('run_time').hitTestable(), findsOneWidget);
  });
}
