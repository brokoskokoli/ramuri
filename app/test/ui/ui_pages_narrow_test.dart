import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:running_app/features/storage/storage_gate.dart';
import 'package:running_app/features/storage/storage_start.dart';
import 'package:running_app/features/transparency/value_explanation_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import '../app_harness.dart';

/// WP14 Teil D1: Seiten ohne eigenen Screen laufen bei 360 dp Breite und
/// Textskalierung 1,5 weder über (Overflow-Ausnahme) noch mit zu kleinen
/// Bedienelementen (mindestens 48 dp, FR-0205).
Future<void> _narrow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.5;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpAndSettle();
}

/// Scrollt die Seite durch und prüft Überlauf und Zielgrößen jedes Bildes.
Future<void> _scan(
  WidgetTester tester,
  String page, {
  bool buttons = true,
}) async {
  var checked = 0;
  for (var i = 0; i < 8; i++) {
    expect(tester.takeException(), isNull, reason: '$page, Schritt $i');
    for (final type in [FilledButton, OutlinedButton, TextButton, FilterChip]) {
      for (final e in find.byType(type).evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, greaterThanOrEqualTo(48), reason: '$page $type');
        checked++;
      }
    }
    await tester.dragFrom(const Offset(180, 500), const Offset(0, -400));
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull, reason: page);
  // Gegenprobe: die Prüfung hat wirklich Bedienelemente gesehen.
  if (buttons) expect(checked, greaterThan(0), reason: page);
}

void main() {
  for (final locale in const [Locale('de'), Locale('en')]) {
    final l = locale.languageCode;
    testWidgets('Einrichtung, 360 dp, Skalierung 1,5, $l', (tester) async {
      final d = Device();
      await d.start(tester, locale);
      await _narrow(tester);
      await _scan(tester, 'setup');
    });

    for (final entry in {
      'home_profile': 'profile',
      'home_settings': 'settings',
      'overview_zones': 'zones',
      'overview_permissions': 'permissions',
      'overview_sensors': 'sensors',
      'overview_data': 'data',
    }.entries) {
      testWidgets('${entry.value}, 360 dp, Skalierung 1,5, $l', (tester) async {
        final d = Device();
        await d.start(tester, locale);
        await d.skipSetup(tester);
        await openOverview(tester);
        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();
        await _narrow(tester);
        await _scan(tester, entry.value);
      });
    }

    for (final screen in <String, Widget Function()>{
      'not_openable': () => NotOpenableScreen(
        state: const StorageNotOpenableState(
          StorageNotOpenableCause.keyMissing,
        ),
        onRetry: () {},
        onReset: () {},
        onRestoreFromArchive: () {},
      ),
      'encryption_inactive': () => EncryptionInactiveScreen(onRetry: () {}),
    }.entries) {
      testWidgets('${screen.key}, 360 dp, Skalierung 1,5, $l', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: RamuriTheme.light,
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: screen.value(),
          ),
        );
        await _narrow(tester);
        await _scan(tester, screen.key);
      });
    }

    testWidgets('Erklärung, 360 dp, Skalierung 1,5, $l', (tester) async {
      final d = Device();
      await d.start(tester, locale);
      await d.skipSetup(tester);
      // Nicht abwarten: das Future endet erst beim Zurück.
      unawaited(
        Navigator.of(tester.element(find.byKey(const Key('home_screen'))))
            .push<void>(
              MaterialPageRoute(
                builder: (_) => ValueExplanationScreen(
                  session: d.session,
                  valueKey: classificationKey,
                ),
              ),
            ),
      );
      await tester.pumpAndSettle();
      await _narrow(tester);
      await _scan(tester, 'explanation', buttons: false);
    });
  }
}
