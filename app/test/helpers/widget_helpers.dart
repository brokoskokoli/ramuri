import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gemeinsame Hilfen für Widget-Tests. Ein Name je Bedeutung: Varianten mit
/// anderem Verhalten haben eigene Namen, keine Schalter.

/// Finder für das Widget mit `Key(k)`.
Finder keyed(String k) => find.byKey(Key(k));

/// Scrollt das Widget mit `Key(key)` sichtbar, tippt es an und wartet mit
/// `pumpAndSettle`.
Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(keyed(key));
  await tester.tap(keyed(key));
  await tester.pumpAndSettle();
}

/// Wie [tapKey] für einen beliebigen Finder, wartet aber zusätzlich vor dem
/// Tippen (Scroll-Animation abwarten).
Future<void> tapFinderAfterSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Lässt Quelle und Kacheln (echte Zeit) zur Ruhe kommen: wartet, bis
/// [requests] sechs Runden lang unverändert bleibt.
Future<void> settleUntilRequestsStable(
  WidgetTester tester,
  int Function() requests,
) async {
  var last = -1;
  var stable = 0;
  while (stable < 6) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    stable = requests() == last ? stable + 1 : 0;
    last = requests();
  }
}

/// Lässt Lesen, Aufnahme und Speichern (echte Zeit) zur Ruhe kommen: feste
/// zwölf Runden, ohne Bedingung.
Future<void> settleRealTimeFixed(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}
