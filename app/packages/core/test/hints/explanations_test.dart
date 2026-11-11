import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Erklärungsbausteine (FR-0179 bis FR-0181) und Karte „Erholung“ (FR-0107,
/// OQ-0077): jede Erklärung aus den Daten belegt, ohne Daten nichts.
void main() {
  final today = DateTime.utc(2030, 3, 1);
  DateTime ago(int n) => today.subtract(Duration(days: n));

  group('Fitnessentwicklung', () {
    test('Anstieg von 43 auf 46 aus 5 Läufen, alle Zahlen aus den Daten', () {
      final e = explainFitnessDevelopment([
        FitnessPoint(ago(40), 43),
        FitnessPoint(ago(30), 44),
        FitnessPoint(ago(20), 44.5),
        FitnessPoint(ago(10), 45),
        FitnessPoint(ago(1), 46),
      ], today: today)!;
      expect(e.kind, ExplanationKind.fitnessDevelopment);
      expect(e.code, 'up');
      expect(e.evidenceOf(EvidenceKey.fromValue), 43);
      expect(e.evidenceOf(EvidenceKey.toValue), 46);
      expect(e.evidenceOf(EvidenceKey.fromDay), ago(40));
      expect(e.evidenceOf(EvidenceKey.toDay), ago(1));
      expect(e.evidenceOf(EvidenceKey.runCount), 5);
    });

    test('Richtung: fallend und gleich', () {
      expect(
        explainFitnessDevelopment([
          FitnessPoint(ago(5), 46),
          FitnessPoint(ago(1), 44),
        ], today: today)!.code,
        'down',
      );
      expect(
        explainFitnessDevelopment([
          FitnessPoint(ago(5), 46),
          FitnessPoint(ago(1), 46),
        ], today: today)!.code,
        'same',
      );
    });

    test(
      'ohne Daten, mit einem Lauf oder nur außerhalb des Fensters: nichts',
      () {
        expect(explainFitnessDevelopment(const [], today: today), isNull);
        expect(
          explainFitnessDevelopment([FitnessPoint(ago(3), 45)], today: today),
          isNull,
        );
        expect(
          explainFitnessDevelopment([
            FitnessPoint(ago(60), 40),
            FitnessPoint(ago(50), 41),
            FitnessPoint(ago(2), 45),
          ], today: today),
          isNull,
          reason: 'ein Lauf im Fenster von 42 Tagen genügt nicht',
        );
        expect(
          explainFitnessDevelopment([
            FitnessPoint(ago(42), 40),
            FitnessPoint(ago(2), 45),
          ], today: today),
          isNull,
          reason: '42 Tage zurück liegt schon außerhalb',
        );
        expect(
          explainFitnessDevelopment([
            FitnessPoint(ago(41), 40),
            FitnessPoint(ago(2), 45),
          ], today: today),
          isNotNull,
        );
      },
    );

    test('Werte nach heute und nicht endliche Werte zählen nicht', () {
      expect(
        explainFitnessDevelopment([
          FitnessPoint(ago(5), 40),
          FitnessPoint(ago(-1), 50),
          FitnessPoint(ago(3), double.nan),
        ], today: today),
        isNull,
      );
    });
  });

  group('Trainingsempfehlung', () {
    PlanUnit planned([PlanUnitKind k = PlanUnitKind.easy]) => PlanUnit(
      id: 1,
      day: ago(-1),
      kind: k,
      phase: PlanPhase.build,
      weekIndex: 0,
      minutes: 40,
      segments: const [],
    );
    LoadDay load({
      double? atl = 60,
      double? ctl = 40,
      Set<LoadProvisionalReason> atlP = const {},
      Set<LoadProvisionalReason> ctlP = const {},
    }) => LoadDay(
      day: today,
      load: 50,
      atl: atl,
      ctl: ctl,
      tsb: null,
      tsbPercentMean7: null,
      flags: const {},
      atlProvisionalReasons: atlP,
      ctlProvisionalReasons: ctlP,
      unitCount: 1,
      ratedUnits: 1,
      convertedUnits: 0,
      unratedUnits: 0,
    );

    test('Einheit und gesicherte Belastung: beides belegt', () {
      final e = explainTrainingRecommendation(
        plannedUnit: planned(),
        load: load(),
      )!;
      expect(e.code, 'withLoad');
      expect(e.evidenceOf(EvidenceKey.plannedKind), 'easy');
      expect(e.evidenceOf(EvidenceKey.shortTermLoad), 60);
      expect(e.evidenceOf(EvidenceKey.longTermLoad), 40);
    });

    test('vorläufige oder fehlende Belastung wird nicht als Grund genannt', () {
      for (final l in [
        load(atlP: {LoadProvisionalReason.startup}),
        load(ctlP: {LoadProvisionalReason.startup}),
        load(atl: null),
        load(ctl: null),
        null,
      ]) {
        final e = explainTrainingRecommendation(
          plannedUnit: planned(),
          load: l,
        )!;
        expect(e.code, 'planOnly');
        expect(e.evidenceOf(EvidenceKey.shortTermLoad), isNull);
        expect(e.evidenceOf(EvidenceKey.longTermLoad), isNull);
      }
    });

    test('ohne Einheit oder Ruhetag: keine Erklärung', () {
      expect(
        explainTrainingRecommendation(plannedUnit: null, load: load()),
        isNull,
      );
      expect(
        explainTrainingRecommendation(
          plannedUnit: planned(PlanUnitKind.rest),
          load: load(),
        ),
        isNull,
      );
    });
  });

  group('Planänderung', () {
    PlanVersionRecord record(Map<String, Object?> summary) => PlanVersionRecord(
      id: 4,
      goalId: 1,
      createdAt: today,
      validFrom: ago(-2),
      trigger: PlanTrigger.weekly,
      reason: 'weekly',
      version: const PlanVersion(),
      inputsJson: '{}',
      summaryJson: jsonEncode(summary),
    );

    test('Auslöser, Grund und Alt-Neu-Bild aus der Fassung', () {
      final e = explainPlanChange(
        record({'larger': true, 'changedUnitCount': 3}),
      );
      expect(e.kind, ExplanationKind.planChange);
      expect(e.code, 'weekly');
      expect(e.evidenceOf(EvidenceKey.trigger), 'weekly');
      expect(e.evidenceOf(EvidenceKey.validFrom), ago(-2));
      expect(e.evidenceOf(EvidenceKey.larger), true);
      expect(e.evidenceOf(EvidenceKey.changedUnitCount), 3);
    });

    test('Felder, die die Fassung nicht hat, fehlen auch im Beleg', () {
      final e = explainPlanChange(record({}));
      expect(e.evidenceOf(EvidenceKey.larger), isNull);
      expect(e.evidenceOf(EvidenceKey.changedUnitCount), isNull);
    });
  });

  group('Datenqualität', () {
    ComputedValue value({
      double? v,
      UnavailableReason? reason,
      ValueQuality q = ValueQuality.good,
    }) => ComputedValue(
      key: 'vo2max_run',
      value: v,
      unavailableReason: reason,
      unit: 'ml',
      computedAt: today,
      measurementCount: 12,
      sources: const [],
      method: 'm',
      methodVersion: 2,
      parameterVersion: 1,
      quality: q,
    );

    test('fehlender Wert: Grund-Code und Belege aus den Metadaten', () {
      final e = explainDataQuality(
        value(reason: UnavailableReason.insufficientCoverage),
      )!;
      expect(e.kind, ExplanationKind.dataQuality);
      expect(e.code, 'insufficientCoverage');
      expect(e.evidenceOf(EvidenceKey.valueKey), 'vo2max_run');
      expect(e.evidenceOf(EvidenceKey.method), 'm');
      expect(e.evidenceOf(EvidenceKey.methodVersion), 2);
      expect(e.evidenceOf(EvidenceKey.measurementCount), 12);
    });

    test('vorläufiger Wert: Code der Qualität; guter Wert: nichts', () {
      expect(
        explainDataQuality(value(v: 45, q: ValueQuality.provisional))!.code,
        'quality.provisional',
      );
      expect(explainDataQuality(value(v: 45)), isNull);
      expect(
        explainDataQuality(value(v: 45, q: ValueQuality.sufficient)),
        isNull,
      );
    });

    test(
      'Wert fehlt ohne Grund und ohne schlechte Qualität: nichts erfunden',
      () {
        expect(explainDataQuality(value()), isNull);
      },
    );
  });

  group('Karte „Erholung“ (K58, FR-0107, OQ-0077, PAR-184)', () {
    test('ohne Hinweis kein Modell (ausgeblendet)', () {
      expect(RecoveryCard.from(const HintSelection()), isNull);
      expect(
        RecoveryCard.from(const HintSelection(locked: [HintCode.pause])),
        isNull,
      );
    });

    test('mit Hinweis: nur Code, Knopf und Belege; nie Zahl oder Zustand', () {
      final card = RecoveryCard.from(
        const HintSelection(
          hint: Hint(
            code: HintCode.lowWellbeing,
            action: HintAction.easyRun,
            evidence: [Evidence(EvidenceKey.wellbeing, 2)],
          ),
        ),
      )!;
      expect(card.code, HintCode.lowWellbeing);
      expect(card.action, HintAction.easyRun);
      expect(card.basis.single.key, EvidenceKey.wellbeing);
      // Typ-Ebene: das Modell hat genau diese Felder, keine Zahl, kein Zustand.
      expect(card.toJson().keys.toSet(), {'hint', 'action', 'basis'});
      expect(card.toJson()['hint'], isA<String>());
    });

    test('kein Code und kein Beleg nennt einen Zustand oder Ruhepuls', () {
      const banned = [
        'recovered',
        'ready',
        'fatigue',
        'state',
        'score',
        'risk',
        'resting',
        'restingheart',
        'rhr',
        'hrv',
      ];
      final names = [
        for (final c in HintCode.values) c.name,
        for (final k in EvidenceKey.values) k.name,
      ].map((n) => n.toLowerCase());
      for (final n in names) {
        for (final b in banned) {
          expect(n.contains(b), isFalse, reason: '$n enthält $b');
        }
      }
    });
  });
}
