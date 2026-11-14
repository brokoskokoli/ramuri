import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/profile/profile_screen.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure/measure_support.dart';

// Synthetische Werte. Beleg zu profile_screen.dart (dispose): Das Aufräumen der
// Rückmeldung darf im Baumabbau keinen setState auslösen.

Future<void> _open(WidgetTester tester, {required bool popFirst}) async {
  // Bedienungshilfe an: Der ScaffoldMessenger blendet Meldungen ohne Animation
  // aus, der Status "dismissed" kommt dann sofort (wie mit abgeschalteten
  // Animationen auf dem Emulator).
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(accessibleNavigation: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final session = await tester.runAsync(() => FakeStorage().open(testKey));
  final clock = FakeClock(DateTime.utc(2026, 11, 10, 12));
  final recalc = RecalculationController(
    RecalculationService(
      session: session!,
      clock: clock,
      calculation: ValueCalculationService(session: session, clock: clock),
    ),
  );
  addTearDown(recalc.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      theme: RamuriTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          key: const Key('open'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProfileScreen(
                session: session,
                clock: clock,
                recalculation: recalc,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  // Rückmeldung wie nach dem Speichern, noch sichtbar beim Verlassen.
  ScaffoldMessenger.of(tester.element(find.byType(ProfileScreen)))
      .showSnackBar(const SnackBar(content: Text('gespeichert')));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('gespeichert'), findsOneWidget);
  if (popFirst) {
    Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
  } else {
    // Ganzer Baum fällt weg (wie am Testende der Integrationstests).
    await tester.pumpWidget(const SizedBox());
  }
}

void main() {
  testWidgets('Verlassen mit offener Rückmeldung: kein Fehler, Meldung weg', (
    tester,
  ) async {
    await _open(tester, popFirst: true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('gespeichert'), findsNothing);
  });

  testWidgets('Baumabbau mit offener Rückmeldung: kein Fehler', (tester) async {
    await _open(tester, popFirst: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
