import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

Future<void> _open(Device d, WidgetTester tester) async {
  await d.skipSetup(tester);
  await tester.tap(find.byKey(const Key('home_settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings_zones')));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, List<String> v) async {
  for (var i = 0; i < v.length; i++) {
    await tester.enterText(find.byKey(Key('zone_bound_$i')), v[i]);
  }
}

void main() {
  testWidgets('Zoneneditor: Standard, Näherungshinweis, speichern (FR-0061)', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await _open(d, tester);
    expect(find.textContaining('Näherung'), findsOneWidget);
    expect(find.textContaining('keine gemessenen Schwellen'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('zone_bound_1')))
          .controller!
          .text,
      '60',
    );

    await _enter(tester, ['40', '50', '60', '70', '80', '100']);
    await tester.tap(find.byKey(const Key('zones_save')));
    await tester.pumpAndSettle();
    expect(
      await d.session.settings.get(SettingKeys.reserveZoneBounds),
      '40,50,60,70,80,100',
    );
    expect(find.byKey(const Key('zones_error')), findsNothing);
  });

  testWidgets('Zoneneditor: ungültig wird gemeldet und nicht gespeichert', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await _open(d, tester);

    await _enter(tester, ['50', '70', '60', '80', '90', '100']);
    await tester.tap(find.byKey(const Key('zones_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Limit 3 must be greater'), findsOneWidget);
    expect(await d.session.settings.get(SettingKeys.reserveZoneBounds), isNull);

    await _enter(tester, ['50', '60', '70', '80', '90', '101']);
    await tester.tap(find.byKey(const Key('zones_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Limit 6: only 0 to 100'), findsOneWidget);

    await _enter(tester, ['50', '60', '', '80', '90', '100']);
    await tester.tap(find.byKey(const Key('zones_save')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Limit 3: please enter a whole number'),
      findsOneWidget,
    );
    expect(await d.session.settings.get(SettingKeys.reserveZoneBounds), isNull);
  });

  testWidgets('Zoneneditor: Zurücksetzen und gespeicherte Werte beim Öffnen', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await _open(d, tester);
    await _enter(tester, ['40', '50', '60', '70', '80', '100']);
    await tester.tap(find.byKey(const Key('zones_save')));
    await tester.pumpAndSettle();

    // Seite neu öffnen: gespeicherte Werte stehen drin.
    await tester.tap(find.byTooltip('Zurück'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_zones')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('zone_bound_0')))
          .controller!
          .text,
      '40',
    );

    await tester.tap(find.byKey(const Key('zones_reset')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('zone_bound_0')))
          .controller!
          .text,
      '50',
    );
    expect(
      await d.session.settings.get(SettingKeys.reserveZoneBounds),
      '50,60,70,80,90,100',
    );
  });
}
