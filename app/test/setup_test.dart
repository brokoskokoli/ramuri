import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

void main() {
  testWidgets('erster Start: Einrichtung angeboten, überspringen, Lauf-Start '
      'erreichbar, zweiter Start ohne Einrichtung (FR-0001)', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    expect(find.byKey(const Key('setup_skip')), findsOneWidget);
    expect(find.byKey(const Key('home_start_run')), findsNothing);

    await d.skipSetup(tester);
    expect(find.byKey(const Key('setup_skip')), findsNothing);
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
    expect(await d.session.settings.get(SettingKeys.setupDone), '1');
    // Überspringen speichert kein Profil.
    final p = await d.session.profile.read();
    expect(p.birthYear, isNull);
    expect(p.maxHeartRateBpm, isNull);

    await d.stop(tester);
    await d.start(tester, const Locale('de'));
    expect(find.byKey(const Key('setup_skip')), findsNothing);
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
  });

  testWidgets('Einrichtung mit Eingaben speichert das Profil und geht weiter', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await tester.enterText(find.byKey(const Key('profile_birthYear')), '1986');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
    expect((await d.session.profile.read()).birthYear, 1986);
    expect(await d.session.settings.get(SettingKeys.setupDone), '1');
  });

  testWidgets('Einrichtung mit leerem Formular speichern ist erlaubt', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
  });

  testWidgets(
    'abgelehnte Eingabe: Einrichtung bleibt offen, nichts gespeichert',
    (tester) async {
      final d = Device();
      await d.start(tester, const Locale('de'));
      await tester.enterText(find.byKey(const Key('profile_max')), '231');
      await tester.tap(find.byKey(const Key('profile_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setup_skip')), findsOneWidget);
      expect((await d.session.profile.read()).maxHeartRateBpm, isNull);
      expect(await d.session.settings.get(SettingKeys.setupDone), isNull);
      // Überspringen geht trotzdem.
      await d.skipSetup(tester);
      expect(find.byKey(const Key('home_start_run')), findsOneWidget);
    },
  );

  testWidgets('Eingabe mit Hinweis: gespeichert, Hinweis sichtbar, dann weiter '
      '(PAR-016)', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await tester.enterText(find.byKey(const Key('profile_birthYear')), '1986');
    await tester.enterText(find.byKey(const Key('profile_max')), '150');
    await tester.tap(find.byKey(const Key('profile_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('differs from the age-based'), findsOneWidget);
    expect(find.textContaining('Please check.'), findsOneWidget);
    // Dauerhaft sichtbar, nicht nur als flüchtige Snackbar.
    expect(find.text('Saved. Please check the notes.'), findsOneWidget);
    expect(find.byKey(const Key('home_start_run')), findsNothing);
    expect((await d.session.profile.read()).maxHeartRateBpm, 150);
    await tester.tap(find.byKey(const Key('setup_continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_start_run')), findsOneWidget);
  });
}
