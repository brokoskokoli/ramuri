import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/statistics/fitness_explanations.dart';

import 'app_harness.dart';
import 'progress_cards_test.dart' show stored;

// WP23 Teil D2, Fortschritt: Erklärungen FR-0180 (Fitnessentwicklung,
// Datenqualität), nur mit Daten (FR-0181). Alle Werte sind erfunden.

Finder k(String key) => find.byKey(Key(key));

final _today = DateTime.utc(2026, 6, 10);

RunEstimate _est(int id, String day, double? v) => RunEstimate(
  runId: id,
  endedAt: DateTime.utc(2026, 6, 1),
  day: day,
  value: stored(vo2maxRunValueKey, v),
);

FitnessOverview _overview({
  List<RunEstimate> runs = const [],
  ComputedValue? longTerm,
  ComputedValue? efficiency,
}) => FitnessOverview(
  runEstimates: runs,
  longTerm: longTerm,
  efficiency: efficiency,
  pendingRuns: 0,
  day: '2026-06-10',
);

Future<void> _pump(
  WidgetTester tester,
  FitnessOverview f, {
  String locale = 'de',
  Brightness brightness = Brightness.light,
  double width = 411,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    localizedApp(
      locale: Locale(locale),
      brightness: brightness,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FitnessExplanationCard(fitness: f, today: _today),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _line(WidgetTester tester, int i) =>
    tester.widget<Text>(k('stat_explain_line_$i')).data!;

void main() {
  group('Fitnessentwicklung', () {
    testWidgets('gestiegen: Werte, Zeitraum und Zahl der Läufe aus den Daten', (
      tester,
    ) async {
      await _pump(
        tester,
        _overview(
          runs: [
            _est(1, '2026-05-10', 43.04),
            _est(2, '2026-05-30', 44),
            _est(3, '2026-06-08', 46.04),
          ],
        ),
      );
      expect(k('stat_explain_card'), findsOneWidget);
      expect(
        _line(tester, 0),
        contains(
          'von 43,0 auf 46,0 gestiegen. Die Schätzung beruht auf 3 '
          'Läufen.',
        ),
      );
    });

    testWidgets('gesunken und unverändert (en)', (tester) async {
      await _pump(
        tester,
        _overview(runs: [_est(1, '2026-05-20', 46), _est(2, '2026-06-08', 44)]),
        locale: 'en',
      );
      expect(_line(tester, 0), contains('fell from 46.0 to 44.0'));
      expect(_line(tester, 0), contains('based on 2 runs'));
      await _pump(
        tester,
        _overview(runs: [_est(1, '2026-05-20', 45), _est(2, '2026-06-08', 45)]),
        locale: 'en',
      );
      expect(_line(tester, 0), contains('45.0 between'));
      expect(_line(tester, 0), contains('unchanged'));
    });

    testWidgets('weniger als 2 Läufe, zu alte Läufe, Läufe ohne Wert: keine '
        'Erklärung, keine Karte', (tester) async {
      for (final f in [
        _overview(runs: [_est(1, '2026-06-08', 46)]),
        _overview(runs: [_est(1, '2026-03-01', 40), _est(2, '2026-06-08', 46)]),
        _overview(
          runs: [_est(1, '2026-05-20', null), _est(2, '2026-06-08', 46)],
        ),
        _overview(),
      ]) {
        await _pump(tester, f);
        expect(k('stat_explain_card'), findsNothing);
      }
    });
  });

  group('Datenqualität', () {
    testWidgets('vorläufig: Beleg aus dem Wert; guter Wert: nichts', (
      tester,
    ) async {
      await _pump(
        tester,
        _overview(
          longTerm: stored(
            vo2maxLongTermValueKey,
            45,
            quality: ValueQuality.provisional,
            count: 4,
          ),
          efficiency: stored(aerobicEfficiencyValueKey, 1.2),
        ),
      );
      expect(_line(tester, 0), contains('vorläufig'));
      expect(_line(tester, 0), contains('4 Messwerten'));
      expect(k('stat_explain_line_1'), findsNothing);
    });

    testWidgets('fehlender Wert nennt den gespeicherten Grund (en, dunkel, '
        '320 dp, Schrift 2.0)', (tester) async {
      await _pump(
        tester,
        _overview(
          efficiency: stored(
            aerobicEfficiencyValueKey,
            null,
            reason: UnavailableReason.noHeartRate,
          ),
        ),
        locale: 'en',
        brightness: Brightness.dark,
        width: 320,
        scale: 2,
      );
      expect(_line(tester, 0), contains('There is no value.'));
      expect(tester.takeException(), isNull);
    });
  });

  test('neue Texte: keine Diagnose, kein festgestellter Erholungszustand', () {
    final bad = RegExp(
      r'erholt|ermüd|erholungszustand|sicher|verletz|überlast|krank|'
      r'bereit|diagnose gestellt|recovered|fatigue|recovery state|'
      r'\bsafe\b|injur|overload|\bill\b|\bready\b',
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final locale in ['de', 'en']) {
      final json = jsonDecode(
        File('lib/l10n/app_$locale.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final e in json.entries) {
        final key = e.key;
        if (key.startsWith('@') || e.value is! String) continue;
        final mine =
            key.startsWith('recovery') ||
            key.startsWith('homePause') ||
            key.startsWith('homeWarnReminder') ||
            key.startsWith('progressExplain');
        // Die Überschrift trägt das Wort nur als Kartentitel (Design).
        if (!mine || key == 'recoveryTitle') continue;
        if (bad.hasMatch(e.value as String)) hits.add('$locale/$key');
      }
    }
    expect(hits, isEmpty);
  });
}
