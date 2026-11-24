import 'package:core/core.dart';
import 'package:test/test.dart';

// PAR-233: Ersatz einer lockeren Einheit durch eine andere Sportart.
// Synthetische Werte: HFmax 190, Ruhepuls 60 → Grenze „locker“ 151 (PAR-111).
const _hr = HeartRateBasis(maxBpm: 190, restingBpm: 60);

PlanUnit _unit(
  int id,
  DateTime day, {
  PlanUnitKind kind = PlanUnitKind.easy,
  int minutes = 40,
  int? runId,
}) => PlanUnit(
  id: id,
  day: day,
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: minutes,
  segments: const [],
  runId: runId,
);

RunFigures _sport({
  int id = 100,
  int minutes = 30,
  int? totalMinutes,
  double? avg = 130,
}) => RunFigures(
  runId: id,
  endedAt: DateTime.utc(2026, 11, 18, 18),
  day: '2026-11-18',
  isRunning: false,
  movingTime: Duration(minutes: minutes),
  totalTime: Duration(minutes: totalMinutes ?? minutes),
  heartRateAverageBpm: avg,
);

void main() {
  // Mittwoch, 18.11.2026; Woche Montag 16.11. bis Sonntag 22.11.
  final wed = DateTime.utc(2026, 11, 18);

  SportReplacementBlock? check({
    PlanUnit? unit,
    RunFigures? sport,
    List<PlanUnit> others = const [],
    Set<int> sportIds = const {100},
    int? rpe,
    double? highHr,
    HeartRateBasis? hr = _hr,
  }) {
    final u = unit;
    return planSportReplacementBlock(
      unit: u,
      sport: sport ?? _sport(),
      units: [?u, ...others],
      sportRunIds: sportIds,
      rpe: rpe,
      highHrMinutes: highHr,
      heartRate: hr,
    );
  }

  group('PAR-233 Ersatz einer lockeren Einheit', () {
    test('locker, 30 von 40 min: erlaubt', () {
      expect(check(unit: _unit(1, wed)), isNull);
    });

    test('26 von 40 min liegt unter zwei Dritteln: zu kurz', () {
      expect(
        check(unit: _unit(1, wed), sport: _sport(minutes: 26)),
        SportReplacementBlock.tooShort,
      );
    });

    test('Grenze zwei Drittel: 20 von 30 min erlaubt, 19 nicht', () {
      expect(
        check(unit: _unit(1, wed, minutes: 30), sport: _sport(minutes: 20)),
        isNull,
      );
      expect(
        check(unit: _unit(1, wed, minutes: 30), sport: _sport(minutes: 19)),
        SportReplacementBlock.tooShort,
      );
    });

    test('Pause zählt nicht: 40 min Dauer, 25 min Bewegung von 40 min '
        'geplant ist zu kurz', () {
      expect(
        check(
          unit: _unit(1, wed),
          sport: _sport(minutes: 25, totalMinutes: 40),
        ),
        SportReplacementBlock.tooShort,
      );
    });

    test('Bewegungszeit entscheidet: 27 min Bewegung bei 40 min Dauer '
        'reicht für 40 min geplant', () {
      expect(
        check(
          unit: _unit(1, wed),
          sport: _sport(minutes: 27, totalMinutes: 40),
        ),
        isNull,
      );
    });

    test('10 min ab 80 % HFmax: zu intensiv (PAR-058)', () {
      expect(
        check(unit: _unit(1, wed), highHr: 10),
        SportReplacementBlock.tooIntensive,
      );
      expect(check(unit: _unit(1, wed), highHr: 9.9), isNull);
    });

    test('RPE 7: zu intensiv (PAR-058)', () {
      expect(
        check(unit: _unit(1, wed), rpe: 7),
        SportReplacementBlock.tooIntensive,
      );
      expect(check(unit: _unit(1, wed), rpe: 6), isNull);
    });

    test('Durchschnittspuls an der Grenze aus PAR-111: nicht locker', () {
      expect(
        check(unit: _unit(1, wed), sport: _sport(avg: 151)),
        SportReplacementBlock.tooIntensive,
      );
      expect(check(unit: _unit(1, wed), sport: _sport(avg: 150.9)), isNull);
    });

    test('ohne Durchschnittspuls oder Pulsbasis nicht bestimmbar', () {
      expect(
        check(unit: _unit(1, wed), sport: _sport(avg: null)),
        SportReplacementBlock.tooIntensive,
      );
      expect(
        check(unit: _unit(1, wed), hr: null),
        SportReplacementBlock.tooIntensive,
      );
    });

    test('nur Art „locker“: lang, hart, Geh-Lauf und Ruhetag nie', () {
      for (final kind in PlanUnitKind.values) {
        final result = check(unit: _unit(1, wed, kind: kind));
        if (kind == PlanUnitKind.easy) {
          expect(result, isNull, reason: kind.name);
        } else {
          expect(result, SportReplacementBlock.noEasyUnit, reason: kind.name);
        }
      }
      expect(check(), SportReplacementBlock.noEasyUnit);
    });

    test(
      'zweiter Ersatz in derselben Woche nicht, in der Folgewoche wieder',
      () {
        final monday = _unit(2, DateTime.utc(2026, 11, 16), runId: 90);
        final ids = {90, 100};
        expect(
          check(unit: _unit(1, wed), others: [monday], sportIds: ids),
          SportReplacementBlock.alreadyReplaced,
        );
        // Sonntag derselben Woche: noch dieselbe Planwoche.
        expect(
          check(
            unit: _unit(1, DateTime.utc(2026, 11, 22)),
            others: [monday],
            sportIds: ids,
          ),
          SportReplacementBlock.alreadyReplaced,
        );
        // Montag danach: neue Woche.
        expect(
          check(
            unit: _unit(1, DateTime.utc(2026, 11, 23)),
            others: [monday],
            sportIds: ids,
          ),
          isNull,
        );
        // Ersatz am Montag der Folgewoche sperrt den Sonntag davor nicht
        // (Wochenwechsel Sonntag/Montag um Mitternacht).
        expect(
          check(
            unit: _unit(1, DateTime.utc(2026, 11, 15)),
            others: [monday],
            sportIds: ids,
          ),
          isNull,
        );
        // Ein Lauf an einer anderen Einheit der Woche zählt nicht als Ersatz.
        expect(
          check(unit: _unit(1, wed), others: [monday], sportIds: {100}),
          isNull,
        );
        // Die Einheit, die die Sporteinheit schon trägt, zählt nicht doppelt.
        expect(check(unit: _unit(1, wed, runId: 100), sportIds: {100}), isNull);
      },
    );
  });
}
