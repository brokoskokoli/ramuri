import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'section_support.dart';

// PAR-247, PAR-248: Puls, der nicht zum Tempo passt. Alle Läufe synthetisch.

const p = FitnessParameters.v5();

/// HFRuhe 60, HFmax 190: Reserve 130 bpm.
const basis = selBasis;
const rest = 60;
const hrr = 130;

int bpmAt(double share) => (rest + share * hrr).round();

List<TimeSpan> spansOf(
  RunPreprocessing run, {
  double? vo2max = 44,
  HeartRateBasis b = basis,
  FitnessParameters parameters = p,
  BeltTrack? belt,
}) => paceMismatchSpans(
  run: run,
  basis: b,
  longTermVo2max: vo2max,
  parameters: parameters,
  belt: belt,
);

/// 6 min konstant 2,8 m/s, Puls flach bei 0,18 der Reserve, dann in 10 s
/// Sprung auf 0,8 der Reserve; weiter bis [seconds].
SelScenario plateau({int seconds = 900, double high = 0.8}) => SelScenario(
  seconds: seconds,
  speed: (s) => 2.8,
  bpm: (s) {
    if (s <= 360) return bpmAt(0.18);
    if (s >= 370) return bpmAt(high);
    return (bpmAt(0.18) + (bpmAt(high) - bpmAt(0.18)) * (s - 360) / 10).round();
  },
);

/// Spannen als (Start, Ende) zum Vergleichen.
List<(DateTime, DateTime)> se(Iterable<TimeSpan> spans) => [
  for (final s in spans) (s.start, s.end),
];

/// Zeitpunkte der Medianreihe mit `r < bound` (Hilfe für die Erwartung).
List<DateTime> medianBelow(RunPreprocessing run, double bound) => [
  for (final m in run.heartRate.medianSeries)
    if ((m.bpm - rest) / hrr < bound) m.time,
];

void main() {
  group('Erwarteter Puls (PAR-247, FR-0069, FR-0071)', () {
    test('2,8 m/s, VO₂max 44, eben: r_erw ≈ 0,82', () {
      final r = expectedReserveShare(
        metersPerMinute: 2.8 * 60,
        gradient: 0,
        vo2max: 44,
        p: p.vo2max,
      );
      // (0,2 · 168) / (44 − 3,5) = 33,6 / 40,5.
      expect(r, closeTo(33.6 / 40.5, 1e-12));
      expect(r, closeTo(0.82, 0.01));
    });

    test('mit Steigung: Steigungsterm 0,9 · v · G (PAR-027)', () {
      final r = expectedReserveShare(
        metersPerMinute: 2.8 * 60,
        gradient: 0.05,
        vo2max: 44,
        p: p.vo2max,
      );
      expect(r, closeTo((33.6 + 0.9 * 168 * 0.05) / 40.5, 1e-12));
    });

    test('Steigung im Lauf hebt den erwarteten Puls: Spanne erst mit ihr', () {
      // Puls 0,39 der Reserve (unter der Untergrenze) bei 1,5 m/s:
      // eben r_erw = 18/40,5 ≈ 0,44, 0,44 − 0,15 < 0,39 → passt;
      // mit 10 % Steigung r_erw = (18 + 8,1)/40,5 ≈ 0,64 → zu niedrig.
      SelScenario sc(double grade) => SelScenario(
        seconds: 600,
        speed: (s) => 1.5,
        bpm: (s) => bpmAt(0.39),
        altitude: (s, m) => 100 + grade * m,
      );
      expect(spansOf(buildRun(sc(0))), isEmpty);
      expect(spansOf(buildRun(sc(0.1))), isNotEmpty);
    });
  });

  group('Spanne (PAR-247)', () {
    test(
      'Plateau: Spanne ab 1 min bis zum letzten Median unter der Grenze',
      () {
        final run = buildRun(plateau());
        final spans = spansOf(run);
        // r_erw ≈ 0,83, Toleranz ≤ 0,25: die Untergrenze 0,4 bindet.
        final below = medianBelow(run, 0.4);
        final moveStart = run.movement.movingIntervals.first.start;
        final first = run.heartRate.medianSeries
            .map((m) => m.time)
            .firstWhere(
              (t) => t.difference(moveStart) >= p.paceMismatch.noCheckFor,
            );
        expect(se(spans), [(first, below.last)]);
        expect(first, selAt(60));
        // Das Ende liegt auf dem Sprung (Median eines 30-s-Fensters).
        expect(below.last.isAfter(selAt(360)), isTrue);
        expect(below.last.isBefore(selAt(400)), isTrue);
      },
    );

    test('ohne Langzeitwert: Ersatzregel (r < 0,25 bei ≥ 2,0 m/s)', () {
      final run = buildRun(plateau());
      final spans = spansOf(run, vo2max: null);
      expect(se(spans), [(selAt(60), medianBelow(run, 0.25).last)]);
    });

    test('Ersatzregel nur ab 2,0 m/s', () {
      final run = buildRun(
        SelScenario(seconds: 600, speed: (s) => 1.9, bpm: (s) => bpmAt(0.1)),
      );
      expect(spansOf(run, vo2max: null), isEmpty);
      expect(spansOf(run), isNotEmpty);
    });

    test('normaler Anstieg (τ = 60 s, 2,0 bis 3,0 m/s) löst nie aus', () {
      for (final vo2max in [44.0, 60.0]) {
        double speed(int s) => 2.0 + s / 1200;
        final sc = SelScenario(
          seconds: 1200,
          speed: speed,
          bpm: (s) {
            final target = expectedReserveShare(
              metersPerMinute: speed(s) * 60,
              gradient: 0,
              vo2max: vo2max,
              p: p.vo2max,
            );
            final r = target - (target - 0.1) * math.exp(-s / 60);
            return bpmAt(r);
          },
        );
        final run = buildRun(sc);
        expect(spansOf(run, vo2max: vo2max), isEmpty, reason: 'VO₂max $vo2max');
        expect(spansOf(run, vo2max: null), isEmpty);
      }
    });

    test('zu hoher Puls wird nie beanstandet', () {
      final run = buildRun(
        SelScenario(seconds: 600, speed: (s) => 2.8, bpm: (s) => 189),
      );
      expect(spansOf(run), isEmpty);
    });

    test('genau minDuration erfüllt → keine Spanne, darüber eine', () {
      final run = buildRun(plateau());
      final s = spansOf(run).single;
      final exact = p.copyWith(
        paceMismatch: PaceMismatchParameters(minDuration: s.duration),
      );
      expect(spansOf(run, parameters: exact), isEmpty);
      final shorter = p.copyWith(
        paceMismatch: PaceMismatchParameters(
          minDuration: s.duration - const Duration(microseconds: 1),
        ),
      );
      expect(se(spansOf(run, parameters: shorter)), se([s]));
    });

    test('Bedingung genau 1 min (Standard) → keine Spanne', () {
      // Plateau ab Start, Sprung so, dass der letzte Median unter 0,4 genau
      // 60 s nach dem ersten geprüften Zeitpunkt liegt.
      for (var jump = 90; jump <= 150; jump++) {
        final sc = SelScenario(
          seconds: 400,
          speed: (s) => 2.8,
          bpm: (s) => s < jump ? bpmAt(0.18) : bpmAt(0.6),
        );
        final run = buildRun(sc);
        final below = medianBelow(
          run,
          0.4,
        ).where((t) => !t.isBefore(selAt(60)));
        final length = below.last.difference(below.first);
        final spans = spansOf(run);
        if (length == const Duration(minutes: 1)) {
          expect(spans, isEmpty, reason: 'Sprung bei $jump s');
          return;
        }
        expect(spans.isEmpty, length <= const Duration(minutes: 1));
      }
      fail('kein Szenario mit genau 1 min gefunden');
    });

    test('Puls genau auf 0,4 → keine Spanne, knapp darunter eine', () {
      // 112 bpm: (112 − 60)/130 = 0,4.
      SelScenario sc(int bpm) =>
          SelScenario(seconds: 600, speed: (s) => 2.8, bpm: (s) => bpm);
      expect(spansOf(buildRun(sc(112))), isEmpty);
      expect(spansOf(buildRun(sc(111))), isNotEmpty);
    });

    test('Puls genau auf r_erw − Toleranz → keine Prüfung schlägt an; '
        'Toleranzstufe 0,25 bis 3 min, 0,15 danach', () {
      // Band 2,5 m/s (150 m/min), Laufkoeffizient 0,25, VO₂max 78,5:
      // r_erw = 37,5 / 75 = 0,5 exakt. HFmax 188, HFRuhe 60: r = 32/128 = 0,25.
      const b = HeartRateBasis(maxBpm: 188, restingBpm: 60);
      final params = p.copyWith(
        vo2max: const Vo2maxParameters(runCoefficient: 0.25),
        paceMismatch: const PaceMismatchParameters(lowerBound: 1),
      );
      final run = buildRun(
        SelScenario(seconds: 600, speed: (s) => 2.5, bpm: (s) => 92),
      );
      final belt = BeltTrack([
        BeltPiece(
          span: TimeSpan(start: selT0, end: selAt(600)),
          speedMetersPerSecond: 2.5,
          inclinePercent: 0,
        ),
      ]);
      final spans = spansOf(
        run,
        b: b,
        vo2max: 78.5,
        parameters: params,
        belt: belt,
      );
      // Bis 3 min: r = 0,5 − 0,25 → passt. Ab 3 min: 0,25 < 0,35.
      // Das Bandstück endet bei 600 s (Ende exklusiv).
      expect(se(spans), [(selAt(180), selAt(599))]);
      // Ersatzregel: r = 0,25 genau → passt.
      expect(spansOf(run, b: b, vo2max: null, belt: belt), isEmpty);
    });

    test('Pause in der Spanne: zwei getrennte Prüfungen, nach Pausenende '
        'wieder 1 min ohne Prüfung', () {
      final run = buildRun(
        SelScenario(
          seconds: 900,
          speed: (s) => 2.8,
          bpm: (s) => bpmAt(0.18),
          pauses: const [(300, 420)],
        ),
      );
      final spans = spansOf(run);
      expect(spans, hasLength(2));
      expect(spans.first.start, selAt(60));
      expect(spans.first.end.isAfter(selAt(300)), isFalse);
      final resume = run.movement.movingIntervals
          .firstWhere((i) => !i.start.isBefore(selAt(420)))
          .start;
      expect(
        spans.last.start.difference(resume) >= const Duration(minutes: 1),
        isTrue,
      );
      expect(
        spans.last.start.difference(resume) < const Duration(seconds: 62),
        isTrue,
      );
    });

    test('Stillstand < 0,8 m/s unterbricht die Spanne', () {
      final run = buildRun(
        SelScenario(
          seconds: 900,
          speed: (s) => s > 300 && s <= 420 ? 0.0 : 2.8,
          bpm: (s) => bpmAt(0.18),
        ),
      );
      final spans = spansOf(run);
      expect(spans, hasLength(2));
      for (final s in spans) {
        expect(
          s.end.isAfter(selAt(330)) && s.start.isBefore(selAt(420)),
          isFalse,
          reason: '$s',
        );
      }
    });

    test('HFRuhe fehlt → keine Prüfung', () {
      final run = buildRun(plateau());
      expect(spansOf(run, b: const HeartRateBasis(maxBpm: 190)), isEmpty);
      expect(spansOf(run, b: const HeartRateBasis(restingBpm: 60)), isEmpty);
    });

    test('Laufband: Tempo aus den Einstellungen, ohne Tempo keine Prüfung', () {
      final run = buildRun(plateau());
      BeltTrack belt(double speed) => BeltTrack([
        BeltPiece(
          span: TimeSpan(start: selT0, end: selAt(900)),
          speedMetersPerSecond: speed,
          inclinePercent: 0,
        ),
      ]);
      final gps = spansOf(run);
      expect(se(spansOf(run, belt: belt(2.8))), se(gps));
      // Band steht (Tempo 0): keine Bewegung, keine Prüfung.
      expect(spansOf(run, belt: belt(0)), isEmpty);
      // Langsames Band: r_erw = 0,2 · 30 / 40,5 ≈ 0,15 → passt.
      expect(spansOf(run, belt: belt(0.5)), isEmpty);
    });
  });

  group('Fitnesssicht des Pulses (PAR-248)', () {
    test('nach dem Sprung keine Einzellücke > 10 s aus PAR-009; '
        'Vorverarbeitung unverändert', () {
      final run = buildRun(plateau());
      final before = run.heartRate;
      final processedBefore = [...before.processed];
      // Ausgangslage: die Vorverarbeitung verwirft den echten Anstieg.
      final outliers = before.processed
          .where((h) => h.reason == DiscardReason.heartRateOutlier)
          .toList();
      expect(outliers, isNotEmpty);
      expect(
        before.gaps.any((g) => !g.start.isBefore(selAt(360))),
        isTrue,
        reason: 'ohne PAR-248 entsteht nach dem Sprung eine Lücke',
      );
      final spans = spansOf(run);
      final fit = fitnessHeartRateOf(
        heartRate: before,
        spans: spans,
        pauses: const [],
        runStart: selT0,
        until: selAt(900),
        parameters: run.parameters,
      );
      final end = spans.single.end;
      expect(fit.gaps.where((g) => !g.start.isBefore(end)), isEmpty);
      expect(
        fit.processed.where(
          (h) =>
              h.input.time.isAfter(end) &&
              h.reason == DiscardReason.heartRateOutlier,
        ),
        isEmpty,
      );
      // Spannenwerte fehlen (wie eine Pulslücke).
      expect(
        fit.processed
            .where(
              (h) =>
                  !h.input.time.isBefore(selAt(60)) &&
                  !h.input.time.isAfter(end),
            )
            .every((h) => h.state == MeasurementState.unavailable),
        isTrue,
      );
      // Die Vorverarbeitung bleibt, wie sie war.
      expect(run.heartRate, same(before));
      expect(before.processed, processedBefore);
      final again = buildRun(plateau()).heartRate;
      expect(again.averageBpm, before.averageBpm);
      expect(again.maxBpm, before.maxBpm);
      expect(again.gaps.length, before.gaps.length);
    });

    test('ohne Spanne ist die Fitnesssicht der Puls der Vorverarbeitung', () {
      final run = buildRun(steady(600));
      final fit = fitnessHeartRateOf(
        heartRate: run.heartRate,
        spans: const [],
        pauses: const [],
        runStart: selT0,
        until: selAt(780),
        parameters: run.parameters,
      );
      expect(fit, same(run.heartRate));
    });
  });

  group('Abschnittsauswahl (FR-0073, PAR-011)', () {
    test('Abschnitt mit der Spanne bekommt den neuen Grund, danach wieder '
        'Einschwingzeit, dann normal', () {
      final run = buildRun(plateau(seconds: 1500));
      final spans = spansOf(run);
      final fit = fitnessHeartRateOf(
        heartRate: run.heartRate,
        spans: spans,
        pauses: const [],
        runStart: selT0,
        until: selAt(1500),
        parameters: run.parameters,
      );
      final sel = Vo2maxSectionSelector(parameters: p).select(
        run: run.withHeartRate(fit),
        basis: basis,
        runStart: selT0,
        until: selAt(1500),
        paceMismatch: spans,
      );
      final blockEnd = spans.single.end.add(run.parameters.settlingDuration);
      final mismatch = sel.sections
          .where((s) => rulesOf(s).contains(SectionRule.heartRatePaceMismatch))
          .toList();
      expect(mismatch, isNotEmpty);
      for (final s in mismatch) {
        expect(s.status, SectionStatus.rejected);
        expect(s.to.isAfter(blockEnd), isFalse);
      }
      expect(mismatch.last.to, blockEnd);
      final after = sel.sections.where((s) => !s.from.isBefore(blockEnd));
      expect(after, isNotEmpty);
      expect(after.first.from, blockEnd);
      for (final s in after) {
        expect(rulesOf(s), isNot(contains(SectionRule.heartRatePaceMismatch)));
        expect(rulesOf(s), isNot(contains(SectionRule.heartRateGaps)));
      }
      expect(after.any((s) => s.status == SectionStatus.eligible), isTrue);
      // Ohne Spanne: kein Abschnitt mit dem neuen Grund.
      final plain = Vo2maxSectionSelector(parameters: p)
          .select(run: run, basis: basis, runStart: selT0, until: selAt(1500));
      expect(
        plain.sections.where(
          (s) => rulesOf(s).contains(SectionRule.heartRatePaceMismatch),
        ),
        isEmpty,
      );
    });
  });

  group('TRIMP (FR-0092, FR-0197, OQ-0051)', () {
    test('Spanne zählt als Lücke, Abdeckung wie bisher', () {
      final run = buildRun(plateau(seconds: 2400));
      final spans = spansOf(run);
      final fit = fitnessHeartRateOf(
        heartRate: run.heartRate,
        spans: spans,
        pauses: const [],
        runStart: selT0,
        until: selAt(2400),
        parameters: run.parameters,
      );
      for (final trimp in <LoadModel>[
        const EdwardsTrimp(),
        const BanisterTrimp(LoadCoefficients.male),
      ]) {
        TrimpResult value(HeartRateResult hr) => (trimp.compute(
          basis: basis,
          heartRate: hr,
          movement: run.movement,
          p: p,
        ) as FitnessAvailable<TrimpResult>).value;
        final full = value(run.heartRate);
        final cut = value(fit);
        expect(cut.coveredMicros, lessThan(full.coveredMicros));
        expect(
          cut.movingMicros - cut.coveredMicros,
          greaterThanOrEqualTo(spans.single.duration.inMicroseconds),
        );
        // Spanne ≈ 5,5 min von 40 min: unter 100 %, über 80 % → unvollständig.
        expect(cut.incomplete, isTrue);
      }
    });

    test('unter 80 % Abdeckung kein Wert (OQ-0051)', () {
      final run = buildRun(plateau(seconds: 900));
      final spans = spansOf(run);
      final fit = fitnessHeartRateOf(
        heartRate: run.heartRate,
        spans: spans,
        pauses: const [],
        runStart: selT0,
        until: selAt(900),
        parameters: run.parameters,
      );
      final r = const EdwardsTrimp().compute(
        basis: basis,
        heartRate: fit,
        movement: run.movement,
        p: p,
      );
      expect(r, isA<FitnessUnavailable<TrimpResult>>());
    });
  });
}
