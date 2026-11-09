import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';

/// Reihe der Neuberechnung (WP19 NB1): Ablehnen und Laden des Belastungsstands
/// laufen nicht parallel zu Bestätigen und den anderen Schreibern.
final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

void main() {
  late StorageSession session;
  late RecalculationService service;
  late RecalculationController controller;
  var dataChanged = 0;

  setUp(() async {
    session = await FakeStorage().open(_key);
    final clock = FakeClock(DateTime.utc(2030, 3, 1, 12));
    service = RecalculationService(
      session: session,
      clock: clock,
      calculation: ValueCalculationService(session: session, clock: clock),
    );
    dataChanged = 0;
    controller = RecalculationController(
      service,
      onDataChanged: () => dataChanged++,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'serialized wartet auf laufende exclusive-Aktionen, in Reihenfolge',
    () async {
      final gate = Completer<void>();
      final order = <String>[];
      final first = controller.exclusive(() async {
        order.add('a-start');
        await gate.future;
        order.add('a-ende');
      });
      final load = controller.serialized(() async => order.add('laden'));
      await settle();
      expect(order, ['a-start']);
      gate.complete();
      await Future.wait([first, load]);
      expect(order, ['a-start', 'a-ende', 'laden']);
    },
  );

  test('serialized meldet keine Datenänderung (sonst Endlosschleife mit dem '
      'Neuladen), exclusive schon', () async {
    await controller.serialized(() async {});
    expect(dataChanged, 0);
    await controller.exclusive(() async {});
    expect(dataChanged, 1);
  });

  test('Ablehnen wartet auf eine laufende Aktion der Reihe', () async {
    final offer = await service.requestPersonalFactor(
      LoadFactorRecord(
        profile: LoadProfile.edwards,
        value: 2,
        runs: 12,
        day: DateTime.utc(2030, 3, 1),
      ),
    );
    await settle();
    expect(controller.offer, isNotNull);
    expect(offer.causes, {RecalculationCause.personalFactor});

    final gate = Completer<void>();
    final running = controller.exclusive(() => gate.future);
    final declining = controller.decline();
    await settle();
    // Noch nicht abgelehnt: das Angebot steht, der Merker ist da.
    expect(await service.pendingOffer(), isNotNull);
    expect(await LoadSettings.pendingFactor(session.settings), isNotNull);
    gate.complete();
    await running;
    await declining;
    expect(await service.pendingOffer(), isNull);
    expect(controller.offer, isNull);
    expect(await LoadSettings.declinedFactor(session.settings), isNotNull);
  });
}
