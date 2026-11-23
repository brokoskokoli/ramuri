import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const p = PlanParameters();

  test('PAR-058: Standardwerte 10 min und RPE 7', () {
    expect(p.completedIntensiveMinHighHrMinutes, 10);
    expect(p.completedIntensiveMinRpe, 7);
  });

  test('intensiv durch Puls ohne RPE', () {
    expect(p.completedIntensive(highHrMinutes: 10), isTrue);
    expect(p.completedIntensive(highHrMinutes: 9.99), isFalse);
  });

  test('intensiv durch RPE ohne Puls', () {
    expect(p.completedIntensive(rpe: 7), isTrue);
    expect(p.completedIntensive(rpe: 6), isFalse);
  });

  test('eins von beiden genügt (oder, nicht und)', () {
    expect(p.completedIntensive(rpe: 3, highHrMinutes: 12), isTrue);
    expect(p.completedIntensive(rpe: 8, highHrMinutes: 0), isTrue);
  });

  test('keins von beiden: nicht intensiv', () {
    expect(p.completedIntensive(), isFalse);
    expect(p.completedIntensive(rpe: 6, highHrMinutes: 9), isFalse);
  });

  test('Grenze folgt dem Parameter', () {
    const q = PlanParameters(completedIntensiveMinHighHrMinutes: 11);
    expect(q.completedIntensive(highHrMinutes: 10), isFalse);
    expect(q.completedIntensive(highHrMinutes: 11), isTrue);
  });

  test('Kennzeichen für die Anzeige: ohne Puls und RPE keins (FR-0171)', () {
    expect(p.completedIntensity(), isNull);
    expect(p.completedIntensity(rpe: 8), isTrue);
    expect(p.completedIntensity(rpe: 6), isFalse);
    expect(p.completedIntensity(highHrMinutes: 10), isTrue);
    expect(p.completedIntensity(highHrMinutes: 0), isFalse);
    expect(p.completedIntensity(rpe: 3, highHrMinutes: 12), isTrue);
  });
}
