import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/export/file_handoff_scope.dart';
import 'package:running_app/features/settings/about_screen.dart';
import 'package:running_app/features/settings/ppg_camera_section.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show started;

Future<DeveloperModeStore> _store() async {
  final session = await FakeStorage().open(Uint8List(32));
  return SettingsDeveloperModeStore(
    session.settings,
    FakeClock(DateTime.utc(2026, 11, 14)),
  );
}

Future<void> _pump(
  WidgetTester tester,
  DeveloperModeStore store, {
  String locale = 'de',
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      theme: RamuriTheme.light,
      darkTheme: RamuriTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: AboutScreen(
        developerMode: store,
        appVersion: () async => '0.1.0 (12)',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVersion(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(key('about_version'));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  pairsTests();
  cameraTests();
  testWidgets('Name, Version, Lizenzen; ohne Modus kein Abschnitt Entwickler', (
    tester,
  ) async {
    await _pump(tester, await _store());
    expect(find.text('Über'), findsOneWidget);
    expect(find.text('Version 0.1.0 (12)'), findsOneWidget);
    expect(key('about_licenses'), findsOneWidget);
    expect(key('about_dev_section'), findsNothing);
    expect(key('about_dev_badge'), findsNothing);
    expect(key('about_toast'), findsNothing);
  });

  testWidgets('9 Tipps schalten nicht ein, Zähler erst ab dem 7. Tipp', (
    tester,
  ) async {
    final store = await _store();
    await _pump(tester, store);
    await _tapVersion(tester, 6);
    expect(key('about_toast'), findsNothing);
    await _tapVersion(tester, 1);
    expect(find.text('Noch 3 Tipps bis zum Entwicklermodus'), findsOneWidget);
    await _tapVersion(tester, 1);
    expect(find.text('Noch 2 Tipps bis zum Entwicklermodus'), findsOneWidget);
    await _tapVersion(tester, 1);
    expect(find.text('Noch 1 Tipp bis zum Entwicklermodus'), findsOneWidget);
    expect(await store.read(), isFalse);
    expect(key('about_dev_section'), findsNothing);
    expect(key('about_dev_badge'), findsNothing);
  });

  testWidgets('10 Tipps schalten ein; Abschnitt, Hinweis, gespeichert', (
    tester,
  ) async {
    final store = await _store();
    await _pump(tester, store);
    await _tapVersion(tester, 10);
    expect(await store.read(), isTrue);
    expect(find.text('Entwicklermodus an'), findsNWidgets(2)); // Hinweis, Toast
    expect(key('about_dev_badge'), findsOneWidget);
    expect(find.text('Entwickler'), findsOneWidget);
    expect(key('about_dev_switch'), findsOneWidget);
  });

  testWidgets('Schalter schaltet aus, Zähler beginnt neu', (tester) async {
    final store = await _store();
    await store.set(true);
    await _pump(tester, store);
    expect(key('about_dev_section'), findsOneWidget);
    expect(key('about_toast'), findsNothing);
    await tester.tap(key('about_dev_switch'));
    await tester.pumpAndSettle();
    expect(await store.read(), isFalse);
    expect(key('about_dev_section'), findsNothing);
    expect(key('about_dev_badge'), findsNothing);
    // 9 Tipps danach schalten wieder nicht ein.
    await _tapVersion(tester, 9);
    expect(await store.read(), isFalse);
  });

  testWidgets('Englisch, dunkel: Texte und Abschnitt', (tester) async {
    final store = await _store();
    await store.set(true);
    await _pump(tester, store, locale: 'en', dark: true);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Version 0.1.0 (12)'), findsOneWidget);
    expect(find.text('Developer mode on'), findsOneWidget);
    expect(find.text('Developer'), findsOneWidget);
    expect(find.text('Licenses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Version unbekannt, wenn das System keine liefert', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        theme: RamuriTheme.light,
        home: AboutScreen(
          developerMode: await _store(),
          appVersion: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version unbekannt'), findsOneWidget);
  });

  testWidgets('Übersicht: Über zeigt den Modus aus der Sitzung (Verdrahtung)', (
    tester,
  ) async {
    final d = await started(tester);
    await SettingsDeveloperModeStore(d.session.settings, d.clock).set(true);
    await openOverview(tester);
    await tester.tap(key('overview_about'));
    await tester.pumpAndSettle();
    expect(key('about_dev_badge'), findsOneWidget);
    // Kamera der App (hier ohne Rückkamera) und Kamerawahl der Sitzung sind verdrahtet.
    expect(key('about_ppg_camera_card'), findsOneWidget);
    expect(find.text('Keine Rückkamera'), findsOneWidget);
  });
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

/// Über mit Entwickler-Abschnitt, Morgenmessungen (eine mit Gurt-RR, eine
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
        child: AboutScreen(
          developerMode: mode,
          appVersion: () async => '0.1.0 (12)',
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
        'Morgenmessung eine Pulsquelle mit RR verbunden ist. Die App wertet '
        'den Gurt nicht aus.',
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

/// Baut „Über“ neu auf (wie nach einem Neustart: neuer Zustand, dieselben Einstellungen).
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
      home: AboutScreen(
        developerMode: s.mode,
        appVersion: () async => '0.1.0 (12)',
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
