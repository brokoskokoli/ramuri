import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/storage/storage_start.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'settings_gate_storage.dart';
import 'storage_world.dart';

// Willkommen (FR-0207): vor der ersten Einrichtung, einmal.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

Future<void> _restart(Device d, WidgetTester tester, [String l = 'de']) async {
  await d.stop(tester);
  await d.start(tester, Locale(l), welcome: true);
}

void main() {
  testWidgets('erster Start (Deutsch): Logo, Satz, Knopf, Hinweis, dunkel', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final d = Device();
    await d.start(tester, const Locale('de'), welcome: true);
    expect(key('welcome_screen'), findsOneWidget);
    expect(find.text('Ruhig laufen.\nKlar vorankommen.'), findsOneWidget);
    expect(find.text("Los geht's"), findsOneWidget);
    expect(
      find.text(
        'Deine Läufe bleiben auf deinem Handy.\n'
        'Ohne Konto, ohne Uhr-Zwang.',
      ),
      findsOneWidget,
    );
    // OQ-0075: kein Versprechen über „Daten“.
    expect(find.textContaining('Daten'), findsNothing);
    // Logo mit Beschriftung für TalkBack, Knopf mindestens 48 dp.
    expect(find.bySemanticsLabel('ramuri'), findsWidgets);
    expect(find.byType(RamuriLogo), findsOneWidget);
    expect(
      tester.getSize(key('welcome_start')).height,
      greaterThanOrEqualTo(48),
    );
    // Auch im hellen System bleibt der Grund dunkel.
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(RamuriDarkScope),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, RamuriColors.night.background);
    expect(key('setup_skip'), findsNothing);
    await tester.tap(key('welcome_start'));
    await tester.pumpAndSettle();
    expect(key('welcome_screen'), findsNothing);
    expect(key('setup_skip'), findsOneWidget);
  });

  testWidgets('Logo im selben Bild wie der Text: im ersten Bild mit dem Satz '
      'ist das Logo schon geladen', (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('de')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final w = World();
    // Der Start hält vor dem Öffnen an, wie auf dem Gerät, während Schlüssel
    // und Datenbank laden.
    final opening = Completer<void>();
    final controller = StorageStartController(
      keyStore: w.keys,
      generateKey: () => keyOf(1),
      wire: () async {
        await opening.future;
        return StorageWiring(storage: w.storage, files: w.files);
      },
    );
    await tester.pumpWidget(
      RunningApp(dependencies: AppDependencies(storageStart: controller)),
    );
    expect(key('welcome_tagline'), findsNothing);
    // Das Vorladen läuft schon; Bilder dekodiert nur die echte Zeit.
    final image = ramuriLogoImage(
      RamuriLogoStyle.stackedOnDark,
      Brightness.dark,
    );
    final cacheKey = (await tester.runAsync(
      () => image.obtainKey(ImageConfiguration.empty),
    ))!;
    for (var i = 0; i < 400; i++) {
      final status = PaintingBinding.instance.imageCache.statusForKey(cacheKey);
      if (status.tracked && !status.pending) break;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    final status = PaintingBinding.instance.imageCache.statusForKey(cacheKey);
    expect(status.tracked && !status.pending, isTrue);
    opening.complete();
    // Bild für Bild weiter, bis der Satz zum ersten Mal steht.
    for (var i = 0; i < 50 && key('welcome_tagline').evaluate().isEmpty; i++) {
      await tester.pump();
    }
    expect(key('welcome_tagline'), findsOneWidget);
    final raw = tester.widget<RawImage>(
      find.descendant(
        of: find.byType(RamuriLogo),
        matching: find.byType(RawImage),
      ),
    );
    expect(raw.image, isNotNull, reason: 'Logo fehlt im ersten Bild');
  });

  testWidgets('erster Start (Englisch)', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'), welcome: true);
    expect(find.text('Run calmly.\nProgress clearly.'), findsOneWidget);
    expect(find.text("Let's go"), findsOneWidget);
    expect(
      find.text(
        'Your runs stay on your phone.\nNo account, no watch required.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('data'), findsNothing);
    await tester.tap(key('welcome_start'));
    await tester.pumpAndSettle();
    expect(key('setup_skip'), findsOneWidget);
  });

  testWidgets('Neustart nach abgeschlossener Einrichtung: kein Willkommen', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'), welcome: true);
    await d.confirmWelcome(tester);
    await d.skipSetup(tester);
    expect(key('home_screen'), findsOneWidget);
    await _restart(d, tester);
    expect(key('welcome_screen'), findsNothing);
    expect(key('setup_skip'), findsNothing);
    expect(key('home_screen'), findsOneWidget);
  });

  testWidgets(
    'Neustart mitten in der Einrichtung: Willkommen darf wiederkommen, '
    'bis sie abgeschlossen ist',
    (tester) async {
      final d = Device();
      await d.start(tester, const Locale('de'), welcome: true);
      await d.confirmWelcome(tester);
      expect(key('setup_skip'), findsOneWidget);
      await _restart(d, tester);
      expect(key('welcome_screen'), findsOneWidget);
      await d.confirmWelcome(tester);
      await d.skipSetup(tester);
      await _restart(d, tester);
      expect(key('welcome_screen'), findsNothing);
      expect(key('home_screen'), findsOneWidget);
    },
  );

  testWidgets('bestehende Nutzer sehen Willkommen nicht, auch nicht kurz', (
    tester,
  ) async {
    final d = Device();
    final s = await d.storage.open(_appKey);
    await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await d.start(tester, const Locale('de'), welcome: true);
    expect(key('welcome_screen'), findsNothing);
    expect(key('home_screen'), findsOneWidget);
  });

  for (final setupDone in [false, true]) {
    testWidgets('Einstellungen noch nicht gelesen '
        '(${setupDone ? 'Einrichtung erledigt' : 'erster Start'}): weder '
        'Willkommen noch Einrichtung blitzen auf', (tester) async {
      final d = Device();
      if (setupDone) {
        final s = await d.storage.open(_appKey);
        await s.settings.set(
          SettingKeys.setupDone,
          '1',
          at: DateTime.utc(2026),
        );
      }
      final gate = SettingsGateStorage(d.storage)..hold = Completer<void>();
      d.storageOverride = gate;
      await d.start(tester, const Locale('de'), welcome: true, settle: false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(key('welcome_screen'), findsNothing);
      expect(key('setup_skip'), findsNothing);
      expect(key('home_screen'), findsNothing);
      gate.hold!.complete();
      await tester.pumpAndSettle();
      expect(key(setupDone ? 'home_screen' : 'welcome_screen'), findsOneWidget);
    });
  }

  testWidgets('unterbrochener Lauf: der Dialog überdeckt Willkommen nicht, '
      'erscheint danach', (tester) async {
    final d = Device();
    final s = await d.storage.open(_appKey);
    await s.runs.create(startedAt: DateTime.utc(2026, 5, 31, 8));
    d.clock.advance(const Duration(hours: 1));
    await d.start(tester, const Locale('de'), welcome: true);
    expect(key('welcome_screen'), findsOneWidget);
    expect(key('recover_dialog'), findsNothing);
    await d.confirmWelcome(tester);
    expect(key('recover_dialog'), findsOneWidget);
  });
}
