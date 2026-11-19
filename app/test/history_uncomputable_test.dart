import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show openHistory, seedRun, started;

/// FR-0219: Ein Lauf, dessen Werte sich nach drei Versuchen nicht berechnen
/// ließen, ist in der Historie gekennzeichnet; die Detailansicht nennt den
/// Grund. Normale Läufe bleiben unverändert.
const _texts = {
  'de': (
    row: 'nicht berechenbar',
    detail:
        'Die Werte dieses Laufs ließen sich nach drei Versuchen nicht '
        'berechnen. Die Aufzeichnung ist vollständig gespeichert. Ein neuer '
        'Versuch folgt mit „Neu berechnen“ in den Einstellungen oder wenn '
        'eine neue App-Version die Berechnung ändert.',
  ),
  'en': (
    row: 'not computable',
    detail:
        'The values of this run could not be calculated after three '
        'attempts. The recording is fully saved. It will be tried again with '
        '“Recalculate” in the settings or when a new app version changes the '
        'calculation.',
  ),
};

/// Zwei Läufe; der erste gilt nach drei gezählten Fehlversuchen als nicht
/// berechenbar.
Future<(int, int)> _seed(Device d, {int failures = 3}) async {
  final broken = await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
  final normal = await seedRun(d.session, DateTime.utc(2030, 1, 2, 8));
  final counter = CalculationFailures(
    settings: d.session.settings,
    clock: d.clock,
  );
  for (var i = 0; i < failures; i++) {
    await counter.recordFailure(broken);
  }
  return (broken, normal);
}

Future<void> _openDetail(WidgetTester tester, int id) async {
  await tester.ensureVisible(key('history_run_$id'));
  await tester.pumpAndSettle();
  await tester.tap(key('history_run_$id'));
  await tester.pumpAndSettle();
}

void main() {
  for (final MapEntry(key: locale, value: t) in _texts.entries) {
    group('nicht berechenbarer Lauf ($locale)', () {
      testWidgets('Historie kennzeichnet nur diesen Lauf', (tester) async {
        final d = await started(tester, locale: locale);
        final (broken, normal) = await _seed(d);
        await openHistory(d, tester);
        expect(key('history_run_$broken'), findsOneWidget);
        expect(key('history_run_$normal'), findsOneWidget);
        final mark = key('history_uncomputable_$broken');
        expect(mark, findsOneWidget);
        expect((mark.evaluate().single.widget as Text).data, t.row);
        expect(key('history_uncomputable_$normal'), findsNothing);
        expect(find.text(t.row), findsOneWidget);
      });

      testWidgets('Detailansicht nennt den Satz', (tester) async {
        final d = await started(tester, locale: locale);
        final (broken, _) = await _seed(d);
        await openHistory(d, tester);
        await _openDetail(tester, broken);
        expect(key('detail_uncomputable'), findsOneWidget);
        expect(find.text(t.detail), findsOneWidget);
      });

      testWidgets('normaler Lauf: Detailansicht ohne den Satz', (tester) async {
        final d = await started(tester, locale: locale);
        final (_, normal) = await _seed(d);
        await openHistory(d, tester);
        await _openDetail(tester, normal);
        expect(key('detail_uncomputable'), findsNothing);
        expect(find.text(t.detail), findsNothing);
      });

      testWidgets('zwei Fehlversuche: noch keine Kennzeichnung', (
        tester,
      ) async {
        final d = await started(tester, locale: locale);
        final (broken, _) = await _seed(d, failures: 2);
        await openHistory(d, tester);
        expect(key('history_uncomputable_$broken'), findsNothing);
        await _openDetail(tester, broken);
        expect(key('detail_uncomputable'), findsNothing);
      });
    });
  }
}
