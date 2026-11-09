import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('Variationskoeffizient: Grundgesamtheit, Mittel <= 0 unendlich', () {
    expect(variationCoefficient([3, 3, 3]), 0);
    // Mittel 3, Abweichung sqrt(2/3).
    expect(variationCoefficient([2, 3, 4]), closeTo(0.2722, 1e-4));
    expect(variationCoefficient([0, 0]), double.infinity);
    expect(variationCoefficient([-1, -2]), double.infinity);
  });
}
