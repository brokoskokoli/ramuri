// WP33 Teil D: Morgen-Erinnerung planen/streichen je Erreichbarkeit und Schalter.
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

class _Texts implements MorningReminderTexts {
  @override
  MorningReminderLabels get morningLabels => const MorningReminderLabels(
    channelName: 'Morgenmessung',
    title: 'Morgenmessung',
    body: 'Zeit für die Messung am Morgen.',
  );
}

const _validated = {ValidationQuantity.lnRmssdSupine: ValidationState.passed};

void main() {
  // Ortszeit 05:00; Erinnerung 06:30.
  final clock = FakeClock(DateTime(2026, 11, 15, 5));
  late StorageSession session;
  late FakeReminderScheduler scheduler;

  setUp(() async {
    session = await FakeStorage().open(Uint8List(32));
    scheduler = FakeReminderScheduler(granted: true);
  });

  Future<MorningReminderSyncResult> sync({
    bool enabled = true,
    bool dev = false,
    bool validated = false,
  }) async {
    await MorningReminderSettings(enabled: enabled)
        .save(session.settings, at: clock.now());
    await SettingsDeveloperModeStore(session.settings, clock).set(dev);
    return syncMorningReminder(
      settings: session.settings,
      clock: clock,
      scheduler: scheduler,
      texts: _Texts(),
      validationState: validated ? _validated : ppgValidationState,
    );
  }

  group('Planen je Schalter und Erreichbarkeit', () {
    for (final (enabled, dev, validated, expected) in [
      (true, true, false, MorningReminderSyncResult.scheduled),
      (true, false, true, MorningReminderSyncResult.scheduled),
      (true, false, false, MorningReminderSyncResult.unreachable),
      (false, true, false, MorningReminderSyncResult.off),
      (false, false, true, MorningReminderSyncResult.off),
    ]) {
      test('Schalter $enabled, Entwicklermodus $dev, validiert $validated '
          '-> $expected', () async {
        // Eine alte Planung wird in jedem Fall ersetzt oder gestrichen.
        await scheduler.scheduleMorning(
          DateTime(2026, 11, 14, 6, 30),
          labels: _Texts().morningLabels,
        );
        expect(
          await sync(enabled: enabled, dev: dev, validated: validated),
          expected,
        );
        if (expected == MorningReminderSyncResult.scheduled) {
          expect(scheduler.morningAt, DateTime(2026, 11, 15, 6, 30));
        } else {
          expect(scheduler.morningAt, isNull);
        }
      });
    }
  });

  test('ohne Berechtigung wird gestrichen', () async {
    scheduler.granted = false;
    expect(await sync(dev: true), MorningReminderSyncResult.notPermitted);
    expect(scheduler.morningAt, isNull);
    expect(scheduler.morningCancelCount, 1);
  });

  test('Ausschalten des Entwicklermodus streicht eine geplante', () async {
    expect(await sync(dev: true), MorningReminderSyncResult.scheduled);
    expect(scheduler.morningAt, isNotNull);
    await SettingsDeveloperModeStore(session.settings, clock).set(false);
    final r = await syncMorningReminder(
      settings: session.settings,
      clock: clock,
      scheduler: scheduler,
      texts: _Texts(),
    );
    expect(r, MorningReminderSyncResult.unreachable);
    expect(scheduler.morningAt, isNull);
  });

  test('Neuplanung beim Öffnen: nach 06:30 der nächste Tag', () async {
    final late = FakeClock(DateTime(2026, 11, 15, 7));
    await MorningReminderSettings(enabled: true)
        .save(session.settings, at: late.now());
    await SettingsDeveloperModeStore(session.settings, late).set(true);
    await syncMorningReminder(
      settings: session.settings,
      clock: late,
      scheduler: scheduler,
      texts: _Texts(),
    );
    expect(scheduler.morningAt, DateTime(2026, 11, 16, 6, 30));
  });

  test('Text und Kanal ohne Werte, eigener Kanal', () async {
    await sync(dev: true);
    final l = scheduler.morningLabels!;
    expect('${l.title} ${l.body}', isNot(matches(RegExp(r'\d'))));
    expect(
      scheduler.channelName,
      isNull,
    ); // nicht der Kanal der Training-Erinnerungen
    expect(scheduler.scheduled, isEmpty); // nichts in der Trainingsliste
  });

  test('Uhrzeit liegt nur in den Einstellungen; Vorschlag 06:30', () async {
    expect(
      (await MorningReminderSettings.load(session.settings)).minuteOfDay,
      390,
    );
    await const MorningReminderSettings(
      enabled: true,
      minuteOfDay: 7 * 60 + 5,
    ).save(session.settings, at: clock.now());
    expect(
      await session.settings.get(SettingKeys.morningReminderTime),
      '07:05',
    );
  });
}
