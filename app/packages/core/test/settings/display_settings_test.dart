import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('Kilometer: Meter durch 1000, Pace unverändert', () {
    expect(DistanceUnit.kilometers.distanceFromMeters(5230), 5.23);
    expect(DistanceUnit.kilometers.paceFromSecondsPerKm(330), 330);
  });

  test('Meilen: 1609,344 m je Meile, Pace je Meile', () {
    expect(DistanceUnit.miles.distanceFromMeters(1609.344), closeTo(1, 1e-12));
    expect(
      DistanceUnit.miles.paceFromSecondsPerKm(300),
      closeTo(482.8032, 1e-9),
    );
  });

  test('Speicherwert: unbekannt oder leer ergibt Kilometer', () {
    expect(DistanceUnit.fromStorage('mi'), DistanceUnit.miles);
    expect(DistanceUnit.fromStorage('km'), DistanceUnit.kilometers);
    expect(DistanceUnit.fromStorage(null), DistanceUnit.kilometers);
    expect(DistanceUnit.fromStorage('xx'), DistanceUnit.kilometers);
  });
}
