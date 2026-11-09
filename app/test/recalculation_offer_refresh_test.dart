import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/features/statistics/load_card.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

/// Das angezeigte Faktor-Angebot ist das bestätigte (WP19 NB2b, Review 2
/// Befund 5): nimmt der Belastungsstand ein Angebot zurück oder ersetzt es,
/// erfährt der Controller der Neuberechnung davon; Bestätigen und Ablehnen
/// wirken nie auf einen Wert, den die Karte nicht zeigt.
final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

LoadFactorRecord _factor(double v) => LoadFactorRecord(
  profile: LoadProfile.edwards,
  value: v,
  runs: 12,
  day: DateTime.utc(2030, 3, 1),
);

void main() {
  late StorageSession session;
  late FakeClock clock;
  late RecalculationService service;
  late RecalculationController controller;

  setUp(() async {
    session = await FakeStorage().open(_key);
    await session.profile.save(
      const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    );
    clock = FakeClock(DateTime.utc(2030, 3, 1, 12));
    service = RecalculationService(
      session: session,
      clock: clock,
      calculation: ValueCalculationService(session: session, clock: clock),
    );
    controller = RecalculationController(service);
  });

  tearDown(() => controller.dispose());

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> replacePending(double v) => LoadSettings.writePendingFactor(
    session.settings,
    _factor(v),
    at: clock.now(),
  );

  test(
    'Rücknahme in der Reihe: der Controller zeigt kein Angebot mehr',
    () async {
      await service.requestPersonalFactor(_factor(2.5));
      await settle();
      expect(controller.offer!.personalFactor, _factor(2.5));
      var notified = 0;
      controller.addListener(() => notified++);
      await controller.serializedRefreshingOffer(
        () => service.withdrawPersonalFactor(),
      );
      expect(controller.offer, isNull);
      expect(notified, 1);
      // Ohne Änderung keine Meldung (sonst Schleifen mit dem Neuladen).
      await controller.serializedRefreshingOffer(() async {});
      expect(notified, 1);
    },
  );

  test('Ersetzung in der Reihe: der Controller zeigt den neuen Wert', () async {
    await service.requestPersonalFactor(_factor(2.5));
    await settle();
    await controller.serializedRefreshingOffer(() => replacePending(3.0));
    expect(controller.offer!.personalFactor, _factor(3.0));
  });

  test('Bestätigen eines inzwischen ersetzten Angebots: nichts geändert, '
      'neues Angebot steht da, kein Fehler', () async {
    await service.requestPersonalFactor(_factor(2.5));
    await settle();
    await replacePending(3.0);
    await controller.confirm();
    expect(controller.phase, RecalculationPhase.idle);
    expect(controller.offer!.personalFactor, _factor(3.0));
    expect(await LoadSettings.factor(session.settings), isNull);
  });

  test('Ablehnen eines inzwischen ersetzten Angebots: der neue Wert gilt '
      'nicht als abgelehnt', () async {
    await service.requestPersonalFactor(_factor(2.5));
    await settle();
    await replacePending(3.0);
    await controller.decline();
    expect(controller.phase, RecalculationPhase.idle);
    expect(controller.offer!.personalFactor, _factor(3.0));
    expect(await LoadSettings.declinedFactor(session.settings), isNull);
  });

  testWidgets('Karte Belastung nutzt die Instanz des Controllers: nimmt ihr '
      'Laden das Angebot zurück, ist es auch dort weg', (tester) async {
    await tester.runAsync(() async {
      await service.requestPersonalFactor(_factor(2.5));
      await settle();
      expect(controller.offer, isNotNull);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: RamuriTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LoadCard(
            session: session,
            clock: clock,
            recalculation: controller,
          ),
        ),
      ),
    );
    await tester.runAsync(settle);
    await tester.pump();
    // Keine Läufe: der Faktor ist nicht berechenbar, load() nimmt das Angebot
    // zurück (training_load_service `_syncFactor`).
    expect(await LoadSettings.pendingFactor(session.settings), isNull);
    expect(controller.offer, isNull);
  });
}
