import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/overview_screen.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show started;

/// Neuberechnung, die nach Belieben als laufend gilt.
class _BusyController extends RecalculationController {
  _BusyController(super.service);

  bool running = true;

  @override
  bool get busy => running;
}

void main() {
  testWidgets('Übersicht: jede bisher erreichbare Seite ist erreichbar', (
    tester,
  ) async {
    await started(tester);
    // Heute zeigt nur noch das Profil-Symbol (48 dp), keine Einträge.
    expect(key('home_settings'), findsNothing);
    expect(tester.getSize(key('home_overview')), const Size(48, 48));
    final targets = <String, Finder>{
      'home_profile': key('profile_max'),
      'home_settings': key('settings_unit'),
      'overview_sensors': find.widgetWithText(AppBar, 'Pulssensoren'),
      'overview_zones': key('zone_bound_0'),
      'overview_permissions': find.widgetWithText(AppBar, 'Berechtigungen'),
      'overview_data': find.widgetWithText(AppBar, 'Daten'),
      'overview_about': key('about_version'),
    };
    for (final e in targets.entries) {
      await openOverview(tester);
      await tester.tap(key(e.key));
      await tester.pumpAndSettle();
      expect(e.value, findsOneWidget, reason: e.key);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(key('overview_about'), findsOneWidget, reason: e.key);
    }
    // Die Einstellungen führen nicht mehr doppelt dorthin.
    await tester.tap(key('home_settings'));
    await tester.pumpAndSettle();
    for (final k in [
      'settings_sensors',
      'settings_zones',
      'settings_permissions',
      'settings_data',
    ]) {
      expect(key(k), findsNothing, reason: k);
    }
  });

  testWidgets('Entwicklermodus aus: kein Eintrag Entwicklereinstellungen', (
    tester,
  ) async {
    await started(tester);
    await openOverview(tester);
    expect(key('overview_about'), findsOneWidget);
    expect(key('overview_developer'), findsNothing);
    expect(find.text('Entwicklereinstellungen'), findsNothing);
  });

  testWidgets('10 Tipps auf Über → zurück: Eintrag direkt nach Über, öffnet '
      'die Seite; dort aus → Seite zu, Eintrag weg', (tester) async {
    final d = await started(tester);
    final mode = SettingsDeveloperModeStore(d.session.settings, d.clock);
    await openOverview(tester);
    await tester.tap(key('overview_about'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.tap(key('about_version'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(key('about_dev_badge'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Ohne Neustart: der Eintrag steht direkt unter „Über“.
    expect(key('overview_developer'), findsOneWidget);
    expect(find.text('Entwicklereinstellungen'), findsOneWidget);
    final tiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => t.key ?? (t.title! as Text).data)
        .toList();
    final about = find.descendant(
      of: key('overview_about'),
      matching: find.byType(ListTile),
    );
    final dev = find.descendant(
      of: key('overview_developer'),
      matching: find.byType(ListTile),
    );
    final all = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(
      all.indexOf(tester.widget<ListTile>(dev)),
      all.indexOf(tester.widget<ListTile>(about)) + 1,
      reason: '$tiles',
    );
    expect(
      tester
          .widget<Icon>(
            find
                .descendant(
                  of: key('overview_developer'),
                  matching: find.byType(Icon),
                )
                .first,
          )
          .icon,
      Icons.developer_mode_outlined,
    );

    await tester.tap(key('overview_developer'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Entwicklereinstellungen'), findsOne);
    expect(key('about_dev_switch'), findsOneWidget);
    expect(key('about_ppg_camera_card'), findsOneWidget);
    expect(key('dev_ppg_diag_card'), findsOneWidget);
    expect(key('about_pairs'), findsOneWidget);

    await tester.tap(key('about_dev_switch'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(mode.read), isFalse);
    // Seite zu, zurück in der Übersicht, Eintrag weg.
    expect(key('about_dev_switch'), findsNothing);
    expect(key('overview_about'), findsOneWidget);
    expect(key('overview_developer'), findsNothing);
  });

  testWidgets(
    'Lizenzen: Über → Lizenzen öffnet die Seite mit Sora und Manrope',
    (tester) async {
      await started(tester);
      registerFontLicenses();
      await openOverview(tester);
      await tester.tap(key('overview_about'));
      await tester.pumpAndSettle();
      await tester.tap(key('about_licenses'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('Sora'), findsOneWidget);
      expect(find.text('Manrope'), findsOneWidget);
    },
  );

  testWidgets('Sperre: Sensoren, Zonen, Berechtigungen, Daten während der '
      'Neuberechnung aus; Profil und Einstellungen offen', (tester) async {
    final d = await started(tester);
    final controller = _BusyController(
      RecalculationService(
        session: d.session,
        clock: d.clock,
        calculation: ValueCalculationService(
          session: d.session,
          clock: d.clock,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: OverviewScreen(
          session: d.session,
          clock: d.clock,
          permissions: d.permissions,
          recalculation: controller,
          sensors: d.sensors,
        ),
      ),
    );
    VoidCallback? onTap(String k) => tester
        .widget<ListTile>(
          find.descendant(of: key(k), matching: find.byType(ListTile)),
        )
        .onTap;
    for (final k in [
      'overview_sensors',
      'overview_zones',
      'overview_permissions',
      'overview_data',
    ]) {
      expect(onTap(k), isNull, reason: k);
    }
    expect(onTap('home_profile'), isNotNull);
    expect(onTap('home_settings'), isNotNull);
    expect(onTap('overview_about'), isNotNull);
    controller.running = false;
    controller.notifyListeners();
    await tester.pump();
    expect(onTap('overview_data'), isNotNull);
  });
}
