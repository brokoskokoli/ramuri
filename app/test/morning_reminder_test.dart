// WP33 Teil D: Morgen-Erinnerung in der App (Schalter auf Morgenwerte,
// Neuplanung beim Öffnen, Ausschalten des Entwicklermodus, Alles löschen,
// Tippen) und der Boot-Pfad (plant sie nicht). Fake-Scheduler, keine Werte.
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/morning_trend_screen.dart';
import 'package:running_app/features/reminders/reminder_controller.dart';
import 'package:running_app/features/settings/about_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure/measure_support.dart';

final _clock = FakeClock(DateTime(2026, 11, 15, 5));

Future<(StorageSession, FakeReminderScheduler, ReminderController)> _setup(
  WidgetTester tester, {
  Widget Function(StorageSession session)? home,
  bool dev = true,
  bool enabled = false,
  String locale = 'de',
}) async {
  final session = (await tester.runAsync(() => FakeStorage().open(testKey)))!;
  await tester.runAsync(() async {
    await SettingsDeveloperModeStore(session.settings, _clock).set(dev);
    await MorningReminderSettings(enabled: enabled)
        .save(session.settings, at: _clock.now());
  });
  final scheduler = FakeReminderScheduler(granted: true);
  final controller = ReminderController(scheduler: scheduler, clock: _clock);
  addTearDown(controller.dispose);
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ReminderScope(
      controller: controller,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(locale),
        theme: RamuriTheme.light,
        home: Builder(
          builder: (context) {
            controller.texts = AppReminderTexts(
              AppLocalizations.of(context),
              MaterialLocalizations.of(context),
              use24h: true,
            );
            return home?.call(session) ??
                MorningTrendScreen(
                  session: session,
                  clock: _clock,
                  device: () async => (manufacturer: 'T', model: 'M'),
                );
          },
        ),
      ),
    ),
  );
  controller.attach(session);
  await tester.pumpAndSettle();
  return (session, scheduler, controller);
}

Future<void> _returnToApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  Future<(StorageSession, FakeReminderScheduler, ReminderController)> onTrend(
    WidgetTester tester, {
    bool dev = true,
    bool enabled = false,
  }) => _setup(tester, dev: dev, enabled: enabled);

  testWidgets('Schalter auf Morgenwerte plant, Zeit wählbar, aus streicht', (
    tester,
  ) async {
    final (_, sched, _) = await onTrend(tester);
    expect(find.text('Aus'), findsOneWidget);
    await tester.tap(find.byKey(const Key('morning_reminder_switch')));
    await tester.pumpAndSettle();
    expect(find.text('Täglich um 06:30'), findsOneWidget);
    expect(sched.morningAt, DateTime(2026, 11, 15, 6, 30));
    expect(sched.morningLabels?.channelName, 'Morgenmessung');
    await tester.tap(find.byKey(const Key('morning_reminder_switch')));
    await tester.pumpAndSettle();
    expect(sched.morningAt, isNull);
    expect(find.text('Aus'), findsOneWidget);
  });

  testWidgets('Berechtigung abgelehnt: Schalter bleibt aus', (tester) async {
    final (_, sched, c) = await onTrend(tester);
    sched.granted = false;
    await tester.tap(find.byKey(const Key('morning_reminder_switch')));
    await tester.pumpAndSettle();
    expect(sched.morningAt, isNull);
    expect(c.morningActive, isFalse);
    expect(find.byKey(const Key('morning_reminder_denied')), findsOneWidget);
  });

  testWidgets('Neuplanung beim Öffnen: eingeschaltet und erreichbar', (
    tester,
  ) async {
    final (_, sched, _) = await onTrend(tester, enabled: true);
    expect(sched.morningAt, DateTime(2026, 11, 15, 6, 30));
    sched.morningAt = null; // vom System vergessen (Neustart)
    await _returnToApp(tester);
    expect(sched.morningAt, DateTime(2026, 11, 15, 6, 30));
  });

  testWidgets('ohne Erreichbarkeit wird keine geplant', (tester) async {
    final (_, sched, _) = await onTrend(tester, dev: false, enabled: true);
    await _returnToApp(tester);
    expect(sched.morningAt, isNull);
    expect(sched.morningScheduleCount, 0);
  });

  testWidgets('Ausschalten des Entwicklermodus streicht die Erinnerung', (
    tester,
  ) async {
    late SettingsDeveloperModeStore store;
    final (_, sched, _) = await _setup(
      tester,
      enabled: true,
      home: (session) {
        store = SettingsDeveloperModeStore(session.settings, _clock);
        return AboutScreen(
          developerMode: store,
          appVersion: () async => '0.1.0',
        );
      },
    );
    expect(sched.morningAt, isNotNull);
    // Abschnitt Entwickler: Schalter „Entwicklermodus“ aus.
    await tester.dragUntilVisible(
      find.byType(Switch),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(store.read), isFalse);
    expect(sched.morningAt, isNull);
  });

  testWidgets('„Alles löschen“ (cancelAll) streicht die Erinnerung', (
    tester,
  ) async {
    final (_, sched, c) = await onTrend(tester, enabled: true);
    expect(sched.morningAt, isNotNull);
    await tester.runAsync(c.cancelAll);
    expect(sched.morningAt, isNull);
    expect(c.morning.enabled, isFalse);
  });

  testWidgets('Tippen auf die Erinnerung öffnet die Morgenmessung', (
    tester,
  ) async {
    final (_, sched, c) = await onTrend(tester, enabled: true);
    var opened = 0;
    c.onOpenMorning = () => opened++;
    sched.launchTarget = 'other';
    await _returnToApp(tester);
    expect(opened, 0);
    sched.launchTarget = 'morning';
    await _returnToApp(tester);
    expect(opened, 1);
    await _returnToApp(tester);
    expect(opened, 1, reason: 'Anliegen wird mit dem Lesen gelöscht');
  });

  test('Boot-Pfad plant die Morgen-Erinnerung nicht (Kotlin-Quelle)', () {
    final dir = 'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri';
    final receiver = File('$dir/TrainingReminderReceiver.kt')
        .readAsStringSync();
    // Der Zweig mit Neustart und Update ruft nur die Trainings-Erinnerungen.
    final bootArm = RegExp(
      r'ACTION_BOOT_COMPLETED,[^>]*?->\s*(\S+)',
      dotAll: true,
    ).firstMatch(receiver)!;
    expect(bootArm.group(0), isNot(contains('MorningReminder')));
    expect(bootArm.group(1), 'TrainingReminders.fire(context)');
    expect(
      RegExp(r'MorningReminder\.ACTION_FIRE\s*->').hasMatch(receiver),
      isTrue,
    );
    // Kein eigener Speicher: nichts für den Neustart abgelegt (SEC-0009).
    final morning = File('$dir/MorningReminder.kt').readAsStringSync();
    expect(morning, isNot(contains('getSharedPreferences')));
    expect(morning, isNot(contains('BOOT_COMPLETED')));
    expect(
      File('$dir/TrainingReminders.kt')
          .readAsStringSync()
          .contains('MorningReminder.fire'),
      isFalse,
    );
  });
}
