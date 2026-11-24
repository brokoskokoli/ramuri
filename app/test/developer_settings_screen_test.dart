import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/export/file_handoff_scope.dart';
import 'package:running_app/features/settings/developer_settings_screen.dart';
import 'package:running_app/features/settings/ppg_camera_section.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

void main() {
  pairsTests();
  cameraTests();
  pageTests();
}

/// Alle drei Abschnitte: Modus an, Kameras, Morgenmessungen.
Future<DeveloperModeStore> _pumpAll(
  WidgetTester tester, {
  String locale = 'de',
  double scale = 1,
  Size size = const Size(800, 2400),
}) async {
  final s = await _cameraSetup();
  final session = await FakeStorage().open(Uint8List(32));
  final morning = (session as MorningStorage).morning;
  await morning.add(_morning(1));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      theme: RamuriTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FileHandoffScope(
        handoff: FakeFileHandoff(),
        child: DeveloperSettingsScreen(
          developerMode: s.mode,
          ppgCamera: s.camera,
          cameraChoice: s.choice,
          morning: morning,
          clock: () => DateTime.utc(2031, 2, 3),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s.mode;
}

void pageTests() {
  testWidgets('Seite: Titel, Abschnitte Entwicklermodus, Kamera, Messpaare, '
      'Kamera gegen Gurt in dieser Reihenfolge', (tester) async {
    await _pumpAll(tester);
    expect(find.widgetWithText(AppBar, 'Entwicklereinstellungen'), findsOne);
    expect(find.text('Entwicklermodus'), findsOneWidget);
    final y = [
      key('about_dev_switch'),
      key('about_ppg_camera_card'),
      key('about_pairs'),
      key('dev_compare'),
    ].map((f) => tester.getTopLeft(f).dy).toList();
    expect(y[0], lessThan(y[1]));
    expect(y[1], lessThan(y[2]));
    expect(y[2], lessThan(y[3]));
  });

  testWidgets('Seite: Englisch', (tester) async {
    await _pumpAll(tester, locale: 'en');
    expect(find.widgetWithText(AppBar, 'Developer settings'), findsOne);
    expect(find.text('Developer mode'), findsOneWidget);
    expect(find.text('Camera for pulse measurement'), findsOneWidget);
    expect(find.text('Camera and strap pairs'), findsOneWidget);
  });

  for (final locale in ['de', 'en']) {
    testWidgets('Seite: große Schrift (200 %) ohne Überlauf, $locale', (
      tester,
    ) async {
      await _pumpAll(
        tester,
        locale: locale,
        scale: 2,
        size: const Size(720, 1280),
      );
      expect(tester.takeException(), isNull);
      // Bis zum letzten Abschnitt scrollen, auch dort kein Überlauf.
      await tester.scrollUntilVisible(
        key('about_pairs_share'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(key('about_pairs_share'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

MorningMeasurement _morning(int day) => MorningMeasurement(
  measuredAt: DateTime.utc(2030, 1, day, 6, 30),
  utcOffset: Duration.zero,
  posture: RestingPosture.lying,
  deviceManufacturer: 'Testhersteller',
  deviceModel: 'Modell',
  method: ppgMethod,
  methodVersion: ppgMethodVersion,
  quality: PpgQuality.good,
  restingHrBpm: 58,
  rmssdMs: 40,
  cameraIntervalsMs: const [1000, 1010],
  beforeValidation: true,
  outsideWindow: false,
);

/// Entwicklereinstellungen mit Morgenmessungen (eine mit Gurt-RR, eine
/// ohne) und Übergabe-Fake.
Future<({FakeFileHandoff handoff, DeveloperModeStore mode})> _pumpPairs(
  WidgetTester tester, {
  bool on = true,
  String locale = 'de',
}) async {
  final session = await FakeStorage().open(Uint8List(32));
  final mode = SettingsDeveloperModeStore(
    session.settings,
    FakeClock(DateTime.utc(2026, 11, 14)),
  );
  await mode.set(on);
  final morning = (session as MorningStorage).morning;
  await morning.add(
    _morning(1),
    beltPackets: [
      RrPacket(
        time: DateTime.utc(2030, 1, 1, 6, 29),
        source: 'gurt-1',
        intervals: const [900],
      ),
    ],
  );
  await morning.add(_morning(2));
  final handoff = FakeFileHandoff();
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      theme: RamuriTheme.light,
      home: FileHandoffScope(
        handoff: handoff,
        child: DeveloperSettingsScreen(
          developerMode: mode,
          morning: morning,
          clock: () => DateTime.utc(2031, 2, 3),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (handoff: handoff, mode: mode);
}

void pairsTests() {
  testWidgets('Messpaare: Zahl, Warnhinweis vor dem Teilen, dann die Datei', (
    tester,
  ) async {
    final r = await _pumpPairs(tester);
    expect(
      find.text(
        '1 Morgen mit Gurt-RR, 1 ohne. Gespeichert wird, wenn bei der '
        'Morgenmessung eine Pulsquelle mit RR verbunden ist. Den Vergleich '
        'zeigt der Abschnitt „Kamera gegen Gurt“; er geht in keine Auswertung '
        'ein.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(key('about_pairs_share'));
    await tester.tap(key('about_pairs_share'));
    await tester.pumpAndSettle();
    // Warnhinweis zuerst, noch nichts geteilt.
    expect(key('about_pairs_dialog'), findsOneWidget);
    expect(find.text('Unverschlüsselte Datei teilen?'), findsOneWidget);
    expect(r.handoff.shared, isEmpty);
    await tester.tap(key('about_pairs_cancel'));
    await tester.pumpAndSettle();
    expect(r.handoff.shared, isEmpty);
    await tester.tap(key('about_pairs_share'));
    await tester.pumpAndSettle();
    await tester.tap(key('about_pairs_confirm'));
    await tester.pumpAndSettle();
    expect(r.handoff.shared, hasLength(1));
    expect(
      r.handoff.shared.single.fileName,
      'running-morgenpaare-20310203.csv',
    );
    final text = String.fromCharCodes(r.handoff.shared.single.bytes!);
    expect(text, contains(',belt_rr,rr,1,1,'));
    expect(find.text('Datei an das gewählte Ziel übergeben.'), findsOneWidget);
  });

  testWidgets('Messpaare: ohne Entwicklermodus weder Zahl noch Knopf', (
    tester,
  ) async {
    await _pumpPairs(tester, on: false);
    expect(key('about_pairs'), findsNothing);
    expect(key('about_pairs_share'), findsNothing);
  });

  testWidgets('Messpaare: Ausschalten blendet Zahl und Knopf aus', (
    tester,
  ) async {
    await _pumpPairs(tester);
    await tester.ensureVisible(key('about_dev_switch'));
    await tester.tap(key('about_dev_switch'));
    await tester.pumpAndSettle();
    expect(key('about_pairs_share'), findsNothing);
  });

  testWidgets('Messpaare: Englisch', (tester) async {
    await _pumpPairs(tester, locale: 'en');
    expect(find.text('Share pairs as CSV'), findsOneWidget);
    expect(
      find.textContaining('1 morning with strap RR, 1 without'),
      findsOneWidget,
    );
  });
}

/// Drei erfundene Rückkameras wie die Debug-Quelle: Standard, eine physische
/// Kamera der Standardkamera und eine ohne Blitz; dazu eine ohne feste Bildrate.
const List<PpgCameraInfo> _cameras = [
  PpgCameraInfo(ref: PpgCameraRef('0'), focalLengthMm: 5.4, isDefault: true),
  PpgCameraInfo(ref: PpgCameraRef('0', '2'), focalLengthMm: 2.2),
  PpgCameraInfo(
    ref: PpgCameraRef('1'),
    focalLengthMm: 6.8,
    unusable: PpgCameraUnusable.noFlash,
  ),
];

/// Erfundene Kameras mit Bildrate: 60 (Standard), 30, ohne Bildrate, nicht nutzbar mit
/// bekannter Bildrate und nicht nutzbar ohne feste Bildrate.
const List<PpgCameraInfo> _rateCameras = [
  PpgCameraInfo(
    ref: PpgCameraRef('0'),
    focalLengthMm: 6.4,
    isDefault: true,
    frameRate: 60,
  ),
  PpgCameraInfo(ref: PpgCameraRef('0', '2'), focalLengthMm: 2.2, frameRate: 30),
  PpgCameraInfo(ref: PpgCameraRef('0', '3'), focalLengthMm: 4.0),
  PpgCameraInfo(
    ref: PpgCameraRef('1'),
    focalLengthMm: 6.8,
    frameRate: 60,
    unusable: PpgCameraUnusable.noFlash,
  ),
  PpgCameraInfo(ref: PpgCameraRef('2'), unusable: PpgCameraUnusable.frameRate),
];

typedef _CameraSetup = ({
  SettingsStore settings,
  DeveloperModeStore mode,
  PpgCameraChoiceStore choice,
  FakePpgCamera camera,
});

Future<_CameraSetup> _cameraSetup({bool on = true}) async {
  final session = await FakeStorage().open(Uint8List(32));
  final clock = FakeClock(DateTime.utc(2026, 11, 14));
  final mode = SettingsDeveloperModeStore(session.settings, clock);
  await mode.set(on);
  final camera = FakePpgCamera()..cameraList = _cameras;
  return (
    settings: session.settings,
    mode: mode,
    choice: SettingsPpgCameraChoiceStore(session.settings, clock),
    camera: camera,
  );
}

/// Baut die Entwicklereinstellungen neu auf (wie nach einem Neustart: neuer Zustand, dieselben Einstellungen).
Future<void> _pumpCamera(
  WidgetTester tester,
  _CameraSetup s, {
  String locale = 'de',
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      theme: RamuriTheme.light,
      home: DeveloperSettingsScreen(
        developerMode: s.mode,
        ppgCamera: s.camera,
        cameraChoice: s.choice,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _entry(PpgCameraRef? ref) => find.byKey(PpgCameraSection.entryKey(ref));

bool _selected(WidgetTester tester, PpgCameraRef? ref) {
  final tile = tester.widget<RadioListTile<String>>(_entry(ref));
  return RadioGroup.maybeOf<String>(tester.element(_entry(ref)))?.groupValue ==
      tile.value;
}

bool _enabled(WidgetTester tester, PpgCameraRef ref) =>
    tester.widget<RadioListTile<String>>(_entry(ref)).enabled ?? true;

void cameraTests() {
  testWidgets(
    'Kamera: drei Kameras, Standard markiert, ohne Blitz nicht wählbar',
    (tester) async {
      final s = await _cameraSetup();
      await _pumpCamera(tester, s);
      expect(find.text('Kamera für die Pulsmessung'), findsOneWidget);
      expect(find.text('Kamera 0'), findsOneWidget);
      expect(find.text('Kamera 0/2'), findsOneWidget);
      expect(find.text('Kamera 1'), findsOneWidget);
      expect(find.text('5,4 mm · Standard'), findsOneWidget);
      expect(find.text('2,2 mm'), findsOneWidget);
      expect(find.text('6,8 mm · ohne Blitz'), findsOneWidget);
      expect(_enabled(tester, const PpgCameraRef('0')), isTrue);
      expect(_enabled(tester, const PpgCameraRef('0', '2')), isTrue);
      expect(_enabled(tester, const PpgCameraRef('1')), isFalse);
      expect(_selected(tester, null), isTrue);
      expect(key('about_ppg_camera_missing'), findsNothing);

      // Tipp auf die Kamera ohne Blitz ändert nichts.
      await tester.tap(_entry(const PpgCameraRef('1')));
      await tester.pumpAndSettle();
      expect(await s.choice.readManual(), isNull);
      expect(_selected(tester, null), isTrue);
    },
  );

  testWidgets('Kamera: Bildrate je nutzbarer Kamera im Untertitel', (
    tester,
  ) async {
    final s = await _cameraSetup();
    s.camera.cameraList = _rateCameras;
    await _pumpCamera(tester, s);
    expect(find.text('6,4 mm · 60 Bilder/s · Standard'), findsOneWidget);
    expect(find.text('2,2 mm · 30 Bilder/s'), findsOneWidget);
    // Ohne Bildrate entfällt das Teilstück.
    expect(find.text('4,0 mm'), findsOneWidget);
    // Nicht nutzbar: Grund, keine Bildrate (auch wenn Kotlin eine kennt).
    expect(find.text('6,8 mm · ohne Blitz'), findsOneWidget);
    expect(find.text('Bildrate'), findsOneWidget);
    expect(find.textContaining('Bilder/s'), findsNWidgets(2));
  });

  testWidgets('Kamera: Bildrate englisch', (tester) async {
    final s = await _cameraSetup();
    s.camera.cameraList = _rateCameras;
    await _pumpCamera(tester, s, locale: 'en');
    expect(find.text('6.4 mm · 60 fps · Default'), findsOneWidget);
    expect(find.text('2.2 mm · 30 fps'), findsOneWidget);
    expect(find.text('4.0 mm'), findsOneWidget);
    expect(find.text('6.8 mm · no flash'), findsOneWidget);
    expect(find.textContaining('fps'), findsNWidgets(2));
  });

  testWidgets('Kamera: Wahl bleibt nach Neuaufbau, „Standard“ löscht sie', (
    tester,
  ) async {
    final s = await _cameraSetup();
    await _pumpCamera(tester, s);
    await tester.tap(_entry(const PpgCameraRef('0', '2')));
    await tester.pumpAndSettle();
    expect(await s.choice.readManual(), const PpgCameraRef('0', '2'));
    expect(await s.settings.get(SettingKeys.ppgCameraManual), '0/2');

    await _pumpCamera(tester, s);
    expect(_selected(tester, const PpgCameraRef('0', '2')), isTrue);
    expect(_selected(tester, null), isFalse);

    await tester.tap(_entry(null));
    await tester.pumpAndSettle();
    expect(await s.choice.readManual(), isNull);
    expect(_selected(tester, null), isTrue);
    await _pumpCamera(tester, s);
    expect(_selected(tester, null), isTrue);
  });

  testWidgets('Kamera: gewählte Kamera verschwunden → Hinweis, Standard gilt', (
    tester,
  ) async {
    final s = await _cameraSetup();
    await s.choice.setManual(const PpgCameraRef('0', '5'));
    await _pumpCamera(tester, s);
    expect(
      find.text('Gewählte Kamera nicht gefunden, es gilt die Standardkamera'),
      findsOneWidget,
    );
    expect(_selected(tester, null), isTrue);
    // Die Wahl bleibt gespeichert, bis man eine andere trifft.
    expect(await s.choice.readManual(), const PpgCameraRef('0', '5'));
  });

  testWidgets('Kamera: ohne Rückkamera „Keine Rückkamera“', (tester) async {
    final s = await _cameraSetup();
    s.camera.cameraList = const [];
    await _pumpCamera(tester, s);
    expect(find.text('Keine Rückkamera'), findsOneWidget);
    expect(_entry(null), findsNothing);
  });

  testWidgets('Kamera: ohne Kamera-Recht bleibt die Liste', (tester) async {
    final s = await _cameraSetup();
    s.camera.availabilityState = PpgCameraAvailability.permissionDenied;
    await _pumpCamera(tester, s);
    expect(find.text('Kamera 0/2'), findsOneWidget);
  });

  testWidgets('Kamera: ohne Entwicklermodus keine Karte', (tester) async {
    final s = await _cameraSetup(on: false);
    await _pumpCamera(tester, s);
    expect(key('about_ppg_camera_card'), findsNothing);
    expect(find.text('Kamera für die Pulsmessung'), findsNothing);
    expect(s.camera.camerasCount, 0);
  });

  testWidgets('Kamera: Ausschalten des Entwicklermodus blendet die Karte aus', (
    tester,
  ) async {
    final s = await _cameraSetup();
    await _pumpCamera(tester, s);
    expect(key('about_ppg_camera_card'), findsOneWidget);
    await tester.tap(key('about_dev_switch'));
    await tester.pumpAndSettle();
    expect(key('about_ppg_camera_card'), findsNothing);
  });

  testWidgets('Kamera: Englisch', (tester) async {
    final s = await _cameraSetup();
    s.camera.cameraList = [
      ..._cameras,
      const PpgCameraInfo(
        ref: PpgCameraRef('3'),
        unusable: PpgCameraUnusable.frameRate,
      ),
    ];
    await s.choice.setManual(const PpgCameraRef('9'));
    await _pumpCamera(tester, s, locale: 'en');
    expect(find.text('Camera for pulse measurement'), findsOneWidget);
    expect(find.text('Camera 0/2'), findsOneWidget);
    expect(find.text('5.4 mm · Default'), findsOneWidget);
    expect(find.text('6.8 mm · no flash'), findsOneWidget);
    expect(find.text('frame rate'), findsOneWidget);
    expect(
      find.text('Selected camera not found, the default camera is used'),
      findsOneWidget,
    );
    s.camera.cameraList = const [];
    await _pumpCamera(tester, s, locale: 'en');
    expect(find.text('No rear camera'), findsOneWidget);
  });
}
