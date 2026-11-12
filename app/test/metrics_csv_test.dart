import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// WP25 D: Einstieg „Zusatzmetriken exportieren“ unter „Daten“ (FR-0184).
Future<Device> _openData(WidgetTester tester, String locale) async {
  final d = Device();
  await d.start(tester, Locale(locale));
  await d.skipSetup(tester);
  final run = await d.session.runs.create(
    startedAt: DateTime.utc(2030, 1, 1, 8),
  );
  await d.session.values.createOriginals(ValueOwner.run(run.id), [
    ComputedValue(
      key: 'aerobic_efficiency',
      value: 1.5,
      unit: 'm/beat',
      computedAt: DateTime.utc(2030, 1, 1, 9),
      measurementCount: 4,
      sources: const ['strap'],
      method: 'ae',
      methodVersion: 1,
      parameterVersion: 1,
      quality: ValueQuality.good,
    ),
  ]);
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('overview_data')));
  await tester.pumpAndSettle();
  return d;
}

void main() {
  for (final locale in ['de', 'en']) {
    testWidgets('Teilen liefert die CSV mit Dezimalpunkt ($locale)', (
      tester,
    ) async {
      final d = await _openData(tester, locale);
      await tester.tap(find.byKey(const Key('metrics_export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('metrics_share')));
      await tester.pumpAndSettle();
      expect(d.fileHandoff.saved, isEmpty);
      final file = d.fileHandoff.shared.single;
      expect(file.mimeType, 'text/csv');
      expect(file.fileName, startsWith('running-metriken-'));
      final text = utf8.decode(file.bytes!);
      expect(text, startsWith('format_version,run_id,'));
      expect(text, contains(',original,aerobic_efficiency,1.5,m/beat,good,'));
      expect(text, contains(',current,aerobic_efficiency,1.5,'));
      expect(text, isNot(contains('1,5')));
    });
  }

  testWidgets('Speichern geht an das Dokumentenziel, Abbruch bleibt still', (
    tester,
  ) async {
    final d = await _openData(tester, 'de');
    await tester.tap(find.byKey(const Key('metrics_export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metrics_cancel')));
    await tester.pumpAndSettle();
    expect(d.fileHandoff.shared, isEmpty);
    expect(d.fileHandoff.saved, isEmpty);
    await tester.tap(find.byKey(const Key('metrics_export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metrics_save')));
    await tester.pumpAndSettle();
    expect(d.fileHandoff.saved, hasLength(1));
    expect(find.text('Datei gespeichert.'), findsOneWidget);
  });

  testWidgets('Fehler der Übergabe: Meldung ohne Inhalte', (tester) async {
    final d = await _openData(tester, 'de');
    d.fileHandoff.nextResult = FileHandoffResult.failed;
    await tester.tap(find.byKey(const Key('metrics_export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metrics_share')));
    await tester.pumpAndSettle();
    expect(find.text('Export fehlgeschlagen.'), findsOneWidget);
  });
}
