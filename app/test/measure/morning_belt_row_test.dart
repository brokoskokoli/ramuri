import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_belt.dart';
import 'package:running_app/features/measure/morning_launcher.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// WP37 C2: Gurtzeile im Einstieg der Morgenmessung. Synthetische Geräte.

class _Counting extends FakeHeartRateSensor {
  final calls = <String>[];

  @override
  Stream<HeartRateEvent> connect(String deviceId) {
    calls.add(deviceId);
    return super.connect(deviceId);
  }
}

final _clock = FakeClock(DateTime.utc(2026, 11, 10, 6));

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump();
  }
}

/// Öffnet den Einstieg über einen Host mit Gurtquelle; [known]: bekannte
/// Geräte (das erste zuletzt genutzt).
Future<(_Counting, SensorManager)> _pump(
  WidgetTester t, {
  required List<String> known,
  required bool dark,
  String lang = 'de',
}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final session = await t.runAsync(() => FakeStorage().open(testKey));
  final sensor = _Counting();
  final manager = SensorManager(
    sensor: sensor,
    clock: _clock,
    requestPermissions: () async {},
    bluetoothGranted: () async => true,
  );
  addTearDown(manager.dispose);
  await t.runAsync(() async {
    for (final id in known) {
      await session!.devices.upsert(
        id,
        displayName: 'Gurt $id',
        at: _clock.now(),
      );
    }
    if (known.isNotEmpty) {
      await session!.devices.markUsed(known.first, at: _clock.now());
    }
    await manager.attachStore(session!.devices);
  });
  await t.pumpWidget(
    MaterialApp(
      theme: dark ? RamuriTheme.dark : RamuriTheme.light,
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MorningMeasureHost(
        camera: FakePpgCamera(),
        store: (session! as MorningStorage).morning,
        settings: session.settings,
        clock: _clock,
        autoTick: false,
        belt: MorningBelt(
          readings: manager.activeReadings,
          connected: () => manager.selector.activeId != null,
          developerMode: () async => false,
          sensors: manager,
        ),
      ),
    ),
  );
  await _settle(t);
  return (sensor, manager);
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dunkel' : 'hell';

    testWidgets('bekannter Gurt: ohne Rückfrage verbunden ($mode)', (t) async {
      final (sensor, _) = await _pump(t, known: ['g1', 'g2'], dark: dark);
      expect(sensor.calls, ['g1']);
      expect(tester(t, 'morning_gurt_text').data, 'verbunden: Gurt g1');
      expect(find.byKey(const Key('morning_gurt_pick')), findsNothing);
      expect(find.byKey(const Key('morning_gurt_note')), findsNothing);
    });

    testWidgets('ohne Gurt: „kein Gurt“, Hinweis, Knopf 48 dp, Auswahl und '
        'zurück ($mode)', (t) async {
      final (sensor, _) = await _pump(t, known: [], dark: dark);
      expect(sensor.calls, isEmpty);
      expect(tester(t, 'morning_gurt_text').data, 'kein Gurt');
      expect(
        tester(t, 'morning_gurt_note').data,
        contains('fehlen die Gurtwerte für die Validierung'),
      );
      final pick = find.byKey(const Key('morning_gurt_pick'));
      expect(t.getSize(pick).height, greaterThanOrEqualTo(48));
      await t.tap(pick);
      await t.pumpAndSettle();
      expect(find.text('Pulssensoren'), findsOneWidget);
      expect(find.byKey(const Key('morning_start')), findsNothing);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('morning_start')), findsOneWidget);
      expect(find.byKey(const Key('morning_gurt_pick')), findsOneWidget);
    });
  }

  testWidgets('englisch: Texte der Zeile', (t) async {
    await _pump(t, known: [], dark: false, lang: 'en');
    expect(tester(t, 'morning_gurt_text').data, 'no strap');
    expect(find.text('Connect strap'), findsOneWidget);
  });
}

Text tester(WidgetTester t, String key) => t.widget<Text>(find.byKey(Key(key)));
