import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/reminders/reminder_controller.dart';
import 'package:running_app/features/reminders/reminder_section.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

final _key = Uint8List.fromList(List.filled(32, 7));

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.open,
  runDays: const {1, 3, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

void main() {
  late StorageSession session;
  late FakeReminderScheduler scheduler;
  late ReminderController controller;

  Future<void> pump(WidgetTester tester, {String locale = 'de'}) async {
    session = await FakeStorage().open(_key);
    await (session as GoalStorage).goals.save(
      _goal(),
      today: DateTime.utc(2026, 11, 1),
    );
    controller = ReminderController(
      scheduler: scheduler,
      clock: FakeClock(DateTime.utc(2026, 11, 9, 8)),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: RamuriTheme.light,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            controller.texts = AppReminderTexts(
              AppLocalizations.of(context),
              MaterialLocalizations.of(context),
              use24h: true,
            );
            return Scaffold(
              body: SingleChildScrollView(
                child: ReminderSection(controller: controller),
              ),
            );
          },
        ),
      ),
    );
    controller.attach(session);
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester) => tester
      .widget<SwitchListTile>(find.byKey(const Key('reminder_switch')))
      .value;

  setUp(() => scheduler = FakeReminderScheduler());

  testWidgets('Start: aus, ohne Anfrage der Berechtigung', (tester) async {
    await pump(tester);
    expect(switchValue(tester), isFalse);
    expect(scheduler.requestCount, 0);
    expect(find.byKey(const Key('reminder_denied')), findsNothing);
    expect(await session.settings.get(SettingKeys.reminderEnabled), isNull);
    // Ausgeschaltet: storniert, plant nichts.
    expect(scheduler.replaceCount, 0);
    expect(find.text('18:00'), findsOneWidget);
  });

  testWidgets('Einschalten fragt die Berechtigung; erteilt: an und geplant', (
    tester,
  ) async {
    scheduler.grantOnRequest = true;
    await pump(tester);
    await tester.tap(find.byKey(const Key('reminder_switch')));
    await tester.pumpAndSettle();
    expect(scheduler.requestCount, 1);
    expect(switchValue(tester), isTrue);
    expect(await session.settings.get(SettingKeys.reminderEnabled), '1');
    expect(scheduler.replaceCount, greaterThan(0));
    expect(scheduler.channelName, 'Trainingserinnerungen');
  });

  testWidgets('abgelehnt: Schalter aus mit Erklärung, nichts geplant', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('reminder_switch')));
    await tester.pumpAndSettle();
    expect(scheduler.requestCount, 1);
    expect(switchValue(tester), isFalse);
    expect(find.byKey(const Key('reminder_denied')), findsOneWidget);
    expect(await session.settings.get(SettingKeys.reminderEnabled), '0');
    expect(scheduler.replaceCount, 0);
    // Die Rückkehr aus dem Systemdialog nimmt die Erklärung nicht weg.
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reminder_denied')), findsOneWidget);
  });

  testWidgets(
    'API 31/32: Anfrage meldet erteilt, im System aus: Schalter aus mit Erklärung',
    (tester) async {
      scheduler
        ..grantOnRequest = true
        ..blockedBySystem = true;
      await pump(tester);
      await tester.tap(find.byKey(const Key('reminder_switch')));
      await tester.pumpAndSettle();
      expect(scheduler.requestCount, 1);
      expect(switchValue(tester), isFalse);
      expect(find.byKey(const Key('reminder_denied')), findsOneWidget);
      expect(await session.settings.get(SettingKeys.reminderEnabled), '0');
      expect(scheduler.scheduled, isEmpty);
    },
  );

  testWidgets('Trainingszeit und Vorlauf werden gespeichert', (tester) async {
    scheduler.grantOnRequest = true;
    await pump(tester);
    await tester.tap(find.byKey(const Key('reminder_switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 min'));
    await tester.pumpAndSettle();
    expect(await session.settings.get(SettingKeys.reminderLeadMinutes), '60');
    await controller.setTime(7 * 60 + 45);
    await tester.pumpAndSettle();
    expect(await session.settings.get(SettingKeys.reminderTime), '07:45');
    expect(find.text('07:45'), findsOneWidget);
  });

  testWidgets('im System entzogen: Schalter aus mit Erklärung', (tester) async {
    scheduler.granted = false;
    final s = await FakeStorage().open(_key);
    await const ReminderSettings(enabled: true)
        .save(s.settings, at: DateTime.utc(2026, 11, 9));
    // Neue Sitzung mit gespeichertem „an“ (etwa nach einem Import).
    await pump(tester);
    controller.attach(s);
    await tester.pumpAndSettle();
    expect(switchValue(tester), isFalse);
    expect(find.byKey(const Key('reminder_denied')), findsOneWidget);
    expect(scheduler.scheduled, isEmpty);
  });

  testWidgets('cancelAll storniert („Alles löschen“)', (tester) async {
    scheduler.grantOnRequest = true;
    await pump(tester);
    await tester.tap(find.byKey(const Key('reminder_switch')));
    await tester.pumpAndSettle();
    final before = scheduler.cancelCount;
    await controller.cancelAll();
    await tester.pumpAndSettle();
    expect(scheduler.cancelCount, before + 1);
    expect(switchValue(tester), isFalse);
  });

  testWidgets('Text nennt nur Art und Uhrzeit, de und en', (tester) async {
    for (final (locale, title, body) in [
      ('de', 'Geplantes Training', 'Langer Lauf um 18:00'),
      ('en', 'Planned workout', 'Long run at 18:00'),
    ]) {
      late AppReminderTexts texts;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              texts = AppReminderTexts(
                AppLocalizations.of(context),
                MaterialLocalizations.of(context),
                use24h: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(texts.title, title);
      expect(texts.body(PlanUnitKind.long, 18 * 60), body);
    }
  });
}
