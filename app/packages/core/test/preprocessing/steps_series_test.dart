import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

RawSteps st(num sec, int count) =>
    RawSteps(time: at(sec), source: 'test', count: count);

void main() {
  test('Schritte: Zuordnung über Zeitstempel, rückwärtige Zeit verworfen', () {
    final r = RunPreprocessor(start: t0);
    r.addSteps(st(10, 20));
    r.addSteps(st(20, 45));
    final back = r.addSteps(st(20, 99));
    expect(back.reason, DiscardReason.nonMonotonicTime);
    final l = r.stepsAt(at(26));
    expect(l.value!.count, 45);
    expect(l.age, const Duration(seconds: 6));
    expect(r.stepsAt(at(9)).state, MeasurementState.unavailable);
    final res = r.result(at: at(30)).steps;
    expect(res.processed, hasLength(3));
    expect(res.acceptedValues.map((s) => s.count), [20, 45]);
    expect(res.method, 'steps-series');
    expect(res.parameterVersion, 2);
  });
}
