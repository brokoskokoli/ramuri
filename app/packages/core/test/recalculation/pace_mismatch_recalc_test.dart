import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

// PAR-247 in der Neuberechnung (NFR-0001): alte Daten, neue Version; je Lauf
// gilt der VO₂max-Langzeitwert, der vor seinem Start galt. Synthetische Läufe.

/// HFRuhe 60, HFmax 190 (profile190): Plateau 6 min bei 0,3 der Reserve
/// (99 bpm), danach 0,75 (157,5 → 158 bpm). 0,3 liegt über der Ersatzregel
/// (0,25), aber weit unter r_erw − 0,15 bei einem Langzeitwert um 55.
int plateauBpm(int s) => s < 360 ? 99 : 158;

Future<ComputedValue> vo2maxRun(RecalcWorld w, int id) async =>
    (await w.session.values.read(ValueOwner.run(id)))
        .firstWhere((p) => p.current.key == vo2maxRunValueKey)
        .current;

Future<ComputedValue> valueOf(RecalcWorld w, int id, String key) async =>
    (await w.session.values.read(ValueOwner.run(id)))
        .firstWhere((p) => p.current.key == key)
        .current;

bool hasMismatchReason(ComputedValue v) => v.sections.any(
  (s) => s.reasons.contains(SectionRule.heartRatePaceMismatch.name),
);

void main() {
  test('alte Daten, neue Version: je Lauf der Langzeitwert vor seinem Start, '
      'nie aus dem Lauf selbst', () async {
    final w = await RecalcWorld.create();
    // Reihenfolge der IDs absichtlich nicht nach Startzeit: der späte
    // Plateau-Lauf zuerst, der früheste zuletzt.
    final late = await w.seedRun(
      DateTime.utc(2030, 2, 20, 8),
      speed: 2.8,
      bpmOf: plateauBpm,
    );
    final normal = [
      for (final d in [
        DateTime.utc(2030, 1, 20, 8),
        DateTime.utc(2030, 1, 25, 8),
        DateTime.utc(2030, 2, 1, 8),
        DateTime.utc(2030, 2, 8, 8),
      ])
        await w.seedRun(d),
    ];
    final early = await w.seedRun(
      DateTime.utc(2030, 1, 10, 8),
      speed: 2.8,
      bpmOf: plateauBpm,
    );
    // Alte Daten: mit Parameterversion 4 gerechnet.
    final old = w.calc(
      fitness: const FitnessParameters(parameterVersion: 4),
      pre: const PreprocessingParameters(parameterVersion: 4),
    );
    for (final id in [late, ...normal, early]) {
      await old.calculateAfterRun(id);
    }
    final offer = await w.recalc().checkVersions();
    expect(offer!.causes, contains(RecalculationCause.algorithmVersion));
    await w.recalc().confirm(offer);
    expect(await w.recalc().checkVersions(), isNull);

    final lateValue = await vo2maxRun(w, late);
    final earlyValue = await vo2maxRun(w, early);
    expect(lateValue.parameterVersion, currentParameterVersion);
    // Vor dem frühen Lauf gibt es keinen Langzeitwert: Ersatzregel, 0,3 der
    // Reserve passt. Mit dem eigenen Wert (oder dem späterer Läufe) wäre der
    // Anfang abgelehnt.
    expect(hasMismatchReason(earlyValue), isFalse);
    // Vor dem späten Lauf gilt der Langzeitwert der normalen Läufe.
    expect(hasMismatchReason(lateValue), isTrue);
    for (final id in normal) {
      expect(hasMismatchReason(await vo2maxRun(w, id)), isFalse);
    }
  });

  test('Berechnung nach dem Lauf: Langzeitwert der früheren Läufe; TRIMP '
      'ohne die Spanne', () async {
    final w = await RecalcWorld.create();
    for (final d in [
      DateTime.utc(2030, 1, 20, 8),
      DateTime.utc(2030, 1, 25, 8),
      DateTime.utc(2030, 2, 1, 8),
    ]) {
      await w.calc().calculateAfterRun(await w.seedRun(d));
    }
    final id = await w.seedRun(
      DateTime.utc(2030, 2, 20, 8),
      speed: 2.8,
      bpmOf: plateauBpm,
    );
    await w.calc().calculateAfterRun(id);
    expect(hasMismatchReason(await vo2maxRun(w, id)), isTrue);
    // Derselbe Lauf ohne frühere Läufe (Ersatzregel, keine Spanne).
    final lone = await RecalcWorld.create();
    final loneId = await lone.seedRun(
      DateTime.utc(2030, 2, 20, 8),
      speed: 2.8,
      bpmOf: plateauBpm,
    );
    await lone.calc().calculateAfterRun(loneId);
    final with_ = await valueOf(w, id, trimpRunValueKey);
    final without = await valueOf(lone, loneId, trimpRunValueKey);
    expect(with_.value, isNotNull);
    expect(with_.value!, lessThan(without.value!));
    // Zonen bleiben (Vorverarbeitung unverändert).
    for (final key in [
      zoneBelowValueKey,
      for (var z = 1; z <= zoneValueCount; z++) zoneTimeValueKey(z),
    ]) {
      expect(
        (await valueOf(w, id, key)).value,
        (await valueOf(lone, loneId, key)).value,
        reason: key,
      );
    }
  });

  test('erster Lauf ohne frühere Läufe: Ersatzregel', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(
      DateTime.utc(2030, 2, 20, 8),
      speed: 2.8,
      bpmOf: plateauBpm,
    );
    await w.calc().calculateAfterRun(id);
    expect(hasMismatchReason(await vo2maxRun(w, id)), isFalse);
  });
}
