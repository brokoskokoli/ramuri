import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';

/// FR-0219: „Neu berechnen“ ohne Angebot im Controller. Ein Versuch läuft nur,
/// wenn es einen nicht berechenbaren Lauf gibt und nichts anderes rechnet.
final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Zählt die Versuche; die Liste der nicht berechenbaren Läufe ist steuerbar.
class _CountingService extends RecalculationService {
  _CountingService({
    required super.session,
    required super.clock,
    required super.calculation,
  });

  Set<int> uncomputable = {};
  Completer<void>? hold;
  int retries = 0;

  @override
  Future<Set<int>> uncomputableRuns() async => {...uncomputable};

  @override
  Future<void> retryUncomputable() async {
    retries++;
    await hold?.future;
    uncomputable = {};
  }
}

void main() {
  late _CountingService service;
  late RecalculationController controller;
  var dataChanged = 0;

  setUp(() async {
    final session = await FakeStorage().open(_key);
    final clock = FakeClock(DateTime.utc(2030, 3, 1, 12));
    service = _CountingService(
      session: session,
      clock: clock,
      calculation: ValueCalculationService(
        algorithms: AlgorithmRegistry.standard(),
        session: session,
        clock: clock,
      ),
    );
    dataChanged = 0;
    controller = RecalculationController(
      service,
      onDataChanged: () => dataChanged++,
    );
  });

  tearDown(() => controller.dispose());

  test('ohne nicht berechenbaren Lauf kein Versuch', () async {
    await controller.refreshUncomputable();
    expect(controller.hasUncomputable, isFalse);
    expect(await controller.retryUncomputable(), isFalse);
    expect(service.retries, 0);
    expect(controller.phase, RecalculationPhase.idle);
  });

  test('zweiter Aufruf während des Versuchs löst keinen zweiten aus', () async {
    service.uncomputable = {4};
    await controller.refreshUncomputable();
    expect(controller.hasUncomputable, isTrue);
    final hold = service.hold = Completer<void>();
    final first = controller.retryUncomputable();
    expect(controller.busy, isTrue);
    expect(await controller.retryUncomputable(), isFalse);
    hold.complete();
    expect(await first, isTrue);
    expect(service.retries, 1);
    expect(dataChanged, 1);
    expect(controller.busy, isFalse);
    expect(controller.hasUncomputable, isFalse);
  });
}
