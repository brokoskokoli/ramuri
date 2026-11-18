import 'package:core/core.dart';
import 'package:test/test.dart';

import '../support/overlapping_runs.dart';
import 'recalc_support.dart';

/// Tageswerte mit zwei Läufen, die sich nach einem Rücksprung der Wanduhr
/// überlappen (ADR-0005 Punkt 7): B beginnt und endet vor dem Ende von A.
void main() {
  // A startet 22:40 UTC, endet nach Sitzungszeit 23:00 UTC (Versatz 0, Tag
  // 25.); B startet 22:52 UTC, endet 22:55 UTC (Versatz +1 h, 23:55 lokal,
  // ebenfalls der 25.). Der Stichtag folgt dem Versatz von A, dem Lauf mit
  // dem späteren Ende: 26. 00:00 UTC. Mit dem Versatz von B wäre er 25.
  // 23:00 UTC, und A (Ende 23:00 UTC) fiele aus dem Tageswert.
  const day = '2030-02-25';
  final start = DateTime.utc(2030, 2, 25, 22, 40);

  Future<(RecalcWorld, OverlappingRuns)> world() async {
    final w = await RecalcWorld.create();
    final o = await recordOverlappingRuns(
      start: start,
      utcOffsetB: const Duration(hours: 1),
      session: w.session,
    );
    w.clock.set(DateTime.utc(2030, 2, 27, 9));
    return (w, o);
  }

  Future<ComputedValue> longTerm(RecalcWorld w) async =>
      (await w.session.values.read(const ValueOwner.day(day)))
          .firstWhere((p) => p.original.key == vo2maxLongTermValueKey)
          .current;

  for (final order in ['A, dann B', 'B, dann A']) {
    test('Tageswerte für beide Läufe ($order), Stichtag mit dem Versatz '
        'des später endenden Laufs', () async {
      final (w, o) = await world();
      final a = await o.runA();
      final b = await o.runB();
      expect(b.startedAt.isBefore(a.endedAt!), isTrue);
      expect(dayOfRun(a), day);
      expect(dayOfRun(b), day);

      final ids = order.startsWith('A') ? [o.a, o.b] : [o.b, o.a];
      for (final id in ids) {
        final r = await w.calc().calculateAfterRun(id);
        expect(r.day, day);
        expect(
          await w.session.values.read(const ValueOwner.day(day)),
          isNotEmpty,
          reason: 'nach Lauf $id',
        );
      }
      for (final id in [o.a, o.b]) {
        expect(
          await w.session.values.read(ValueOwner.run(id)),
          isNotEmpty,
          reason: 'Lauf $id',
        );
      }
      final v = await longTerm(w);
      // B (3 min) hat keine bestimmbare VO₂max; A liegt im Tageswert, sein
      // Ende ist der jüngste Datenpunkt.
      expect(v.value, isNotNull);
      expect(v.measurementCount, 1);
      expect(v.dataFrom, a.startedAt);
      expect(v.dataTo, a.endedAt);
    });
  }
}
