import 'package:core/core.dart';
import 'package:test/test.dart';

Duration at(num sec) => Duration(milliseconds: (sec * 1000).round());

void main() {
  group('CadenceEstimator (FR-0202)', () {
    test('gleichmäßige 3 Schritte je Sekunde ergeben 180 je Minute', () {
      final e = CadenceEstimator();
      double? last;
      for (var i = 0; i < 12; i++) {
        last = e.add(at(i / 3));
      }
      expect(last, closeTo(180, 0.5));
    });

    test('weniger als minSteps im Fenster: kein Wert, nie 0', () {
      final e = CadenceEstimator();
      expect(e.add(at(0)), isNull);
      expect(e.add(at(0.5)), isNull);
      expect(e.add(at(1)), isNotNull);
      expect(e.value, isNotNull);
    });

    test('alte Schritte fallen aus dem Fenster', () {
      final e = CadenceEstimator();
      for (var i = 0; i < 10; i++) {
        e.add(at(i * 0.5)); // 120 je Minute
      }
      // 30 s Pause, dann wieder Schritte mit 60 je Minute.
      e.add(at(40));
      e.add(at(41));
      expect(e.add(at(42)), closeTo(60, 0.001));
    });

    test('Schritt nicht nach dem letzten wird ignoriert', () {
      final e = CadenceEstimator();
      e.add(at(0));
      e.add(at(1));
      e.add(at(2));
      final before = e.value;
      expect(e.add(at(2)), isNull);
      expect(e.add(at(1.5)), isNull);
      expect(e.value, before);
    });
  });
}
