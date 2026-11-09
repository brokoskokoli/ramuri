import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('Testfall aus der Quelle: 45 min bei RPE 5 ergeben 225 (FR-0095)', () {
    final s = SrpeLoad.compute(duration: const Duration(minutes: 45), rpe: 5);
    expect(s.points, 225);
    expect(s.method, SrpeLoad.methodId);
    expect(s.version, SrpeLoad.methodVersion);
    expect(s.rpe, 5);
    expect(s.duration, const Duration(minutes: 45));
  });

  test('keine Rundung: 90 s bei RPE 7 ergeben 10,5', () {
    expect(
      SrpeLoad.compute(duration: const Duration(seconds: 90), rpe: 7).points,
      10.5,
    );
  });

  test('RPE 0 ergibt 0 Punkte (gültig, nicht „fehlt“)', () {
    expect(
      SrpeLoad.compute(duration: const Duration(minutes: 30), rpe: 0).points,
      0,
    );
  });

  test('Grenzen: RPE außerhalb 0 bis 10 und negative Dauer werfen', () {
    for (final rpe in [-1, 11]) {
      expect(
        () => SrpeLoad.compute(duration: const Duration(minutes: 1), rpe: rpe),
        throwsA(isA<SubjectiveRangeError>()),
      );
    }
    expect(
      () => SrpeLoad.compute(duration: const Duration(minutes: -1), rpe: 3),
      throwsA(isA<SubjectiveRangeError>()),
    );
  });

  test('gespeicherter Wert behält seine Methode und Version', () {
    final s = SrpeLoad.restore(
      points: 12,
      duration: const Duration(minutes: 4),
      rpe: 3,
      method: 'alt',
      version: 0,
    );
    expect(s.method, 'alt');
    expect(s.version, 0);
    expect(
      () => SrpeLoad.restore(
        points: -1,
        duration: Duration.zero,
        rpe: 3,
        method: 'x',
        version: 1,
      ),
      throwsA(isA<SubjectiveRangeError>()),
    );
  });
}
