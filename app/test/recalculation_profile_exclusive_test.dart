import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';

/// Die Profiländerung läuft über dieselbe Reihe wie die Berechnung nach dem
/// Lauf: Endet ein Lauf zeitgleich mit einer Änderung der
/// Herzfrequenzbasis, sieht das Angebot den Lauf (FR-0006).
final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));
final DateTime _now = DateTime.utc(2030, 3, 1, 12);

const _before = ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60);
const _after = ProfileRecord(maxHeartRateBpm: 180, restingHeartRateBpm: 60);

/// Schreibt mit, wann [profileChanged] im Dienst beginnt.
class _RecordingService extends RecalculationService {
  _RecordingService({
    required super.session,
    required super.clock,
    required super.calculation,
    required this.order,
  });

  final List<String> order;

  @override
  Future<RecalculationOffer?> profileChanged({
    required ProfileRecord before,
    required ProfileRecord after,
  }) {
    order.add('profil');
    return super.profileChanged(before: before, after: after);
  }
}

ComputedValue _trimp() => ComputedValue(
  key: trimpRunValueKey,
  value: 50,
  unit: pointsUnit,
  computedAt: _now,
  measurementCount: 1,
  sources: const [],
  method: 'edwards-trimp',
  methodVersion: 1,
  parameterVersion: 1,
  quality: ValueQuality.good,
);

void main() {
  late StorageSession session;
  late _RecordingService service;
  late RecalculationController controller;
  late List<String> order;
  var dataChanged = 0;

  setUp(() async {
    session = await FakeStorage().open(_key);
    final clock = FakeClock(_now);
    order = [];
    service = _RecordingService(
      session: session,
      clock: clock,
      calculation: ValueCalculationService(session: session, clock: clock),
      order: order,
    );
    dataChanged = 0;
    controller = RecalculationController(
      service,
      onDataChanged: () => dataChanged++,
    );
  });

  tearDown(() async {
    controller.dispose();
    await service.dispose();
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Ende eines Laufs wie nach dem Laufende: in der Reihe, die Werte werden
  /// erst geschrieben, wenn [gate] aufgeht.
  Future<int> finishRun(Completer<void> gate) => controller.exclusive(() async {
    order.add('lauf-start');
    final run = await session.runs.create(
      startedAt: _now.subtract(const Duration(minutes: 30)),
    );
    await gate.future;
    await session.runs.setState(run.id, RunState.finished, endedAt: _now);
    await session.values.createOriginals(ValueOwner.run(run.id), [_trimp()]);
    order.add('lauf-ende');
    return run.id;
  });

  test('gleichzeitig Lauf-Ende und Profiländerung: Profiländerung wartet, '
      'das Angebot enthält den Lauf', () async {
    final gate = Completer<void>();
    final finishing = finishRun(gate);
    await settle();
    final changing = controller.profileChanged(_before, _after);
    await settle();
    expect(order, [
      'lauf-start',
    ], reason: 'Profiländerung darf nicht neben dem Lauf-Ende laufen');

    gate.complete();
    final runId = await finishing;
    await changing;
    expect(order, ['lauf-start', 'lauf-ende', 'profil']);

    final offer = controller.offer;
    expect(offer, isNotNull, reason: 'kein Angebot darf verloren gehen');
    expect(offer!.causes, {RecalculationCause.heartRateBasis});
    expect(offer.runIds, [runId]);
    final pending = await service.pendingOffer();
    expect(pending?.runIds, [runId]);
    expect(controller.phase, RecalculationPhase.idle);
    expect(dataChanged, 2, reason: 'Lauf-Ende und Profiländerung je einmal');
  });

  test('Profiländerung zuerst: das Lauf-Ende wartet dahinter, ohne Lauf mit '
      'Werten kein Angebot', () async {
    final gate = Completer<void>();
    final blocker = controller.exclusive(() => gate.future);
    final changing = controller.profileChanged(_before, _after);
    final finishing = finishRun(Completer<void>()..complete());
    await settle();
    expect(order, isEmpty, reason: 'beide warten auf die laufende Aktion');

    gate.complete();
    await blocker;
    await changing;
    await finishing;
    expect(order, ['profil', 'lauf-start', 'lauf-ende']);
    // Ohne Läufe mit Werten zum Zeitpunkt der Änderung gibt es kein Angebot;
    // der Lauf wird ohnehin mit dem neuen Profil berechnet.
    expect(controller.offer, isNull);
    expect(await service.pendingOffer(), isNull);
  });

  test('ohne gleichzeitiges Lauf-Ende steht das Angebot nach der Rückkehr '
      'sofort da', () async {
    final runId = await finishRun(Completer<void>()..complete());
    await controller.profileChanged(_before, _after);
    expect(controller.offer?.runIds, [runId]);
    expect(controller.offer?.causes, {RecalculationCause.heartRateBasis});
  });
  test('Profiländerung liest das Angebot neu: zurückgenommenes Angebot '
      'verschwindet aus der Karte', () async {
    await finishRun(Completer<void>()..complete());
    await controller.profileChanged(_before, _after);
    final shown = controller.offer;
    expect(shown, isNotNull);

    // Rücknahme am Controller vorbei: der Strom meldet nur neue Angebote.
    var events = 0;
    final sub = service.offers.listen((_) => events++);
    addTearDown(sub.cancel);
    await service.decline(shown!);
    expect(await service.pendingOffer(), isNull);
    expect(controller.offer, isNotNull, reason: 'Karte zeigt noch den alten');

    // Gleiche Herzfrequenzbasis: kein neues Angebot über den Strom.
    await controller.profileChanged(_after, _after);
    expect(controller.offer, isNull);
    expect(await service.pendingOffer(), isNull);
    expect(controller.phase, RecalculationPhase.idle);
    await settle();
    expect(events, 0, reason: 'nur das Neulesen darf die Karte ändern');
  });

  test('Profiländerung ohne Änderung am offenen Angebot lässt die Karte '
      'unverändert', () async {
    final runId = await finishRun(Completer<void>()..complete());
    await controller.profileChanged(_before, _after);
    final shown = controller.offer;
    expect(shown, isNotNull);

    var events = 0;
    final sub = service.offers.listen((_) => events++);
    addTearDown(sub.cancel);
    await controller.profileChanged(_after, _after);
    expect(controller.offer, same(shown));
    expect(controller.offer?.runIds, [runId]);
    expect(controller.offer?.causes, {RecalculationCause.heartRateBasis});
    final pending = await service.pendingOffer();
    expect(pending?.runIds, [runId]);
    expect(pending?.causes, {RecalculationCause.heartRateBasis});
    expect(controller.phase, RecalculationPhase.idle);
    await settle();
    expect(events, 0);
  });
}
