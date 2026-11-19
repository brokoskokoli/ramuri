import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/app_shell.dart';

import 'app_harness.dart';
import 'history_summary_test.dart'
    show openHistory, seedRun, started, text, walk;

/// Zählt die Aufrufe von `SystemNavigator.pop` (App verlassen).
List<int> _exits(WidgetTester tester) {
  final exits = [0];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') exits[0]++;
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return exits;
}

const _tabKeys = [
  'home_today',
  'home_plan',
  'home_history',
  'home_statistics',
  'home_profile_tab',
];

/// Prüft jede Beschriftung der Leiste: eine Zeile, nicht gekürzt, ganz in
/// ihrem Eintrag und in der Leiste; jeder Eintrag mindestens 48 dp.
void _expectLabelsFit(WidgetTester tester, String reason) {
  final bar = tester.getRect(find.byType(NavigationBar));
  for (final k in _tabKeys) {
    final entry = find.byKey(Key(k));
    final box = tester.getRect(entry);
    expect(box.width, greaterThanOrEqualTo(48), reason: '$reason $k');
    expect(box.height, greaterThanOrEqualTo(48), reason: '$reason $k');
    final label = tester.widget<NavigationDestination>(entry).label;
    final text = find.descendant(of: entry, matching: find.text(label));
    expect(text, findsOneWidget, reason: '$reason $k');
    final p = tester.renderObject<RenderParagraph>(text);
    expect(p.didExceedMaxLines, isFalse, reason: '$reason $label');
    // Kein Umbruch: die Zeile passt in voller Breite.
    expect(
      p.size.width,
      greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.01),
      reason: '$reason $label',
    );
    final r = tester.getRect(text);
    expect(r.left, greaterThanOrEqualTo(box.left), reason: '$reason $label');
    expect(r.right, lessThanOrEqualTo(box.right), reason: '$reason $label');
    expect(r.top, greaterThanOrEqualTo(bar.top), reason: '$reason $label');
    expect(r.bottom, lessThanOrEqualTo(bar.bottom), reason: '$reason $label');
  }
}

void main() {
  testWidgets('Navigation: Heute, Verlauf, Fortschritt (FR-0208)', (
    tester,
  ) async {
    await started(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Heute'),
      ),
      findsOneWidget,
    );
    expect(key('home_screen'), findsOneWidget);
    await tester.tap(key('home_history'));
    await tester.pumpAndSettle();
    expect(key('home_screen'), findsNothing);
    expect(key('history_empty'), findsOneWidget);
    await tester.tap(key('home_statistics'));
    await tester.pumpAndSettle();
    expect(key('stat_runs_value'), findsOneWidget);
    await tester.tap(key('home_today'));
    await tester.pumpAndSettle();
    expect(key('home_screen'), findsOneWidget);
  });

  testWidgets('Profil ganz rechts zeigt die Übersicht; Zurück führt zu Heute', (
    tester,
  ) async {
    await started(tester);
    final exits = _exits(tester);
    final keys = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => (d.key! as ValueKey<String>).value)
        .toList();
    expect(keys.last, 'home_profile_tab');
    final profile = find.byKey(const Key('home_profile_tab'));
    expect(
      find.descendant(of: profile, matching: find.text('Profil')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: profile,
        matching: find.byIcon(Icons.person_outline_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(profile);
    await tester.pumpAndSettle();
    // Die Übersicht mit ihren Einträgen, die Leiste bleibt.
    expect(key('home_screen'), findsNothing);
    expect(find.text('Übersicht'), findsOneWidget);
    expect(key('home_profile'), findsOneWidget);
    expect(key('home_settings'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    // Unterseiten liegen als Vollbild darüber, wie über das Symbol auf Heute.
    await tester.tap(key('home_settings'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(key('home_settings'), findsOneWidget);
    // Zurück aus dem Bereich: Heute, nicht aus der App.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(key('home_screen'), findsOneWidget);
    expect(key('home_settings'), findsNothing);
    expect(exits[0], 0);
    // Das Symbol auf Heute führt zur selben Übersicht.
    await openOverview(tester);
    expect(find.text('Übersicht'), findsOneWidget);
    expect(key('home_settings'), findsOneWidget);
  });

  for (final locale in ['de', 'en']) {
    for (final dark in [false, true]) {
      testWidgets('360 dp, Schrift 1,3, $locale, ${dark ? 'dunkel' : 'hell'}: '
          'fünf Beschriftungen vollständig (FR-0208)', (tester) async {
        await loadManrope(tester);
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await started(tester, locale: locale);
        tester.view.physicalSize = const Size(360, 780);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(NavigationBar))).brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        // Jeder Bereich einmal gewählt: die fette Beschriftung ist breiter.
        for (final k in _tabKeys) {
          await tester.tap(find.byKey(Key(k)));
          await tester.pumpAndSettle();
          _expectLabelsFit(tester, k);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('breite Leiste, Schrift 1,3: Beschriftung nicht verkleinert', (
    tester,
  ) async {
    await loadManrope(tester);
    await started(tester);
    tester.view.physicalSize = const Size(800, 1200);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final label = find.descendant(
      of: find.byKey(const Key('home_statistics')),
      matching: find.text('Fortschritt'),
    );
    expect(
      MediaQuery.textScalerOf(tester.element(label)).scale(12),
      moreOrLessEquals(12 * 1.3),
    );
    _expectLabelsFit(tester, 'breit');
  });

  group('Schriftfaktor der Leiste (FR-0208)', () {
    final progress = find.descendant(
      of: find.byKey(const Key('home_statistics')),
      matching: find.text('Fortschritt'),
    );

    /// Wirksamer Faktor der Beschriftung „Fortschritt“ (Grundgröße 12).
    double factor(WidgetTester tester) =>
        MediaQuery.textScalerOf(tester.element(progress)).scale(12) / 12;

    /// Startet die App in [width] dp mit Schrift [scale], „Fortschritt“
    /// gewählt (fett, also am breitesten).
    Future<void> open(WidgetTester tester, double width, double scale) async {
      await loadManrope(tester);
      await started(tester);
      tester.view.physicalSize = Size(width, 780);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home_statistics')));
      await tester.pumpAndSettle();
    }

    testWidgets('360 dp, Schrift 1,3: verkleinert, aber über Grundschrift', (
      tester,
    ) async {
      await open(tester, 360, 1.3);
      expect(factor(tester), greaterThan(1.0));
      expect(factor(tester), lessThan(1.3));
      _expectLabelsFit(tester, '1,3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('360 dp, Schrift 2,0: wie bei 1,3, einzeilig, kein Überlauf', (
      tester,
    ) async {
      await open(tester, 360, 1.3);
      final at13 = factor(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pumpAndSettle();
      expect(factor(tester), moreOrLessEquals(at13, epsilon: 0.01));
      expect(factor(tester), greaterThan(1.0));
      _expectLabelsFit(tester, '2,0');
      expect(tester.getSize(find.byType(NavigationBar)).height, 72);
      expect(tester.takeException(), isNull);
    });

    testWidgets('300 dp, Schrift 1,0: Grundschrift, „…“, voller Text im '
        'Tooltip und für Screenreader', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, 300, 1.0);
      expect(factor(tester), 1.0);
      final p = tester.renderObject<RenderParagraph>(progress);
      // Einzeilig und mit „…“ gekürzt.
      expect(p.didExceedMaxLines, isTrue);
      expect(p.overflow, TextOverflow.ellipsis);
      final line = p.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 'Fortschritt'.length),
      );
      expect(line.map((b) => b.top).toSet(), hasLength(1));
      final box = tester.getRect(find.byKey(const Key('home_statistics')));
      final r = tester.getRect(progress);
      expect(r.left, greaterThanOrEqualTo(box.left));
      expect(r.right, lessThanOrEqualTo(box.right));
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('home_statistics')),
          matching: find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Fortschritt',
          ),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Fortschritt')), findsWidgets);
      // Auch nicht gewählt (normale Stärke) einzeilig mit „…“.
      await tester.tap(find.byKey(const Key('home_today')));
      await tester.pumpAndSettle();
      final plain = tester.renderObject<RenderParagraph>(progress);
      expect(plain.didExceedMaxLines, isTrue);
      expect(plain.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('300 dp, Schrift 0,85: nicht über die Systemschrift gehoben', (
      tester,
    ) async {
      await open(tester, 300, 0.85);
      expect(factor(tester), lessThanOrEqualTo(0.85 + 1e-9));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'Zurück: aus Verlauf und Fortschritt zu Heute, von Heute aus der App',
    (tester) async {
      await started(tester);
      final exits = _exits(tester);
      for (final tab in ['home_history', 'home_statistics']) {
        await tester.tap(key(tab));
        await tester.pumpAndSettle();
        expect(key('home_screen'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(key('home_screen'), findsOneWidget, reason: tab);
        expect(exits[0], 0, reason: tab);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exits[0], 1);
    },
  );

  testWidgets('Lauf, Übersicht und Detail liegen ohne Leiste darüber', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await seedRun(d.session, DateTime.utc(2026, 5, 30, 8));
    // Lauf (Vollbild über den Root-Navigator)
    await tester.tap(key('home_start_run'));
    await tester.pumpAndSettle();
    await tester.tap(key('run_start_ready'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await walk(d, tester, 60);
    await tester.tap(key('run_pause'));
    await tester.pump();
    await tester.tap(key('run_finish'));
    await tester.pumpAndSettle();
    await tester.tap(key('run_finish_confirm'));
    await tester.pumpAndSettle();
    // Zusammenfassung
    expect(find.byType(NavigationBar), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    // Übersicht
    await openOverview(tester);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Detail
    await openHistory(d, tester);
    await tester.tap(key('history_run_$id'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(key('history_run_$id'), findsOneWidget);
  });

  testWidgets('Daten ändern sich bei offenem Bereich: neue Zahl sichtbar', (
    tester,
  ) async {
    final d = await started(tester);
    d.clock.set(DateTime.utc(2026, 6, 3, 12));
    await tester.tap(key('home_history'));
    await tester.pumpAndSettle();
    expect(key('history_empty'), findsOneWidget);
    final shell = tester.widget<AppShell>(find.byType(AppShell));
    // Wie die Berechnung nach einem Lauf, Löschen oder Import: alle Schreiber
    // laufen durch `exclusive` und melden danach die Änderung.
    late int id;
    await shell.recalculation.exclusive(() async {
      id = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
    });
    await tester.pumpAndSettle();
    expect(key('history_empty'), findsNothing);
    expect(text('history_distance_$id'), isNotEmpty);

    // Auch ohne Meldung: ein Wechsel baut den Bereich neu auf (kein
    // IndexedStack), sonst bliebe der alte Stand stehen.
    await tester.tap(key('home_today'));
    await tester.pumpAndSettle();
    final other = await seedRun(d.session, DateTime.utc(2026, 6, 2, 8));
    await tester.tap(key('home_history'));
    await tester.pumpAndSettle();
    expect(key('history_run_$other'), findsOneWidget);
    await tester.tap(key('home_statistics'));
    await tester.pumpAndSettle();
    expect(text('stat_runs_value'), '2');
    await shell.recalculation.exclusive(() async {
      await seedRun(d.session, DateTime.utc(2026, 6, 3, 8));
    });
    await tester.pumpAndSettle();
    expect(text('stat_runs_value'), '3');
  });
}
