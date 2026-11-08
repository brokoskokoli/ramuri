import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ramuri_card.dart';
import 'package:running_app/ui/ramuri_colors.dart';

import 'explanation_test.dart' show explainFromStats, seeded;
import 'history_summary_test.dart' show key;
import 'statistics_test.dart' show openStats;

void main() {
  group('Erklärung im Design (FR-0205)', () {
    for (final b in Brightness.values) {
      testWidgets('${b.name}: Karten in Themefarben, sechs Fragen sichtbar', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = b;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.view.physicalSize = const Size(411, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final d = await seeded(tester, deviceName: 'Brustgurt');
        await openStats(d, tester);
        await explainFromStats(tester, 'stat_explain_vo2_run');
        final colors = b == Brightness.light
            ? RamuriColors.light
            : RamuriColors.night;
        final cards = find.descendant(
          of: key('expl_body'),
          matching: find.byType(RamuriCard),
        );
        // Schätzungs-Hinweis vor der ersten Frage, dann sechs Fragen.
        expect(cards, findsNWidgets(7));
        for (final card in cards.evaluate()) {
          final material = tester.widget<Material>(
            find
                .descendant(
                  of: find.byWidget(card.widget),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(material.color, colors.surface);
        }
        for (final q in [
          'Aus welchen Daten wurde der Wert berechnet?',
          'Wie alt sind diese Daten?',
          'Wie viele geeignete Messungen gingen ein?',
          'Welche Methode wurde verwendet?',
          'Wie verlässlich ist das Ergebnis?',
          'Direkt gemessen oder geschätzt?',
        ]) {
          expect(find.text(q), findsOneWidget, reason: q);
        }
        expect(key('expl_a5_note'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
