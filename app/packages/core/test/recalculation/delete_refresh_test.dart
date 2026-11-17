import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Löschen eines Laufs: Kein Tageswert, in den der Lauf eingegangen ist,
/// bleibt stehen (SEC-0004); die übrigen Tage werden neu gerechnet (ADR-0004).
void main() {
  Future<ValuePair?> longTermOf(RecalcWorld w, String day) async {
    for (final p in await w.session.values.read(ValueOwner.day(day))) {
      if (p.original.key == vo2maxLongTermValueKey) return p;
    }
    return null;
  }

  test('Lauf außerhalb des Fensters, aber in der Glättung: Tageswert danach '
      'neu ohne ihn', () async {
    final w = await RecalcWorld.create();
    // A liegt mehr als 8 Wochen (PAR-043) vor B.
    final a = await w.seedRun(DateTime.utc(2029, 12, 1, 8), speed: 2.5);
    await w.calc().calculateAfterRun(a);
    final b = await w.seedRun(DateTime.utc(2030, 2, 25, 8), speed: 3.5);
    await w.calc().calculateAfterRun(b);
    const dayB = '2030-02-25';
    final bValue = (await runVo2(w.session, b)).current.value!;
    final before = (await longTermOf(w, dayB))!;
    expect(before.current.measurementCount, 1, reason: 'nur B im Fenster');
    expect(
      before.current.value,
      isNot(closeTo(bValue, 1e-9)),
      reason: 'A steckt über die Glättung im Wert',
    );

    w.clock.set(DateTime.utc(2030, 2, 26, 9));
    await w.session.deleteRun(a);
    // Direkt nach dem Löschen ist nichts mehr da, was A enthält.
    // (Die aerobe Effizienz von B rechnet nur mit Läufen ihres Fensters,
    // A ist nicht darin; sie darf bleiben.)
    expect(await longTermOf(w, dayB), isNull);
    expect(
      await w.session.values.read(const ValueOwner.day('2029-12-01')),
      isEmpty,
    );

    await w.calc().refreshAfterDelete();
    final after = (await longTermOf(w, dayB))!;
    expect(after.current.value, closeTo(bValue, 1e-9), reason: 'nur B');
    expect(after.current.computedAt, w.clock.now(), reason: 'neu gerechnet');
    expect(
      after.current.dataFrom!.isBefore(DateTime.utc(2030, 2, 25, 8)),
      isFalse,
    );
    expect(after.current.methodVersion, vo2maxLongTermMethodVersion);
  });

  test('letzter Lauf mit Laufwert gelöscht: keine Tageswerte aus ihm, '
      'Neuberechnung läuft durch', () async {
    final w = await RecalcWorld.create();
    final a = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    await w.calc().calculateAfterRun(a);
    // Ein zweiter Lauf ohne Laufwert (noch nicht gerechnet).
    final c = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
    expect(await runVo2Pairs(w.session, c), isEmpty);
    expect(await w.daysWithValues('2030-02-01', '2030-03-01'), isNotEmpty);

    await w.calc().markRefreshPending(a);
    await w.session.deleteRun(a);
    await w.calc().completePendingRefresh();

    expect(await w.daysWithValues('2029-12-01', '2030-03-31'), isEmpty);
    expect(
      await w.session.settings.get(ValueCalculationService.refreshPendingKey),
      isEmpty,
      reason: 'Merker entfernt: Neuberechnung abgeschlossen',
    );
  });
}
