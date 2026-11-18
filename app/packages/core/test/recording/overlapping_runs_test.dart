import 'package:core/core.dart';
import 'package:test/test.dart';

import '../support/overlapping_runs.dart';

/// Läufe überlappen sich nach einem Rücksprung der Wanduhr um höchstens den
/// Sprung; das ist zulässig (ADR-0005 Punkt 7 „Zeitbasis“, FR-0052).
void main() {
  test('Wanduhr springt in Lauf A um −10 min, B startet 2 min nach dem Ende '
      'von A: B beginnt vor dem Ende von A, beide gespeichert', () async {
    final o = await recordOverlappingRuns();
    final a = await o.runA();
    final b = await o.runB();

    expect(a.state, RunState.finished);
    expect(b.state, RunState.finished);
    // A: Sitzungszeit, 20 min trotz Sprung; B: neuer Anker an der Wanduhr.
    expect(a.startedAt, overlapStart);
    expect(a.endedAt, overlapStart.add(const Duration(minutes: 20)));
    expect(b.startedAt, overlapStart.add(const Duration(minutes: 12)));
    expect(b.endedAt, overlapStart.add(const Duration(minutes: 15)));
    expect(b.startedAt.isBefore(a.endedAt!), isTrue);
    // Überlappung höchstens um den Sprung.
    expect(a.endedAt!.difference(b.startedAt) <= -overlapJump, isTrue);

    expect((await o.session.runs.list()).map((r) => r.id).toSet(), {o.a, o.b});
    expect(await o.session.runs.unfinished(), isEmpty);

    // Jeder Lauf hat seine Punkte, alle innerhalb seiner eigenen Spanne.
    for (final (run, count) in [(a, 20 * 60), (b, 3 * 60)]) {
      final raw = await o.session.rawData.read(run.id);
      expect(raw.positions, hasLength(count), reason: 'Lauf ${run.id}');
      expect(raw.heartRates, hasLength(count), reason: 'Lauf ${run.id}');
      for (final t in [
        ...raw.positions.map((p) => p.value.time),
        ...raw.heartRates.map((p) => p.value.time),
      ]) {
        expect(t.isBefore(run.startedAt), isFalse, reason: '$t');
        expect(t.isAfter(run.endedAt!), isFalse, reason: '$t');
      }
    }

    // Abfrage nach Ende: beide Läufe im Zeitraum, keiner fehlt.
    final between = await o.session.runs.finishedBetween(
      overlapStart,
      overlapStart.add(const Duration(hours: 1)),
    );
    expect(between.map((r) => r.id).toSet(), {o.a, o.b});
  });
}
