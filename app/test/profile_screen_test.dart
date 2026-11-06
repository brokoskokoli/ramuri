import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

Future<Device> openProfile(WidgetTester tester, Locale locale) async {
  final d = Device();
  await d.start(tester, locale);
  await d.skipSetup(tester);
  await tester.tap(find.byKey(const Key('home_profile')));
  await tester.pumpAndSettle();
  return d;
}

Future<void> enter(WidgetTester tester, String key, String text) =>
    tester.enterText(find.byKey(Key(key)), text);

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('profile_save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('leeres Profil speichern (FR-0002), HFmax-Bitte um Eingabe', (
    tester,
  ) async {
    final d = await openProfile(tester, const Locale('de'));
    expect(find.textContaining('Bitte Geburtsjahr oder maximale'), findsOne);
    await save(tester);
    expect(find.text('Profil gespeichert.'), findsOneWidget);
    expect((await d.session.profile.read()).birthYear, isNull);
  });

  testWidgets('Näherung aus dem Alter ist als Schätzung gekennzeichnet', (
    tester,
  ) async {
    await openProfile(tester, const Locale('de'));
    // Stichtag 2026: Geburtsjahr 1986 = Alter 40 = 180 bpm (FR-0004).
    await enter(tester, 'profile_birthYear', '1986');
    await tester.pump();
    expect(find.textContaining('etwa 180 bpm (Schätzung)'), findsOneWidget);
    expect(find.byKey(const Key('hr_estimated_note')), findsOneWidget);
    expect(find.textContaining('kein gemessener Wert'), findsOneWidget);
  });

  testWidgets('Eingabe hat Vorrang vor der Näherung, ohne Schätzhinweis', (
    tester,
  ) async {
    await openProfile(tester, const Locale('en'));
    await enter(tester, 'profile_birthYear', '1986');
    await enter(tester, 'profile_max', '190');
    await tester.pump();
    expect(find.text('Maximum heart rate: 190 bpm (entered)'), findsOneWidget);
    expect(find.byKey(const Key('hr_estimated_note')), findsNothing);
  });

  testWidgets('Geburtsjahr ab Stichtagsjahr wird abgelehnt (OQ-0065)', (
    tester,
  ) async {
    final d = await openProfile(tester, const Locale('en'));
    for (final y in ['2026', '2027']) {
      await enter(tester, 'profile_birthYear', y);
      await save(tester);
      expect(find.text('The value must be a positive number.'), findsOneWidget);
      expect(find.text('Profile saved.'), findsNothing);
      expect((await d.session.profile.read()).birthYear, isNull);
    }
    await enter(tester, 'profile_birthYear', '2025');
    await save(tester);
    expect(find.text('Profile saved.'), findsOneWidget);
    expect((await d.session.profile.read()).birthYear, 2025);
  });

  testWidgets('HFmax knapp außerhalb wird abgelehnt (PAR-016)', (tester) async {
    final d = await openProfile(tester, const Locale('en'));
    await enter(tester, 'profile_max', '231');
    await save(tester);
    expect(find.textContaining('outside 100 to 230 bpm'), findsOneWidget);
    expect(find.text('Profile saved.'), findsNothing);
    expect((await d.session.profile.read()).maxHeartRateBpm, isNull);
    // Grenze selbst gilt.
    await enter(tester, 'profile_max', '230');
    await save(tester);
    expect(find.text('Profile saved.'), findsOneWidget);
    expect((await d.session.profile.read()).maxHeartRateBpm, 230);
  });

  testWidgets('Ruhepuls: Ablehnung (PAR-017) und Hinweis mit Speichern', (
    tester,
  ) async {
    final d = await openProfile(tester, const Locale('en'));
    await enter(tester, 'profile_resting', '29');
    await save(tester);
    expect(find.textContaining('Resting heart rate outside'), findsOneWidget);
    expect((await d.session.profile.read()).restingHeartRateBpm, isNull);

    await enter(tester, 'profile_resting', '35');
    await save(tester);
    expect(find.textContaining('is unusual. Please check.'), findsOneWidget);
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(find.text('Saved. Please check the notes.'), findsOneWidget);
    expect((await d.session.profile.read()).restingHeartRateBpm, 35);
  });

  testWidgets('Konflikt der Eingaben HFmax <= Ruhepuls wird nicht gespeichert '
      '(PAR-018)', (tester) async {
    final d = await openProfile(tester, const Locale('en'));
    await enter(tester, 'profile_max', '120');
    await enter(tester, 'profile_resting', '120');
    await save(tester);
    expect(find.textContaining('must be higher than the resting'), findsOne);
    expect((await d.session.profile.read()).maxHeartRateBpm, isNull);
  });

  testWidgets(
    'Abgelehnte Eingabe: kein Gespeichert-Hinweis, Fehler vollständig',
    (tester) async {
      final d = await openProfile(tester, const Locale('de'));
      await enter(tester, 'profile_birthYear', '1985');
      await enter(tester, 'profile_resting', '110');
      await enter(tester, 'profile_max', '105');
      await save(tester);
      expect(find.textContaining('Gespeichert'), findsNothing);
      expect(find.byKey(const Key('profile_saved_note')), findsNothing);
      expect(find.textContaining('Saved'), findsNothing);
      // Hinweis zu einem nicht gespeicherten Wert wäre irreführend.
      expect(find.textContaining('Altersnäherung'), findsNothing);
      expect(
        find.textContaining('Es wurde nichts gespeichert'),
        findsOneWidget,
      );
      expect(
        find.textContaining('muss größer sein als der Ruhepuls'),
        findsOneWidget,
      );
      expect((await d.session.profile.read()).maxHeartRateBpm, isNull);
    },
  );

  testWidgets('Zahl nicht lesbar: Meldung, nichts gespeichert', (tester) async {
    final d = await openProfile(tester, const Locale('en'));
    await enter(tester, 'profile_weekly', 'abc');
    await save(tester);
    expect(find.text('Not a valid number.'), findsOneWidget);
    expect(find.text('Profile saved.'), findsNothing);
    expect((await d.session.profile.read()).weeklyRunMinutes, isNull);
  });

  testWidgets('Felder, Trainingstage und Dezimalkomma werden gespeichert', (
    tester,
  ) async {
    final d = await openProfile(tester, const Locale('de'));
    await enter(tester, 'profile_weight', '70,5');
    await enter(tester, 'profile_height', '175');
    await enter(tester, 'profile_weekly', '120');
    await enter(tester, 'profile_usual', '45');
    await tester.tap(find.byKey(const Key('profile_day_0')));
    await tester.tap(find.byKey(const Key('profile_day_6')));
    await save(tester);
    final p = await d.session.profile.read();
    expect(p.bodyWeightKg, 70.5);
    expect(p.bodyHeightMeters, 1.75);
    expect(p.weeklyRunMinutes, 120);
    expect(p.usualTrainingMinutes, 45);
    expect(p.trainingDaysMask, 65);
  });

  testWidgets('gespeichertes Profil wird beim Öffnen geladen', (tester) async {
    final d = Device();
    await d.start(tester, const Locale('en'));
    await d.session.profile.save(
      const ProfileRecord(bodyHeightMeters: 1.8, maxHeartRateBpm: 185),
    );
    await d.skipSetup(tester);
    await tester.tap(find.byKey(const Key('home_profile')));
    await tester.pumpAndSettle();
    expect(find.text('180'), findsOneWidget);
    expect(find.text('185'), findsOneWidget);
  });

  for (final locale in const [Locale('de'), Locale('en')]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('PAR-018 Fehlertext bei 411x914, ${locale.languageCode}, '
          'Textskalierung $scale nicht abgeschnitten', (tester) async {
        await openProfile(tester, locale);
        // Nach dem Harness-Setup setzen: der Harness erzwingt sonst 800x2400.
        tester.view.physicalSize = const Size(411, 914);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await enter(tester, 'profile_max', '120');
        await enter(tester, 'profile_resting', '120');
        // Extent der lazy Liste wird erst beim Scrollen genau: mehrfach.
        for (var i = 0; i < 4; i++) {
          await tester.dragFrom(const Offset(5, 450), const Offset(0, -10000));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('profile_save')));
        await tester.pumpAndSettle();
        // Die Liste baut nur Sichtbares: zum Feld mit dem Fehler scrollen.
        await tester.dragFrom(const Offset(5, 450), const Offset(0, 10000));
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(5, 450), const Offset(0, -300));
        await tester.pumpAndSettle();
        final text = locale.languageCode == 'de'
            ? 'muss größer sein als der Ruhepuls'
            : 'must be higher than the resting';
        final finder = find.textContaining(text);
        expect(finder, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: finder, matching: find.byType(RichText)).first,
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      });
    }
  }

  for (final locale in const [Locale('de'), Locale('en')]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('Hinweistext bei 411x914, ${locale.languageCode}, '
          'Textskalierung $scale nicht abgeschnitten', (tester) async {
        await openProfile(tester, locale);
        tester.view.physicalSize = const Size(411, 914);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        // Stichtag 2026: Alter 40 = 180 bpm, 120 weicht weit ab (Hinweis).
        await enter(tester, 'profile_birthYear', '1986');
        await enter(tester, 'profile_max', '120');
        for (var i = 0; i < 4; i++) {
          await tester.dragFrom(const Offset(5, 450), const Offset(0, -10000));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('profile_save')));
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(5, 450), const Offset(0, 10000));
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(5, 450), const Offset(0, -300));
        await tester.pumpAndSettle();
        final text = locale.languageCode == 'de'
            ? 'Bitte prüfen.'
            : 'Please check.';
        final finder = find.textContaining(text);
        expect(finder, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: finder, matching: find.byType(RichText)).first,
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      });
    }
  }
}
