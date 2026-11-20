import 'package:core/core.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 11, 11, 12);

PredictionRun _run(
  String id, {
  required int daysAgo,
  double? meters = 5000,
  double seconds = 1500,
  int? rpe,
}) => PredictionRun(
  id: id,
  date: DateTime.utc(2026, 11, 11).subtract(Duration(days: daysAgo)),
  movingSeconds: seconds,
  distanceMeters: meters,
  rpe: rpe,
);

void main() {
  group('referenceRunChoices (FR-0129)', () {
    test('nur Läufe ab 3 km der letzten 12 Wochen, neueste zuerst', () {
      final runs = [
        _run('alt', daysAgo: 85),
        _run('grenze', daysAgo: 84),
        _run('kurz', daysAgo: 1, meters: 2999),
        _run('genau3', daysAgo: 2, meters: 3000),
        _run('ohne', daysAgo: 3, meters: null),
        _run('neu', daysAgo: 0),
        _run('zukunft', daysAgo: -1),
        _run('nullzeit', daysAgo: 4, seconds: 0),
        _run('mitte', daysAgo: 10),
      ];
      expect(
        [for (final r in referenceRunChoices(runs: runs, now: _now)) r.id],
        ['neu', 'genau3', 'mitte', 'grenze'],
      );
    });

    test('Fenster und Mindeststrecke aus den Parametern', () {
      final runs = [_run('a', daysAgo: 20), _run('b', daysAgo: 5)];
      const p = PredictionParameters(
        runPickerWindowDays: 10,
        suggestionMinimumMeters: 6000,
      );
      expect(
        referenceRunChoices(runs: runs, now: _now, parameters: p),
        isEmpty,
      );
      expect(
        [
          for (final r in referenceRunChoices(
            runs: runs,
            now: _now,
            parameters: const PredictionParameters(runPickerWindowDays: 10),
          ))
            r.id,
        ],
        ['b'],
      );
    });

    test('gleicher Tag: Reihenfolge des Lesers bleibt', () {
      final runs = [_run('spaet', daysAgo: 1), _run('frueh', daysAgo: 1)];
      expect(
        [for (final r in referenceRunChoices(runs: runs, now: _now)) r.id],
        ['spaet', 'frueh'],
      );
    });

    test('ohne passende Läufe leer', () {
      expect(
        referenceRunChoices(
          runs: [_run('kurz', daysAgo: 1, meters: 2000)],
          now: _now,
        ),
        isEmpty,
      );
    });
  });

  test('isHardEnoughForReference: RPE ab 8, ohne Angabe nicht (PAR-185)', () {
    expect(isHardEnoughForReference(_run('a', daysAgo: 1, rpe: 8)), isTrue);
    expect(isHardEnoughForReference(_run('a', daysAgo: 1, rpe: 10)), isTrue);
    expect(isHardEnoughForReference(_run('a', daysAgo: 1, rpe: 7)), isFalse);
    expect(isHardEnoughForReference(_run('a', daysAgo: 1)), isFalse);
  });

  test(
    'referenceFromRun: bestätigter Lauf mit Lauf-ID und Werten des Laufs',
    () {
      final r = referenceFromRun(_run('42', daysAgo: 3, rpe: 5), _now)!;
      expect(r.kind, ReferenceKind.confirmedRun);
      expect(r.runId, '42');
      expect(r.distanceMeters, 5000);
      expect(r.seconds, 1500);
      expect(r.date, DateTime.utc(2026, 11, 8));
      expect(r.createdAt, _now);
      expect(
        referenceFromRun(_run('x', daysAgo: 1, meters: null), _now),
        isNull,
      );
    },
  );
}
