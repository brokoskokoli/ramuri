import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/app_shell.dart';

import 'app_harness.dart';
import 'history_summary_test.dart'
    show key, openHistory, seedRun, started, text, walk;

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
