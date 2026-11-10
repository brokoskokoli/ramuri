import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Regelversion der Fassung (NFR-0001, ADR-0010 Punkt 2 und 7)', () {
    test('die Gesamtversion trägt die Version jeder Teilmethode', () {
      const v = PlanVersion.current;
      expect(v.parametersPart, planParameterVersion);
      expect(v.walkRunPart, walkRunMethodVersion);
      expect(v.targetIntensityPart, targetIntensityMethodVersion);
      expect(v.method, planMethod);
      expect(v.methodVersion, planMethodVersion);
      for (final p in [
        planParameterVersion,
        walkRunMethodVersion,
        targetIntensityMethodVersion,
      ]) {
        expect(p, inInclusiveRange(1, 999));
      }
    });

    test('jede Änderung einer Teilmethode macht die Fassung veraltet', () {
      const c = PlanVersion.current;
      expect(c.isCurrent, isTrue);
      PlanVersion with_({int? method, int? parameter}) => PlanVersion(
        methodVersion: method ?? c.methodVersion,
        parameterVersion: parameter ?? c.parameterVersion,
      );
      expect(with_(method: c.methodVersion + 1).isCurrent, isFalse);
      expect(with_(parameter: c.parameterVersion + 1000000).isCurrent, isFalse);
      expect(with_(parameter: c.parameterVersion + 1000).isCurrent, isFalse);
      expect(with_(parameter: c.parameterVersion + 1).isCurrent, isFalse);
      expect(const PlanVersion(method: 'other').isCurrent, isFalse);
    });

    test('die Methode einer Einheit folgt ihrer Art, nicht der Fassung', () {
      const v = PlanVersion.current;
      expect(v.unitMethod(walkRun: true), (
        walkRunMethod,
        walkRunMethodVersion,
      ));
      expect(v.unitMethod(walkRun: false), (planMethod, planMethodVersion));
    });
  });
}
